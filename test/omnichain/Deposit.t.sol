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

contract OUSDaiUtilityDepositTest is OmnichainBaseTest {
    using OptionsBuilder for bytes;

    // Test deposit of USD
    function test__OUSDaiUtilityDepositUsd() public {
        vm.startPrank(user);

        // LZ receive option
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Send param for USDAI away to USDAI home
        SendParam memory usdaiSendParam = SendParam(
            usdaiAwayEid,
            addressToBytes32(user),
            initialBalance, // will be set later
            /// forge-lint: disable-next-line
            (initialBalance / 10 ** 12) * 10 ** 12,
            receiveOptions,
            "",
            ""
        );

        // Quote the fee for sending USDAI from home to away
        MessagingFee memory fee = usdaiHomeOAdapter.quoteSend(usdaiSendParam, false);

        // Compose message for USDAI away to USDAI home
        bytes memory suffix = abi.encode(initialBalance, "", usdaiSendParam, fee.nativeFee);
        bytes memory composeMsg = abi.encode(IOUSDaiUtility.ActionType.Deposit, suffix);

        // LZ composer option
        bytes memory composerOptions = receiveOptions.addExecutorLzComposeOption(0, 800_000, uint128(fee.nativeFee));

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
        verifyPackets(usdaiAwayEid, addressToBytes32(address(usdaiAwayOAdapter)));

        // Assert that the USDAI away token was minted to the user
        assertEq(usdaiAwayToken.balanceOf(user), initialBalance);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityDepositUsd_LocalDestination() public {
        vm.startPrank(user);

        // LZ receive option
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        // Send param for USDAI away to USDAI home
        SendParam memory usdaiSendParam = SendParam(0, addressToBytes32(user), 0, 0, "", "", "");

        // Compose message for USDAI away to USDAI home
        bytes memory suffix = abi.encode(initialBalance, "", usdaiSendParam, 0);
        bytes memory composeMsg = abi.encode(IOUSDaiUtility.ActionType.Deposit, suffix);

        // LZ composer option
        bytes memory composerOptions = receiveOptions.addExecutorLzComposeOption(0, 800_000, 0);

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
        verifyPackets(usdaiAwayEid, addressToBytes32(address(usdaiAwayOAdapter)));

        // Assert that the USDAI away token was minted to the user
        assertEq(usdai.balanceOf(user), initialBalance);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityDepositUsd_LocalSource_LocalDestination() public {
        vm.startPrank(user);

        // Send param
        SendParam memory usdaiSendParam = SendParam(0, addressToBytes32(user), 0, 0, "", "", "");

        // Data
        bytes memory data = abi.encode(initialBalance, "", usdaiSendParam, 0);

        // Approve the USDAI utility to spend the USD
        usdtHomeToken.approve(address(oUsdaiUtility), initialBalance);

        // Deposit the USD
        oUsdaiUtility.localCompose(IOUSDaiUtility.ActionType.Deposit, address(usdtHomeToken), initialBalance, data);

        // Assert that the USDAI home token was minted to the user
        assertEq(usdai.balanceOf(user), initialBalance);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityDepositUsd_LocalSource_ForeignDestination() public {
        vm.startPrank(user);

        // LZ receive option
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Send param for USDAI away to USDAI home
        SendParam memory usdaiSendParam = SendParam(
            usdaiAwayEid,
            addressToBytes32(user),
            initialBalance, // will be set later
            /// forge-lint: disable-next-line
            (initialBalance / 10 ** 12) * 10 ** 12,
            receiveOptions,
            "",
            ""
        );

        // Quote the fee for sending USDAI from home to away
        MessagingFee memory fee = usdaiHomeOAdapter.quoteSend(usdaiSendParam, false);

        // Data
        bytes memory data = abi.encode(initialBalance, "", usdaiSendParam, fee.nativeFee);

        // Approve the USDAI utility to spend the USD
        usdtHomeToken.approve(address(oUsdaiUtility), initialBalance);

        // Deposit the USD
        oUsdaiUtility.localCompose{value: fee.nativeFee}(
            IOUSDaiUtility.ActionType.Deposit, address(usdtHomeToken), initialBalance, data
        );

        // Verify that the packets were correctly sent to the destination chain
        verifyPackets(usdaiAwayEid, addressToBytes32(address(usdaiAwayOAdapter)));

        // Assert that the USDAI away token was minted to the user
        assertEq(usdaiAwayToken.balanceOf(user), initialBalance);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityDepositUsd_InvalidSend() public {
        vm.startPrank(user);

        // LZ receive option
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Send param for USDAI away to USDAI home
        SendParam memory usdaiSendParam = SendParam(
            usdaiAwayEid,
            addressToBytes32(user),
            initialBalance, // will be set later
            /// forge-lint: disable-next-line
            (initialBalance / 10 ** 12) * 10 ** 12,
            receiveOptions,
            "",
            ""
        );

        // Quote the fee for sending USDAI from home to away
        MessagingFee memory fee = usdaiHomeOAdapter.quoteSend(usdaiSendParam, false);

        // Compose message for USDAI away to USDAI home
        bytes memory suffix = abi.encode(initialBalance, "", usdaiSendParam, 0);
        bytes memory composeMsg = abi.encode(IOUSDaiUtility.ActionType.Deposit, suffix);

        // LZ composer option
        bytes memory composerOptions = receiveOptions.addExecutorLzComposeOption(0, 800_000, uint128(fee.nativeFee));

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

        // Assert that the USD was not sent to the composer receiver
        assertEq(usdai.balanceOf(address(user)), initialBalance);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityDeposit_InsufficientNativeFee_Reverts() public {
        // Amount of base token the utility deposits
        uint256 amount = initialBalance;

        // Credit the utility with the base token as the source adapter would
        vm.prank(address(usdtHomeOAdapter));
        usdtHomeToken.mint(address(oUsdaiUtility), amount);

        // LZ receive option for the onward USDai send
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Cross-chain send param addressed to the user
        SendParam memory sendParam = SendParam(usdaiAwayEid, addressToBytes32(user), amount, 0, receiveOptions, "", "");

        // Quote the onward fee the payload asks the utility to pay
        MessagingFee memory fee = usdaiHomeOAdapter.quoteSend(sendParam, false);

        // Deposit payload declaring the quoted fee
        bytes memory composeMsg =
            abi.encode(IOUSDaiUtility.ActionType.Deposit, abi.encode(uint256(0), "", sendParam, fee.nativeFee));

        // Encode the composer message with the base token adapter as source
        bytes memory message =
            OFTComposeMsgCodec.encode(1, usdtHomeEid, amount, abi.encodePacked(addressToBytes32(user), composeMsg));

        // Native value one wei short of the declared fee
        uint256 value = fee.nativeFee - 1;

        // Utility endpoint that is allowed to call lzCompose
        address endpoint = address(endpoints[usdtHomeEid]);

        // Fund the endpoint to forward the native value
        vm.deal(endpoint, value);

        // Expect the compose to revert rather than deposit and refund
        vm.prank(endpoint);
        vm.expectRevert(IOUSDaiUtility.InsufficientNativeFee.selector);
        oUsdaiUtility.lzCompose{value: value}(address(usdtHomeOAdapter), bytes32(0), message, address(0), "");
    }

    function test__OUSDaiUtilityDeposit_ExactNativeFee_DoesNotRevert() public {
        // Amount of base token the utility deposits
        uint256 amount = initialBalance;

        // Credit the utility with the base token as the source adapter would
        vm.prank(address(usdtHomeOAdapter));
        usdtHomeToken.mint(address(oUsdaiUtility), amount);

        // LZ receive option for the onward USDai send
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Cross-chain send param addressed to the user
        SendParam memory sendParam = SendParam(usdaiAwayEid, addressToBytes32(user), amount, 0, receiveOptions, "", "");

        // Quote the onward fee the payload asks the utility to pay
        MessagingFee memory fee = usdaiHomeOAdapter.quoteSend(sendParam, false);

        // Deposit payload declaring the quoted fee
        bytes memory composeMsg =
            abi.encode(IOUSDaiUtility.ActionType.Deposit, abi.encode(uint256(0), "", sendParam, fee.nativeFee));

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
        verifyPackets(usdaiAwayEid, addressToBytes32(address(usdaiAwayOAdapter)));

        // Assert the onward send went through
        assertEq(usdaiAwayToken.balanceOf(user), amount);
    }

    function test__OUSDaiUtilityDeposit_BlacklistedRecipient_InsufficientFee_RefundsRatherThanReverts() public {
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

        // Deposit payload declaring a fee the compose will not fund
        bytes memory composeMsg =
            abi.encode(IOUSDaiUtility.ActionType.Deposit, abi.encode(uint256(0), "", sendParam, fee.nativeFee));

        // Encode the composer message with the base token adapter as source
        bytes memory message =
            OFTComposeMsgCodec.encode(1, usdtHomeEid, amount, abi.encodePacked(addressToBytes32(user), composeMsg));

        // The blacklist branch sits above the fee guard, so screening wins and the compose returns
        vm.prank(address(endpoints[usdtHomeEid]));
        oUsdaiUtility.lzCompose(address(usdtHomeOAdapter), bytes32(0), message, address(0), "");

        /* The compose refunds instead of reverting, so the utility keeps none of the base token.
        Which address receives the refund is pinned once the payload carries a refund recipient. */
        assertEq(usdtHomeToken.balanceOf(address(oUsdaiUtility)), 0);
    }
}
