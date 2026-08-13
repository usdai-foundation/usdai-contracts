// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {OmnichainBaseTest} from "./Base.t.sol";

import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {
    SendParam,
    MessagingFee,
    OFTReceipt,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";

import {IOUSDaiUtility} from "src/interfaces/IOUSDaiUtility.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OUSDaiUtilityDepositAndStakeTest is OmnichainBaseTest {
    using OptionsBuilder for bytes;

    // Test deposit of USD
    function test__OUSDaiUtilityDepositUsdAndStake() public {
        vm.startPrank(user);

        // LZ receive option
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Send param for USDAI away to USDAI home
        SendParam memory usdaiSendParam = SendParam(
            stakedUsdaiAwayEid,
            addressToBytes32(user),
            initialBalance, // will be set later
            /// forge-lint: disable-next-line
            ((initialBalance - 1e6) / 10 ** 12) * 10 ** 12,
            receiveOptions,
            "",
            ""
        );

        // Quote the fee for sending USDAI from home to away
        MessagingFee memory fee = usdaiHomeOAdapter.quoteSend(usdaiSendParam, false);

        // Compose message for USDAI away to USDAI home
        bytes memory suffix = abi.encode(initialBalance - 1e6, usdaiSendParam, user, fee.nativeFee);
        bytes memory composeMsg = abi.encode(IOUSDaiUtility.ActionType.DepositAndStake, suffix);

        // LZ composer option
        bytes memory composerOptions = receiveOptions.addExecutorLzComposeOption(0, 2_000_000, uint128(fee.nativeFee));

        // Send param for USD away to USD home
        SendParam memory usdtSendParam = SendParam({
            dstEid: usdtHomeEid,
            to: addressToBytes32(address(oUsdaiUtility)),
            amountLD: initialBalance,
            minAmountLD: initialBalance,
            extraOptions: composerOptions,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        // Quote the fee for sending USD from away to home
        (,, OFTReceipt memory receipt) = usdtAwayOAdapter.quoteOFT(usdtSendParam);
        usdtSendParam.minAmountLD = receipt.amountReceivedLD;

        // Compose message for USD away to USD home
        fee = usdtAwayOAdapter.quoteSend(usdtSendParam, false);

        // Send the USD
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) =
            usdtAwayOAdapter.send{value: fee.nativeFee}(usdtSendParam, fee, payable(address(this)));

        // Verify that the packets were correctly sent to the destination chain
        verifyPackets(usdtHomeEid, addressToBytes32(address(usdtHomeOAdapter)));

        // Recreate the compose message for the composer receiver
        bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
            msgReceipt.nonce,
            usdtAwayEid,
            oftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(user), composeMsg)
        );

        // Execute the compose message
        this.lzCompose(
            usdtHomeEid,
            address(usdtHomeOAdapter),
            composerOptions,
            msgReceipt.guid,
            address(oUsdaiUtility),
            composerMsg_
        );

        // Verify that the packets were correctly sent to the destination chain
        verifyPackets(stakedUsdaiAwayEid, addressToBytes32(address(stakedUsdaiAwayOAdapter)));

        // Assert that the USDAI away token was minted to the user
        /// forge-lint: disable-next-line
        assertEq(stakedUsdaiAwayToken.balanceOf(user), ((initialBalance - 1e6) / 10 ** 12) * 10 ** 12);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityDepositUsdAndStake_LocalDestination() public {
        vm.startPrank(user);

        // LZ receive option
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        // Send param for USDAI away to USDAI home
        SendParam memory usdaiSendParam = SendParam(0, addressToBytes32(user), 0, 0, "", "", "");

        // Compose message for USDAI away to USDAI home
        bytes memory suffix = abi.encode(initialBalance - 1e6, usdaiSendParam, user, uint256(0));
        bytes memory composeMsg = abi.encode(IOUSDaiUtility.ActionType.DepositAndStake, suffix);

        // LZ composer option
        bytes memory composerOptions = receiveOptions.addExecutorLzComposeOption(0, 2_000_000, 0);

        // Send param for USD away to USD home
        SendParam memory usdtSendParam = SendParam({
            dstEid: usdtHomeEid,
            to: addressToBytes32(address(oUsdaiUtility)),
            amountLD: initialBalance,
            minAmountLD: initialBalance,
            extraOptions: composerOptions,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        // Quote the fee for sending USD from away to home
        (,, OFTReceipt memory receipt) = usdtAwayOAdapter.quoteOFT(usdtSendParam);
        usdtSendParam.minAmountLD = receipt.amountReceivedLD;

        // Compose message for USD away to USD home
        MessagingFee memory fee = usdtAwayOAdapter.quoteSend(usdtSendParam, false);

        // Send the USD
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) =
            usdtAwayOAdapter.send{value: fee.nativeFee}(usdtSendParam, fee, payable(address(this)));

        // Verify that the packets were correctly sent to the destination chain
        verifyPackets(usdtHomeEid, addressToBytes32(address(usdtHomeOAdapter)));

        // Recreate the compose message for the composer receiver
        bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
            msgReceipt.nonce,
            usdtAwayEid,
            oftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(user), composeMsg)
        );

        // Execute the compose message
        this.lzCompose(
            usdtHomeEid,
            address(usdtHomeOAdapter),
            composerOptions,
            msgReceipt.guid,
            address(oUsdaiUtility),
            composerMsg_
        );

        // Verify that the packets were correctly sent to the destination chain
        verifyPackets(stakedUsdaiAwayEid, addressToBytes32(address(stakedUsdaiAwayOAdapter)));

        // Assert that the staked USDAI home token was minted to the user
        assertEq(IERC20(address(stakedUsdai)).balanceOf(user), initialBalance - 1e6);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityDepositUsdAndStake_LocalSource_LocalDestination() public {
        vm.startPrank(user);

        // Send param
        SendParam memory susdaiSendParam = SendParam(0, addressToBytes32(user), 0, 0, "", "", "");

        // Data
        bytes memory data = abi.encode(initialBalance - 1e6, susdaiSendParam, user, uint256(0));

        // Approve the USDAI utility to spend the USD
        usdtHomeToken.approve(address(oUsdaiUtility), initialBalance);

        // Deposit the USD
        oUsdaiUtility.localCompose(
            IOUSDaiUtility.ActionType.DepositAndStake, address(usdtHomeToken), initialBalance, data
        );

        // Assert that the sUSDAI home token was minted to the user
        assertEq(IERC20(address(stakedUsdai)).balanceOf(user), initialBalance - 1e6);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityDepositUsdAndStake_InvalidStake() public {
        vm.startPrank(user);

        // LZ receive option
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Send param for USDAI away to USDAI home
        SendParam memory usdaiSendParam = SendParam(
            stakedUsdaiAwayEid,
            addressToBytes32(user),
            initialBalance, // will be set later
            /// forge-lint: disable-next-line
            ((initialBalance - 1e6) / 10 ** 12) * 10 ** 12,
            receiveOptions,
            "",
            ""
        );

        // Quote the fee for sending USDAI from home to away
        MessagingFee memory fee = usdaiHomeOAdapter.quoteSend(usdaiSendParam, false);

        // Compose message for USDAI away to USDAI home
        bytes memory suffix = abi.encode(initialBalance, usdaiSendParam, user, fee.nativeFee);
        bytes memory composeMsg = abi.encode(IOUSDaiUtility.ActionType.DepositAndStake, suffix);

        // LZ composer option
        bytes memory composerOptions = receiveOptions.addExecutorLzComposeOption(0, 2_000_000, uint128(fee.nativeFee));

        // Send param for USD away to USD home
        SendParam memory usdtSendParam = SendParam({
            dstEid: usdtHomeEid,
            to: addressToBytes32(address(oUsdaiUtility)),
            amountLD: initialBalance,
            minAmountLD: initialBalance,
            extraOptions: composerOptions,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        // Quote the fee for sending USD from away to home
        (,, OFTReceipt memory receipt) = usdtAwayOAdapter.quoteOFT(usdtSendParam);
        usdtSendParam.minAmountLD = receipt.amountReceivedLD;

        // Compose message for USD away to USD home
        fee = usdtAwayOAdapter.quoteSend(usdtSendParam, false);

        // Send the USD
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) =
            usdtAwayOAdapter.send{value: fee.nativeFee}(usdtSendParam, fee, payable(address(this)));

        // Verify that the packets were correctly sent to the destination chain
        verifyPackets(usdtHomeEid, addressToBytes32(address(usdtHomeOAdapter)));

        // Recreate the compose message for the composer receiver
        bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
            msgReceipt.nonce,
            usdtAwayEid,
            oftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(user), composeMsg)
        );

        // Execute the compose message
        this.lzCompose(
            usdtHomeEid,
            address(usdtHomeOAdapter),
            composerOptions,
            msgReceipt.guid,
            address(oUsdaiUtility),
            composerMsg_
        );

        assertEq(usdai.balanceOf(address(user)), initialBalance);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityDepositUsdAndStake_InvalidSend() public {
        vm.startPrank(user);

        // LZ receive option
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Send param for USDAI away to USDAI home
        SendParam memory usdaiSendParam = SendParam(
            stakedUsdaiAwayEid,
            addressToBytes32(user),
            initialBalance, // will be set later
            /// forge-lint: disable-next-line
            ((initialBalance - 1e6) / 10 ** 12) * 10 ** 12,
            receiveOptions,
            "",
            ""
        );

        // Quote the fee for sending USDAI from home to away
        MessagingFee memory fee = usdaiHomeOAdapter.quoteSend(usdaiSendParam, false);

        // Compose message for USDAI away to USDAI home
        bytes memory suffix = abi.encode(initialBalance - 1e6, usdaiSendParam, user, uint256(0));
        bytes memory composeMsg = abi.encode(IOUSDaiUtility.ActionType.DepositAndStake, suffix);

        // LZ composer option
        bytes memory composerOptions = receiveOptions.addExecutorLzComposeOption(0, 2_000_000, uint128(fee.nativeFee));

        // Send param for USD away to USD home
        SendParam memory usdtSendParam = SendParam({
            dstEid: usdtHomeEid,
            to: addressToBytes32(address(oUsdaiUtility)),
            amountLD: initialBalance,
            minAmountLD: initialBalance,
            extraOptions: composerOptions,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        // Quote the fee for sending USD from away to home
        (,, OFTReceipt memory receipt) = usdtAwayOAdapter.quoteOFT(usdtSendParam);
        usdtSendParam.minAmountLD = receipt.amountReceivedLD;

        // Compose message for USD away to USD home
        fee = usdtAwayOAdapter.quoteSend(usdtSendParam, false);

        // Send the USD
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) =
            usdtAwayOAdapter.send{value: fee.nativeFee}(usdtSendParam, fee, payable(address(this)));

        // Verify that the packets were correctly sent to the destination chain
        verifyPackets(usdtHomeEid, addressToBytes32(address(usdtHomeOAdapter)));

        // Recreate the compose message for the composer receiver
        bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
            msgReceipt.nonce,
            usdtAwayEid,
            oftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(user), composeMsg)
        );

        // Execute the compose message
        this.lzCompose(
            usdtHomeEid,
            address(usdtHomeOAdapter),
            composerOptions,
            msgReceipt.guid,
            address(oUsdaiUtility),
            composerMsg_
        );

        assertEq(IERC20(address(stakedUsdai)).balanceOf(address(user)), initialBalance - 1e6);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityDepositUsdAndStake_InvalidStake_LocalSource() public {
        vm.startPrank(user);

        // Send param
        SendParam memory susdaiSendParam = SendParam(0, addressToBytes32(user), 0, 0, "", "", "");

        // Data
        bytes memory data = abi.encode(initialBalance - 1, susdaiSendParam, user, uint256(0));

        // Approve the USDAI utility to spend the USD
        usdtHomeToken.approve(address(oUsdaiUtility), initialBalance);

        // Deposit the USD
        vm.expectRevert(IOUSDaiUtility.DepositAndStakeFailed.selector);
        oUsdaiUtility.localCompose(
            IOUSDaiUtility.ActionType.DepositAndStake, address(usdtHomeToken), initialBalance, data
        );

        vm.stopPrank();
    }

    function test__OUSDaiUtilityDepositAndStake_InsufficientNativeFee_Reverts() public {
        // Amount of base token the utility deposits and stakes
        uint256 amount = initialBalance;

        // Credit the utility with the base token as the source adapter would
        vm.prank(address(usdtHomeOAdapter));
        usdtHomeToken.mint(address(oUsdaiUtility), amount);

        // LZ receive option for the onward staked USDai send
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Cross-chain send param for the staked USDai leg
        SendParam memory sendParam =
            SendParam(stakedUsdaiAwayEid, addressToBytes32(user), amount, 0, receiveOptions, "", "");

        // Quote the onward fee the payload asks the utility to pay
        MessagingFee memory fee = stakedUsdaiHomeOAdapter.quoteSend(sendParam, false);

        // Deposit and stake payload declaring the quoted fee
        bytes memory composeMsg = abi.encode(
            IOUSDaiUtility.ActionType.DepositAndStake, abi.encode(uint256(0), sendParam, user, fee.nativeFee)
        );

        // Encode the composer message with the base token adapter as source
        bytes memory message =
            OFTComposeMsgCodec.encode(1, usdtHomeEid, amount, abi.encodePacked(addressToBytes32(user), composeMsg));

        // Native value one wei short of the declared fee
        uint256 value = fee.nativeFee - 1;

        // Utility endpoint that is allowed to call lzCompose
        address endpoint = address(endpoints[usdtHomeEid]);

        // Fund the endpoint to forward the native value
        vm.deal(endpoint, value);

        // Expect the compose to revert rather than deposit, stake and refund
        vm.prank(endpoint);
        vm.expectRevert(IOUSDaiUtility.InsufficientNativeFee.selector);
        oUsdaiUtility.lzCompose{value: value}(address(usdtHomeOAdapter), bytes32(0), message, address(0), "");
    }

    function test__OUSDaiUtilityDepositUsdAndStake_InvalidDepositToken_RefundsToRefundTo() public {
        // Amount of USDai the utility receives from the wrong source adapter
        uint256 amount = 1_000e18;

        // Give the user USDai and move it into the utility as an inbound compose would
        vm.startPrank(user);
        usdtHomeToken.approve(address(usdai), amount);
        usdai.deposit(address(usdtHomeToken), amount, 0, user);
        usdai.transfer(address(oUsdaiUtility), amount);
        vm.stopPrank();

        // Refund recipient distinct from the destination
        address refundTo = address(0xF00D);

        // Send param for a local destination
        SendParam memory sendParam = SendParam(0, addressToBytes32(user), 0, 0, "", "", "");

        // Deposit and stake payload naming the distinct refund recipient
        bytes memory composeMsg = abi.encode(
            IOUSDaiUtility.ActionType.DepositAndStake, abi.encode(uint256(0), sendParam, refundTo, uint256(0))
        );

        // Compose message delivered with USDai, which is not the base token
        bytes memory message =
            OFTComposeMsgCodec.encode(1, usdaiHomeEid, amount, abi.encodePacked(addressToBytes32(user), composeMsg));

        // Execute the compose from the utility endpoint with the USDai adapter as source
        vm.prank(address(endpoints[usdtHomeEid]));
        oUsdaiUtility.lzCompose(address(usdaiHomeOAdapter), bytes32(0), message, address(0), "");

        // Assert the rejected token went to the refund recipient
        assertEq(usdai.balanceOf(refundTo), amount);

        // Assert the utility kept nothing
        assertEq(usdai.balanceOf(address(oUsdaiUtility)), 0);
    }

    function test__OUSDaiUtilityDepositAndStake_ExactNativeFee_DoesNotRevert() public {
        // Amount of base token the utility deposits and stakes
        uint256 amount = initialBalance;

        // Credit the utility with the base token as the source adapter would
        vm.prank(address(usdtHomeOAdapter));
        usdtHomeToken.mint(address(oUsdaiUtility), amount);

        // Shares the vault mints, less the amount it holds back on its first deposit
        uint256 shares = amount - 1e6;

        // LZ receive option for the onward staked USDai send
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Cross-chain send param for the staked USDai leg
        SendParam memory sendParam =
            SendParam(stakedUsdaiAwayEid, addressToBytes32(user), shares, 0, receiveOptions, "", "");

        // Quote the onward fee the payload asks the utility to pay
        MessagingFee memory fee = stakedUsdaiHomeOAdapter.quoteSend(sendParam, false);

        // Deposit and stake payload declaring the quoted fee
        bytes memory composeMsg = abi.encode(
            IOUSDaiUtility.ActionType.DepositAndStake, abi.encode(uint256(0), sendParam, user, fee.nativeFee)
        );

        // Encode the composer message with the base token adapter as source
        bytes memory message =
            OFTComposeMsgCodec.encode(1, usdtHomeEid, amount, abi.encodePacked(addressToBytes32(user), composeMsg));

        // Utility endpoint that is allowed to call lzCompose
        address endpoint = address(endpoints[usdtHomeEid]);

        // Fund the endpoint to forward the exact fee
        vm.deal(endpoint, fee.nativeFee);

        // Exactly the declared fee clears the guard, which compares with a strict less than
        vm.prank(endpoint);
        oUsdaiUtility.lzCompose{value: fee.nativeFee}(address(usdtHomeOAdapter), bytes32(0), message, address(0), "");

        // Deliver the packet to the away chain
        verifyPackets(stakedUsdaiAwayEid, addressToBytes32(address(stakedUsdaiAwayOAdapter)));

        // Assert the onward send went through
        /// forge-lint: disable-next-line
        assertEq(stakedUsdaiAwayToken.balanceOf(user), (shares / 10 ** 12) * 10 ** 12);
    }

    function test__OUSDaiUtilityDepositAndStake_SendFails_RefundsToRefundToNotDestination() public {
        // Amount of base token the utility deposits and stakes
        uint256 amount = initialBalance;

        // Credit the utility with the base token as the source adapter would
        vm.prank(address(usdtHomeOAdapter));
        usdtHomeToken.mint(address(oUsdaiUtility), amount);

        // Shares the vault mints, less the amount it holds back on its first deposit
        uint256 shares = amount - 1e6;

        // LZ receive option for the onward staked USDai send
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Cross-chain send param addressed to the user
        SendParam memory sendParam =
            SendParam(stakedUsdaiAwayEid, addressToBytes32(user), shares, 0, receiveOptions, "", "");

        // Refund recipient distinct from the destination
        address refundTo = address(0xF00D);

        // Deposit and stake payload declaring no onward fee, so the guard passes and the send itself is unfunded
        bytes memory composeMsg = abi.encode(
            IOUSDaiUtility.ActionType.DepositAndStake, abi.encode(uint256(0), sendParam, refundTo, uint256(0))
        );

        // Encode the composer message with the base token adapter as source
        bytes memory message =
            OFTComposeMsgCodec.encode(1, usdtHomeEid, amount, abi.encodePacked(addressToBytes32(user), composeMsg));

        // Execute the compose with no native value, so the onward send cannot pay its fee
        vm.prank(address(endpoints[usdtHomeEid]));
        oUsdaiUtility.lzCompose(address(usdtHomeOAdapter), bytes32(0), message, address(0), "");

        // Assert the minted shares went to the refund recipient
        assertEq(IERC20(address(stakedUsdai)).balanceOf(refundTo), shares);

        // Assert the destination address received nothing
        assertEq(IERC20(address(stakedUsdai)).balanceOf(user), 0);
    }
}
