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
import {OUSDaiUtility} from "src/omnichain/OUSDaiUtility.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

contract OUSDaiUtilityWithdrawTest is OmnichainBaseTest {
    using OptionsBuilder for bytes;

    uint256 internal depositAmount;

    function setUp() public override {
        super.setUp();

        vm.startPrank(user);

        // Deposit USDT to get USDai (USDai now holds USDT for withdrawals)
        usdtHomeToken.approve(address(usdai), initialBalance);
        depositAmount = usdai.deposit(address(usdtHomeToken), initialBalance, initialBalance - 1e6, user);

        vm.stopPrank();
    }

    function _upgradeUtilityForUsdaiEndpoint() internal {
        OUSDaiUtility newImpl = new OUSDaiUtility(
            address(this),
            address(endpoints[usdaiHomeEid]),
            address(usdai),
            address(stakedUsdai),
            address(usdaiHomeOAdapter),
            address(stakedUsdaiHomeOAdapter),
            address(usdtHomeOAdapter)
        );
        address proxyAdmin = address(uint160(uint256(vm.load(address(oUsdaiUtility), ERC1967Utils.ADMIN_SLOT))));
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(oUsdaiUtility)), address(newImpl), ""
        );
    }

    function test__OUSDaiUtilityWithdrawUsd_LocalSource_LocalDestination() public {
        vm.startPrank(user);

        // Send param — local destination
        SendParam memory sendParam = SendParam(0, addressToBytes32(user), 0, 0, "", "", "");

        // Data: sendParam, refundTo, nativeFee
        bytes memory data = abi.encode(sendParam, user, uint256(0));

        // Approve OUSDaiUtility to spend USDai
        usdai.approve(address(oUsdaiUtility), depositAmount);

        // Withdraw USDai → base token locally
        oUsdaiUtility.localCompose(IOUSDaiUtility.ActionType.Withdraw, address(usdai), depositAmount, data);

        // Assert user received base token (USDT)
        assertEq(usdtHomeToken.balanceOf(user), depositAmount);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityWithdrawUsd_LocalSource_ForeignDestination() public {
        vm.startPrank(user);

        // LZ receive option
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Send param — bridge base token to away chain
        SendParam memory sendParam = SendParam(
            usdtAwayEid,
            addressToBytes32(user),
            depositAmount,
            /// forge-lint: disable-next-line
            ((depositAmount - 1e6) / 10 ** 12) * 10 ** 12,
            receiveOptions,
            "",
            ""
        );

        // Quote the fee for sending base token from home to away
        MessagingFee memory fee = usdtHomeOAdapter.quoteSend(sendParam, false);

        // Data: sendParam, refundTo, nativeFee
        bytes memory data = abi.encode(sendParam, user, fee.nativeFee);

        // Approve OUSDaiUtility to spend USDai
        usdai.approve(address(oUsdaiUtility), depositAmount);

        // Withdraw USDai → base token and bridge to away chain
        oUsdaiUtility.localCompose{value: fee.nativeFee}(
            IOUSDaiUtility.ActionType.Withdraw, address(usdai), depositAmount, data
        );

        // Verify packets sent to away chain
        verifyPackets(usdtAwayEid, addressToBytes32(address(usdtAwayOAdapter)));

        // Assert user received base token on away chain
        /// forge-lint: disable-next-line
        assertGe(usdtAwayToken.balanceOf(user), ((depositAmount - 1e6) / 10 ** 12) * 10 ** 12);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityWithdrawUsd() public {
        vm.startPrank(user);

        // First, bridge USDai to away chain so user has USDai on away chain
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        SendParam memory usdaiSendParam = SendParam(
            usdaiAwayEid,
            addressToBytes32(user),
            depositAmount,
            /// forge-lint: disable-next-line
            (depositAmount / 10 ** 12) * 10 ** 12,
            receiveOptions,
            "",
            ""
        );

        usdai.approve(address(usdaiHomeOAdapter), depositAmount);
        MessagingFee memory bridgeFee = usdaiHomeOAdapter.quoteSend(usdaiSendParam, false);
        usdaiHomeOAdapter.send{value: bridgeFee.nativeFee}(usdaiSendParam, bridgeFee, payable(user));
        verifyPackets(usdaiAwayEid, addressToBytes32(address(usdaiAwayOAdapter)));

        /// forge-lint: disable-next-line
        uint256 awayBalance = usdaiAwayToken.balanceOf(user);
        assertGt(awayBalance, 0);

        // Build send param for base token destination (back to away chain)
        SendParam memory baseSendParam = SendParam(
            usdtAwayEid,
            addressToBytes32(user),
            awayBalance,
            /// forge-lint: disable-next-line
            ((awayBalance - 1e6) / 10 ** 12) * 10 ** 12,
            receiveOptions,
            "",
            ""
        );

        // Quote fee for base token bridge
        MessagingFee memory baseFee = usdtHomeOAdapter.quoteSend(baseSendParam, false);

        // Compose message: Withdraw action with data
        bytes memory suffix = abi.encode(baseSendParam, user, baseFee.nativeFee);
        bytes memory composeMsg = abi.encode(IOUSDaiUtility.ActionType.Withdraw, suffix);

        // LZ composer options
        bytes memory composerOptions =
            receiveOptions.addExecutorLzComposeOption(0, 1_050_000, uint128(baseFee.nativeFee));

        // Send USDai from away to home with compose
        SendParam memory usdaiBackParam = SendParam({
            dstEid: usdaiHomeEid,
            to: addressToBytes32(address(oUsdaiUtility)),
            amountLD: awayBalance,
            /// forge-lint: disable-next-line
            minAmountLD: (awayBalance / 10 ** 12) * 10 ** 12,
            extraOptions: composerOptions,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        (,, OFTReceipt memory receipt) = usdaiAwayOAdapter.quoteOFT(usdaiBackParam);
        usdaiBackParam.minAmountLD = receipt.amountReceivedLD;

        MessagingFee memory fee = usdaiAwayOAdapter.quoteSend(usdaiBackParam, false);

        usdaiAwayToken.approve(address(usdaiAwayOAdapter), awayBalance);
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) =
            usdaiAwayOAdapter.send{value: fee.nativeFee}(usdaiBackParam, fee, payable(address(this)));

        // Deliver packet to home chain
        verifyPackets(usdaiHomeEid, addressToBytes32(address(usdaiHomeOAdapter)));

        // Build compose message
        bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
            msgReceipt.nonce,
            usdaiAwayEid,
            oftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(user), composeMsg)
        );

        vm.stopPrank();

        // Upgrade OUSDaiUtility to use USDai endpoint (test setup uses separate endpoints per adapter)
        _upgradeUtilityForUsdaiEndpoint();

        vm.startPrank(user);

        // Execute compose
        this.lzCompose(
            usdaiHomeEid,
            address(usdaiHomeOAdapter),
            composerOptions,
            msgReceipt.guid,
            address(oUsdaiUtility),
            composerMsg_
        );

        // Deliver base token to away chain
        verifyPackets(usdtAwayEid, addressToBytes32(address(usdtAwayOAdapter)));

        // Assert user received base token on away chain
        assertGt(usdtAwayToken.balanceOf(user), 0);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityWithdrawUsd_LocalDestination() public {
        vm.startPrank(user);

        // Bridge USDai to away chain
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        SendParam memory usdaiSendParam = SendParam(
            usdaiAwayEid,
            addressToBytes32(user),
            depositAmount,
            /// forge-lint: disable-next-line
            (depositAmount / 10 ** 12) * 10 ** 12,
            receiveOptions,
            "",
            ""
        );

        usdai.approve(address(usdaiHomeOAdapter), depositAmount);
        MessagingFee memory bridgeFee = usdaiHomeOAdapter.quoteSend(usdaiSendParam, false);
        usdaiHomeOAdapter.send{value: bridgeFee.nativeFee}(usdaiSendParam, bridgeFee, payable(user));
        verifyPackets(usdaiAwayEid, addressToBytes32(address(usdaiAwayOAdapter)));

        /// forge-lint: disable-next-line
        uint256 awayBalance = usdaiAwayToken.balanceOf(user);

        // Send USDai back with compose — local destination (dstEid=0)
        SendParam memory baseSendParam = SendParam(0, addressToBytes32(user), 0, 0, "", "", "");

        bytes memory suffix = abi.encode(baseSendParam, user, uint256(0));
        bytes memory composeMsg = abi.encode(IOUSDaiUtility.ActionType.Withdraw, suffix);

        bytes memory composerOptions = receiveOptions.addExecutorLzComposeOption(0, 1_050_000, 0);

        SendParam memory usdaiBackParam = SendParam({
            dstEid: usdaiHomeEid,
            to: addressToBytes32(address(oUsdaiUtility)),
            amountLD: awayBalance,
            /// forge-lint: disable-next-line
            minAmountLD: (awayBalance / 10 ** 12) * 10 ** 12,
            extraOptions: composerOptions,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        (,, OFTReceipt memory receipt) = usdaiAwayOAdapter.quoteOFT(usdaiBackParam);
        usdaiBackParam.minAmountLD = receipt.amountReceivedLD;

        MessagingFee memory fee = usdaiAwayOAdapter.quoteSend(usdaiBackParam, false);

        usdaiAwayToken.approve(address(usdaiAwayOAdapter), awayBalance);
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) =
            usdaiAwayOAdapter.send{value: fee.nativeFee}(usdaiBackParam, fee, payable(address(this)));

        verifyPackets(usdaiHomeEid, addressToBytes32(address(usdaiHomeOAdapter)));

        bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
            msgReceipt.nonce,
            usdaiAwayEid,
            oftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(user), composeMsg)
        );

        vm.stopPrank();

        // Upgrade OUSDaiUtility to use USDai endpoint
        _upgradeUtilityForUsdaiEndpoint();

        vm.startPrank(user);

        this.lzCompose(
            usdaiHomeEid,
            address(usdaiHomeOAdapter),
            composerOptions,
            msgReceipt.guid,
            address(oUsdaiUtility),
            composerMsg_
        );

        // Assert user received base token on home chain
        assertGe(usdtHomeToken.balanceOf(user), awayBalance - 1e6);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityWithdrawUsd_InvalidDepositToken() public {
        // Mint fresh USDT to user for this test (setUp deposited all USDT into USDai)
        vm.prank(address(usdtHomeOAdapter));
        usdtHomeToken.mint(user, initialBalance);

        vm.startPrank(user);

        // Send param
        SendParam memory sendParam = SendParam(0, addressToBytes32(user), 0, 0, "", "", "");

        // Data with the user as the refund recipient for the rejected token
        bytes memory data = abi.encode(sendParam, user, uint256(0));

        // Approve wrong token
        usdtHomeToken.approve(address(oUsdaiUtility), initialBalance);

        // Try to withdraw with USDT as deposit token — should revert (not USDai)
        vm.expectRevert(IOUSDaiUtility.WithdrawFailed.selector);
        oUsdaiUtility.localCompose(IOUSDaiUtility.ActionType.Withdraw, address(usdtHomeToken), initialBalance, data);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityWithdraw_InsufficientNativeFee_Reverts() public {
        // Amount of USDai the utility holds for the withdrawal
        uint256 amount = 1_000e18;

        // Fund the utility with USDai to withdraw
        vm.prank(user);
        usdai.transfer(address(oUsdaiUtility), amount);

        // LZ receive option for the onward base token send
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Cross-chain send param for the base token leg
        SendParam memory sendParam = SendParam(usdtAwayEid, addressToBytes32(user), amount, 0, receiveOptions, "", "");

        // Quote the onward fee the payload asks the utility to pay
        MessagingFee memory fee = usdtHomeOAdapter.quoteSend(sendParam, false);

        // Withdraw payload declaring the quoted fee
        bytes memory composeMsg =
            abi.encode(IOUSDaiUtility.ActionType.Withdraw, abi.encode(sendParam, user, fee.nativeFee));

        // Encode the composer message with the received USDai amount
        bytes memory message =
            OFTComposeMsgCodec.encode(1, usdaiHomeEid, amount, abi.encodePacked(addressToBytes32(user), composeMsg));

        // Native value one wei short of the declared fee
        uint256 value = fee.nativeFee - 1;

        // Utility endpoint that is allowed to call lzCompose
        address endpoint = address(endpoints[usdtHomeEid]);

        // Fund the endpoint to forward the native value
        vm.deal(endpoint, value);

        // Expect the compose to revert rather than withdraw and refund
        vm.prank(endpoint);
        vm.expectRevert(IOUSDaiUtility.InsufficientNativeFee.selector);
        oUsdaiUtility.lzCompose{value: value}(address(usdaiHomeOAdapter), bytes32(0), message, address(0), "");
    }

    function test__OUSDaiUtilityWithdraw_ExactNativeFee_DoesNotRevert() public {
        // Amount of USDai the utility holds for the withdrawal
        uint256 amount = 1_000e18;

        // Fund the utility with USDai to withdraw
        vm.prank(user);
        usdai.transfer(address(oUsdaiUtility), amount);

        // LZ receive option for the onward base token send
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Cross-chain send param for the base token leg
        SendParam memory sendParam = SendParam(usdtAwayEid, addressToBytes32(user), amount, 0, receiveOptions, "", "");

        // Quote the onward fee the payload asks the utility to pay
        MessagingFee memory fee = usdtHomeOAdapter.quoteSend(sendParam, false);

        // Withdraw payload declaring the quoted fee
        bytes memory composeMsg =
            abi.encode(IOUSDaiUtility.ActionType.Withdraw, abi.encode(sendParam, user, fee.nativeFee));

        // Encode the composer message with the received USDai amount
        bytes memory message =
            OFTComposeMsgCodec.encode(1, usdaiHomeEid, amount, abi.encodePacked(addressToBytes32(user), composeMsg));

        // Utility endpoint that is allowed to call lzCompose
        address endpoint = address(endpoints[usdtHomeEid]);

        // Fund the endpoint to forward the exact fee
        vm.deal(endpoint, fee.nativeFee);

        // Record the away chain balance the user already holds from the harness setup
        uint256 awayBefore = usdtAwayToken.balanceOf(user);

        // Exactly the declared fee clears the guard, which compares with a strict less than
        vm.prank(endpoint);
        oUsdaiUtility.lzCompose{value: fee.nativeFee}(address(usdaiHomeOAdapter), bytes32(0), message, address(0), "");

        // Deliver the packet to the away chain
        verifyPackets(usdtAwayEid, addressToBytes32(address(usdtAwayOAdapter)));

        // Assert the onward send went through
        assertEq(usdtAwayToken.balanceOf(user) - awayBefore, amount);
    }

    function test__OUSDaiUtilityWithdrawUsd_SendFails_RefundsToRefundToNotDestination() public {
        // Amount of USDai the utility holds for the withdrawal
        uint256 amount = 1_000e18;

        // Fund the utility with USDai to withdraw
        vm.prank(user);
        usdai.transfer(address(oUsdaiUtility), amount);

        // LZ receive option for the onward base token send
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Cross-chain send param addressed to the user
        SendParam memory sendParam = SendParam(usdtAwayEid, addressToBytes32(user), amount, 0, receiveOptions, "", "");

        // Refund recipient distinct from the destination
        address refundTo = address(0xF00D);

        // Withdraw payload declaring no onward fee, so the guard passes and the send itself is unfunded
        bytes memory composeMsg =
            abi.encode(IOUSDaiUtility.ActionType.Withdraw, abi.encode(sendParam, refundTo, uint256(0)));

        // Encode the composer message with the received USDai amount
        bytes memory message =
            OFTComposeMsgCodec.encode(1, usdaiHomeEid, amount, abi.encodePacked(addressToBytes32(user), composeMsg));

        // Record the destination base token balance
        uint256 userBefore = usdtHomeToken.balanceOf(user);

        // Execute the compose with no native value, so the onward send cannot pay its fee
        vm.prank(address(endpoints[usdtHomeEid]));
        oUsdaiUtility.lzCompose(address(usdaiHomeOAdapter), bytes32(0), message, address(0), "");

        // Assert the withdrawn base token went to the refund recipient
        assertEq(usdtHomeToken.balanceOf(refundTo), amount);

        // Assert the destination address received nothing
        assertEq(usdtHomeToken.balanceOf(user), userBefore);
    }

    function test__OUSDaiUtilityWithdrawUsd_LocalDestination_EmitsFullWidthRecipientTopic() public {
        // Amount of USDai the utility holds for the withdrawal
        uint256 amount = 1_000e18;

        // Fund the utility with USDai to withdraw
        vm.prank(user);
        usdai.transfer(address(oUsdaiUtility), amount);

        // Recipient with bytes set above the address, which no EVM address can hold
        bytes32 recipient = bytes32(uint256(1) << 200) | addressToBytes32(user);

        // Send param for a local destination
        SendParam memory sendParam = SendParam(0, recipient, 0, 0, "", "", "");

        // Withdraw payload
        bytes memory composeMsg =
            abi.encode(IOUSDaiUtility.ActionType.Withdraw, abi.encode(sendParam, user, uint256(0)));

        // Encode the composer message with the received USDai amount
        bytes memory message =
            OFTComposeMsgCodec.encode(1, usdaiHomeEid, amount, abi.encodePacked(addressToBytes32(user), composeMsg));

        // Record the recipient base token balance
        uint256 recipientBefore = usdtHomeToken.balanceOf(user);

        // Expect the recipient topic to carry all 32 bytes rather than the truncated address
        vm.expectEmit(true, true, true, false, address(oUsdaiUtility));
        emit IOUSDaiUtility.ComposerWithdraw(0, address(usdtHomeToken), recipient, 0, 0);

        // Execute the compose from the utility endpoint with the USDai adapter as source
        vm.prank(address(endpoints[usdtHomeEid]));
        oUsdaiUtility.lzCompose(address(usdaiHomeOAdapter), bytes32(0), message, address(0), "");

        // Assert the base token went to the truncated address the recipient topic contains
        assertEq(usdtHomeToken.balanceOf(user) - recipientBefore, amount);
    }
}
