// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {OmnichainBaseTest} from "./Base.t.sol";

import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {SendParam, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";

import {IOUSDaiUtility} from "src/interfaces/IOUSDaiUtility.sol";

/**
 * @title Recipient that refuses every incoming ETH transfer
 * @author USD.AI Foundation
 */
contract EthRejector {
    receive() external payable {
        revert("Rejected");
    }
}

contract OUSDaiUtilityRescueTest is OmnichainBaseTest {
    using OptionsBuilder for bytes;

    function test__OUSDaiUtilityRescueERC20() public {
        // Amount of base token stranded on the utility
        uint256 amount = 100 ether;

        // Credit the utility with the base token as the source adapter would
        vm.prank(address(usdtHomeOAdapter));
        usdtHomeToken.mint(address(oUsdaiUtility), amount);

        // Rescue the stranded base token to the user
        oUsdaiUtility.rescueERC20(address(usdtHomeToken), user, amount);

        // Assert that the utility holds no base token
        assertEq(usdtHomeToken.balanceOf(address(oUsdaiUtility)), 0);

        // Assert that the user received the base token
        assertEq(usdtHomeToken.balanceOf(user), initialBalance + amount);
    }

    function test__OUSDaiUtilityRescueERC20_NotAdmin_Reverts() public {
        // Amount of base token stranded on the utility
        uint256 amount = 100 ether;

        // Credit the utility with the base token as the source adapter would
        vm.prank(address(usdtHomeOAdapter));
        usdtHomeToken.mint(address(oUsdaiUtility), amount);

        // Expect the rescue to revert for a caller that is not the admin
        vm.prank(user);
        vm.expectRevert(IOUSDaiUtility.InvalidAddress.selector);
        oUsdaiUtility.rescueERC20(address(usdtHomeToken), user, amount);
    }

    function test__OUSDaiUtilityRescueETH() public {
        // Amount of ETH stranded on the utility
        uint256 amount = 1 ether;

        // Credit the utility with the stranded ETH
        vm.deal(address(oUsdaiUtility), amount);

        // User balance before the rescue
        uint256 balanceBefore = user.balance;

        // Rescue the stranded ETH to the user
        oUsdaiUtility.rescueETH(user, amount);

        // Assert that the utility holds no ETH
        assertEq(address(oUsdaiUtility).balance, 0);

        // Assert that the user received the ETH
        assertEq(user.balance, balanceBefore + amount);
    }

    function test__OUSDaiUtilityRescueETH_NotAdmin_Reverts() public {
        // Amount of ETH stranded on the utility
        uint256 amount = 1 ether;

        // Credit the utility with the stranded ETH
        vm.deal(address(oUsdaiUtility), amount);

        // Expect the rescue to revert for a caller that is not the admin
        vm.prank(user);
        vm.expectRevert(IOUSDaiUtility.InvalidAddress.selector);
        oUsdaiUtility.rescueETH(user, amount);
    }

    function test__OUSDaiUtilityRescue_ZeroRefundRecipient_StrandsThenRescues() public {
        // Amount of base token the utility holds
        uint256 amount = initialBalance;

        // Credit the utility with the base token as the source adapter would
        vm.prank(address(usdtHomeOAdapter));
        usdtHomeToken.mint(address(oUsdaiUtility), amount);

        // LZ receive option for the onward USDai send
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Cross-chain send param addressed to the blacklisted account
        SendParam memory sendParam =
            SendParam(usdaiAwayEid, addressToBytes32(blacklistedUser), amount, 0, receiveOptions, "", "");

        // Quote the onward fee the payload asks the utility to pay
        MessagingFee memory fee = usdaiHomeOAdapter.quoteSend(sendParam, false);

        // Deposit payload leaving the refund recipient unset
        bytes memory composeMsg =
            abi.encode(IOUSDaiUtility.ActionType.Deposit, abi.encode(sendParam, address(0), fee.nativeFee));

        // Encode the composer message with the base token adapter as source
        bytes memory message =
            OFTComposeMsgCodec.encode(1, usdtHomeEid, amount, abi.encodePacked(addressToBytes32(user), composeMsg));

        // Utility endpoint that is allowed to call lzCompose
        address endpoint = address(endpoints[usdtHomeEid]);

        // Fund the endpoint to forward the native value
        vm.deal(endpoint, fee.nativeFee);

        // Screening rejects the destination and the zero refund recipient blocks the refund
        vm.prank(endpoint);
        oUsdaiUtility.lzCompose{value: fee.nativeFee}(address(usdtHomeOAdapter), bytes32(0), message, address(0), "");

        // Assert the base token stranded on the utility
        assertEq(usdtHomeToken.balanceOf(address(oUsdaiUtility)), amount);

        // Assert the forwarded native value stranded on the utility
        assertEq(address(oUsdaiUtility).balance, fee.nativeFee);

        // Assert the blacklisted account received nothing
        assertEq(usdtHomeToken.balanceOf(blacklistedUser), 0);

        // Record the user balances before the rescue
        uint256 tokenBefore = usdtHomeToken.balanceOf(user);
        uint256 ethBefore = user.balance;

        // Sweep the stranded base token and ETH as the admin
        oUsdaiUtility.rescueERC20(address(usdtHomeToken), user, amount);
        oUsdaiUtility.rescueETH(user, fee.nativeFee);

        // Assert the utility holds no base token
        assertEq(usdtHomeToken.balanceOf(address(oUsdaiUtility)), 0);

        // Assert the utility holds no ETH
        assertEq(address(oUsdaiUtility).balance, 0);

        // Assert the rescued base token and ETH reached the user
        assertEq(usdtHomeToken.balanceOf(user) - tokenBefore, amount);
        assertEq(user.balance - ethBefore, fee.nativeFee);
    }

    function test__OUSDaiUtilityRescue_BlacklistedRefundRecipient_WithholdsUsdaiThenRescues() public {
        // Amount of base token the utility deposits
        uint256 amount = initialBalance;

        // Native value forwarded with the compose, refundable once the send fails
        uint256 nativeValue = 1 ether;

        // Credit the utility with the base token as the source adapter would
        vm.prank(address(usdtHomeOAdapter));
        usdtHomeToken.mint(address(oUsdaiUtility), amount);

        // LZ receive option for the onward USDai delivery
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Cross-chain send param addressed to the user, who is not blacklisted
        SendParam memory sendParam = SendParam(usdaiAwayEid, addressToBytes32(user), amount, 0, receiveOptions, "", "");

        // Deposit payload declaring no onward fee, so the guard passes and the send itself is unfunded
        bytes memory composeMsg =
            abi.encode(IOUSDaiUtility.ActionType.Deposit, abi.encode(sendParam, blacklistedUser, uint256(0)));

        // Compose message delivered with the base token
        bytes memory message =
            OFTComposeMsgCodec.encode(1, usdtHomeEid, amount, abi.encodePacked(addressToBytes32(user), composeMsg));

        // Utility endpoint that is allowed to call lzCompose
        address endpoint = address(endpoints[usdtHomeEid]);

        // Fund the endpoint to forward the native value
        vm.deal(endpoint, nativeValue);

        // Refund recipient ETH balance before the compose
        uint256 ethBefore = blacklistedUser.balance;

        // The deposit succeeds and the onward send fails unfunded, refunding the USDai
        vm.prank(endpoint);
        oUsdaiUtility.lzCompose{value: nativeValue}(address(usdtHomeOAdapter), bytes32(0), message, address(0), "");

        // Assert the blacklisted refund recipient received no USDai
        assertEq(usdai.balanceOf(blacklistedUser), 0);

        // Assert the USDai stranded on the utility
        assertEq(usdai.balanceOf(address(oUsdaiUtility)), amount);

        // Assert the native value was refunded even though the USDai was withheld
        assertEq(blacklistedUser.balance - ethBefore, nativeValue);
        assertEq(address(oUsdaiUtility).balance, 0);

        // User USDai balance before the rescue
        uint256 usdaiBefore = usdai.balanceOf(user);

        // Sweep the withheld USDai as the admin
        oUsdaiUtility.rescueERC20(address(usdai), user, amount);

        // Assert the utility holds no USDai
        assertEq(usdai.balanceOf(address(oUsdaiUtility)), 0);

        // Assert the rescued USDai reached the user
        assertEq(usdai.balanceOf(user) - usdaiBefore, amount);
    }

    /* The two cases below cover the require(success) check in rescueETH(), which reverts the
    whole sweep instead of letting a failed transfer look identical to a successful one. */

    function test__OUSDaiUtilityRescueETH_RejectingRecipient_Reverts() public {
        // Recipient that reverts on receiving ETH
        EthRejector rejector = new EthRejector();

        // Amount of ETH stranded on the utility
        uint256 amount = 1 ether;

        // Credit the utility with the stranded ETH
        vm.deal(address(oUsdaiUtility), amount);

        // Expect the rescue to revert because the recipient refuses the transfer
        vm.expectRevert();
        oUsdaiUtility.rescueETH(address(rejector), amount);

        // Assert the recipient received nothing
        assertEq(address(rejector).balance, 0);

        // Assert the ETH is still stranded on the utility
        assertEq(address(oUsdaiUtility).balance, amount);
    }

    function test__OUSDaiUtilityRescueETH_AmountOverBalance_Reverts() public {
        // Amount of ETH stranded on the utility
        uint256 amount = 1 ether;

        // Credit the utility with the stranded ETH
        vm.deal(address(oUsdaiUtility), amount);

        // User balance before the rescue
        uint256 balanceBefore = user.balance;

        // Expect the rescue to revert because the utility cannot fund the transfer
        vm.expectRevert();
        oUsdaiUtility.rescueETH(user, amount + 1);

        // Assert the user received nothing
        assertEq(user.balance, balanceBefore);

        // Assert the ETH is still stranded on the utility
        assertEq(address(oUsdaiUtility).balance, amount);
    }

    /* A call to the zero address succeeds, so require(success) does not catch this case. */

    function test__OUSDaiUtilityRescueETH_ZeroRecipient_BurnsEth() public {
        // Amount of ETH stranded on the utility
        uint256 amount = 1 ether;

        // Credit the utility with the stranded ETH
        vm.deal(address(oUsdaiUtility), amount);

        // Zero address balance before the rescue
        uint256 balanceBefore = address(0).balance;

        // Nothing rejects a zero recipient, so the ETH leaves the utility for good
        oUsdaiUtility.rescueETH(address(0), amount);

        // Assert the ETH went to the zero address
        assertEq(address(0).balance - balanceBefore, amount);

        // Assert the utility holds no ETH
        assertEq(address(oUsdaiUtility).balance, 0);
    }
}
