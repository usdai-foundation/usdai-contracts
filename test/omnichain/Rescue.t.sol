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
