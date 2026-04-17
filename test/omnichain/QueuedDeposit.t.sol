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

import {IUSDaiQueuedDepositor} from "src/interfaces/IUSDaiQueuedDepositor.sol";
import {IOUSDaiUtility} from "src/interfaces/IOUSDaiUtility.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract USDaiQueuedDepositTest is OmnichainBaseTest {
    using OptionsBuilder for bytes;

    function setUp() public override {
        super.setUp();

        vm.prank(address(usdtHomeOAdapter));
        usdtHomeToken.mint(user, 20_000_000 ether);
    }

    function testFuzz__USDaiQueuedLocalDeposit(
        uint256 amount
    ) public {
        vm.assume(amount >= 1_000_000 ether);
        vm.assume(amount <= 10_000_000 ether);

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken.approve(address(oUsdaiUtility), amount * 2);

        // Data for queued deposit on home chain
        bytes memory data1 = abi.encode(IUSDaiQueuedDepositor.QueueType.Deposit, user, 0);

        // Deposit the USD
        oUsdaiUtility.localCompose(IOUSDaiUtility.ActionType.QueuedDeposit, address(usdtHomeToken), amount, data1);

        IUSDaiQueuedDepositor.QueueItem memory queueItem1 =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 0);
        assertEq(queueItem1.pendingDeposit, amount);
        assertEq(queueItem1.dstEid, 0);
        assertEq(queueItem1.depositor, address(oUsdaiUtility));
        assertEq(queueItem1.recipient, user);

        (uint256 head1, uint256 pending1, IUSDaiQueuedDepositor.QueueItem[] memory queueItems1) =
            usdaiQueuedDepositor.queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 0, 100);
        assertEq(head1, 0);
        assertEq(pending1, amount);
        assertEq(queueItems1.length, 1);

        (uint256 depositCap1, uint256 counter1) = usdaiQueuedDepositor.depositCapInfo();
        assertEq(depositCap1, type(uint256).max);
        assertEq(counter1, amount);

        // Data for queued deposit on home chain
        bytes memory data2 = abi.encode(IUSDaiQueuedDepositor.QueueType.Deposit, user, 0);

        // Deposit the USD
        oUsdaiUtility.localCompose(IOUSDaiUtility.ActionType.QueuedDeposit, address(usdtHomeToken), amount, data2);

        IUSDaiQueuedDepositor.QueueItem memory queueItem2 =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 1);
        assertEq(queueItem2.pendingDeposit, amount);
        assertEq(queueItem2.dstEid, 0);
        assertEq(queueItem2.depositor, address(oUsdaiUtility));
        assertEq(queueItem2.recipient, user);

        (uint256 head2, uint256 pending2, IUSDaiQueuedDepositor.QueueItem[] memory queueItems2) =
            usdaiQueuedDepositor.queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 0, 100);
        assertEq(head2, 0);
        assertEq(pending2, amount * 2);
        assertEq(queueItems2.length, 2);

        (uint256 depositCap, uint256 counter) = usdaiQueuedDepositor.depositCapInfo();
        assertEq(depositCap, type(uint256).max);
        assertEq(counter, amount * 2);

        // Verify that the queued USDai was minted to the user
        assertEq(IERC20(queuedUsdaiToken).balanceOf(user), amount * 2);

        vm.stopPrank();
    }

    function testFuzz__USDaiQueuedLocalDeposit_6Decimals(
        uint256 amount
    ) public {
        vm.assume(amount >= 1_000_000 * 1e6);
        vm.assume(amount <= 10_000_000 * 1e6);

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken6Decimals.approve(address(oUsdaiUtility), amount * 2);

        // Data for queued deposit on home chain
        bytes memory data1 = abi.encode(IUSDaiQueuedDepositor.QueueType.Deposit, user, 0);

        // Deposit the USD
        oUsdaiUtility.localCompose(
            IOUSDaiUtility.ActionType.QueuedDeposit, address(usdtHomeToken6Decimals), amount, data1
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem1 =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), 0);
        assertEq(queueItem1.pendingDeposit, amount);
        assertEq(queueItem1.dstEid, 0);
        assertEq(queueItem1.depositor, address(oUsdaiUtility));
        assertEq(queueItem1.recipient, user);

        (uint256 head1, uint256 pending1, IUSDaiQueuedDepositor.QueueItem[] memory queueItems1) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), 0, 100);
        assertEq(head1, 0);
        assertEq(pending1, amount);
        assertEq(queueItems1.length, 1);

        // Data for queued deposit on home chain
        bytes memory data2 = abi.encode(IUSDaiQueuedDepositor.QueueType.Deposit, user, 0);

        // Deposit the USD
        oUsdaiUtility.localCompose(
            IOUSDaiUtility.ActionType.QueuedDeposit, address(usdtHomeToken6Decimals), amount, data2
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem2 =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), 1);
        assertEq(queueItem2.pendingDeposit, amount);
        assertEq(queueItem2.dstEid, 0);
        assertEq(queueItem2.depositor, address(oUsdaiUtility));
        assertEq(queueItem2.recipient, user);

        (uint256 head2, uint256 pending2, IUSDaiQueuedDepositor.QueueItem[] memory queueItems2) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken6Decimals), 0, 100);
        assertEq(head2, 0);
        assertEq(pending2, amount * 2);
        assertEq(queueItems2.length, 2);

        // Verify that the queued USDai was minted to the user
        assertEq(IERC20(queuedUsdaiToken).balanceOf(user), amount * 2 * 1e12);

        vm.stopPrank();
    }

    function testFuzz__USDaiQueuedLocalDepositAndStake(
        uint256 amount
    ) public {
        vm.assume(amount >= 1_000_000 ether);
        vm.assume(amount <= 10_000_000 ether);

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken.approve(address(oUsdaiUtility), amount * 2);

        // Data for queued deposit on home chain
        bytes memory data1 = abi.encode(IUSDaiQueuedDepositor.QueueType.DepositAndStake, user, 0);

        // Deposit the USD
        oUsdaiUtility.localCompose(IOUSDaiUtility.ActionType.QueuedDeposit, address(usdtHomeToken), amount, data1);

        IUSDaiQueuedDepositor.QueueItem memory queueItem1 =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), 0);
        assertEq(queueItem1.pendingDeposit, amount);
        assertEq(queueItem1.dstEid, 0);
        assertEq(queueItem1.depositor, address(oUsdaiUtility));
        assertEq(queueItem1.recipient, user);

        (uint256 head1, uint256 pending1, IUSDaiQueuedDepositor.QueueItem[] memory queueItems1) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), 0, 100);
        assertEq(head1, 0);
        assertEq(pending1, amount);
        assertEq(queueItems1.length, 1);

        // Data for queued deposit on home chain
        bytes memory data2 = abi.encode(IUSDaiQueuedDepositor.QueueType.DepositAndStake, user, 0);

        // Deposit the USD
        oUsdaiUtility.localCompose(IOUSDaiUtility.ActionType.QueuedDeposit, address(usdtHomeToken), amount, data2);

        IUSDaiQueuedDepositor.QueueItem memory queueItem2 =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), 1);
        assertEq(queueItem2.pendingDeposit, amount);
        assertEq(queueItem2.dstEid, 0);
        assertEq(queueItem2.depositor, address(oUsdaiUtility));
        assertEq(queueItem2.recipient, user);

        (uint256 head2, uint256 pending2, IUSDaiQueuedDepositor.QueueItem[] memory queueItems2) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken), 0, 100);
        assertEq(head2, 0);
        assertEq(pending2, amount * 2);
        assertEq(queueItems2.length, 2);

        // Verify that the queued USDai was minted to the user
        assertEq(IERC20(queuedStakedUsdaiToken).balanceOf(user), amount * 2);

        vm.stopPrank();
    }

    function testFuzz__USDaiQueuedLocalDepositAndStake_6Decimals(
        uint256 amount
    ) public {
        vm.assume(amount >= 1_000_000 * 1e6);
        vm.assume(amount <= 10_000_000 * 1e6);

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken6Decimals.approve(address(oUsdaiUtility), amount * 2);

        // Data for queued deposit on home chain
        bytes memory data1 = abi.encode(IUSDaiQueuedDepositor.QueueType.DepositAndStake, user, 0);

        // Deposit the USD
        oUsdaiUtility.localCompose(
            IOUSDaiUtility.ActionType.QueuedDeposit, address(usdtHomeToken6Decimals), amount, data1
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem1 = usdaiQueuedDepositor.queueItem(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken6Decimals), 0
        );
        assertEq(queueItem1.pendingDeposit, amount);
        assertEq(queueItem1.dstEid, 0);
        assertEq(queueItem1.depositor, address(oUsdaiUtility));
        assertEq(queueItem1.recipient, user);

        (uint256 head1, uint256 pending1, IUSDaiQueuedDepositor.QueueItem[] memory queueItems1) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken6Decimals), 0, 100);
        assertEq(head1, 0);
        assertEq(pending1, amount);
        assertEq(queueItems1.length, 1);

        // Data for queued deposit on home chain
        bytes memory data2 = abi.encode(IUSDaiQueuedDepositor.QueueType.DepositAndStake, user, 0);

        // Deposit the USD
        oUsdaiUtility.localCompose(
            IOUSDaiUtility.ActionType.QueuedDeposit, address(usdtHomeToken6Decimals), amount, data2
        );

        IUSDaiQueuedDepositor.QueueItem memory queueItem2 = usdaiQueuedDepositor.queueItem(
            IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken6Decimals), 1
        );
        assertEq(queueItem2.pendingDeposit, amount);
        assertEq(queueItem2.dstEid, 0);
        assertEq(queueItem2.depositor, address(oUsdaiUtility));
        assertEq(queueItem2.recipient, user);

        (uint256 head2, uint256 pending2, IUSDaiQueuedDepositor.QueueItem[] memory queueItems2) = usdaiQueuedDepositor
            .queueInfo(IUSDaiQueuedDepositor.QueueType.DepositAndStake, address(usdtHomeToken6Decimals), 0, 100);
        assertEq(head2, 0);
        assertEq(pending2, amount * 2);
        assertEq(queueItems2.length, 2);

        // Verify that the queued USDai was minted to the user
        assertEq(IERC20(queuedStakedUsdaiToken).balanceOf(user), amount * 2 * 1e12);

        vm.stopPrank();
    }

    function testFuzz__USDaiQueuedOmnichainDeposit(
        uint256 amount
    ) public {
        vm.assume(amount >= 1_000_000 ether);
        vm.assume(amount <= 10_000_000 ether);

        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        // Compose message for deposit on home chain
        bytes memory suffix = abi.encode(IUSDaiQueuedDepositor.QueueType.Deposit, user, usdtAwayEid);
        bytes memory composeMsg = abi.encode(IOUSDaiUtility.ActionType.QueuedDeposit, suffix);

        // LZ composer option
        bytes memory composerOptions = receiveOptions.addExecutorLzComposeOption(0, 1_050_000, uint128(0));

        // Send param for USD away to USD home
        SendParam memory usdtSendParam = SendParam({
            dstEid: usdtHomeEid,
            to: addressToBytes32(address(oUsdaiUtility)),
            amountLD: amount,
            /// forge-lint: disable-next-line
            minAmountLD: (amount / 10 ** 12) * 10 ** 12,
            extraOptions: composerOptions,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        // Quote the fee for sending USD from away to home
        (,, OFTReceipt memory receipt) = usdtAwayOAdapter.quoteOFT(usdtSendParam);
        usdtSendParam.minAmountLD = receipt.amountReceivedLD;

        // Compose message for USD away to USD home
        MessagingFee memory fee = usdtAwayOAdapter.quoteSend(usdtSendParam, false);

        vm.startPrank(user);

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

        IUSDaiQueuedDepositor.QueueItem memory queueItem =
            usdaiQueuedDepositor.queueItem(IUSDaiQueuedDepositor.QueueType.Deposit, address(usdtHomeToken), 0);
        assertEq(queueItem.pendingDeposit, usdtSendParam.minAmountLD);
        assertEq(queueItem.dstEid, usdtAwayEid);
        assertEq(queueItem.depositor, address(oUsdaiUtility));
        assertEq(queueItem.recipient, user);

        // Verify that the queued USDai was minted to the user
        assertEq(IERC20(queuedUsdaiToken).balanceOf(user), usdtSendParam.minAmountLD);

        vm.stopPrank();
    }

    function test__USDaiQueuedDeposit_RevertWhen_InvalidAmount() public {
        // Local
        vm.startPrank(user);
        usdtHomeToken.approve(address(oUsdaiUtility), 100);

        // Data for queued deposit on home chain
        bytes memory data = abi.encode(IUSDaiQueuedDepositor.QueueType.Deposit, user, 0);

        // Deposit the USD
        vm.expectRevert(IOUSDaiUtility.QueuedDepositFailed.selector);
        oUsdaiUtility.localCompose(IOUSDaiUtility.ActionType.QueuedDeposit, address(usdtHomeToken), 100, data);

        vm.stopPrank();
    }

    function test__USDaiQueuedDeposit_RevertWhen_InvalidDepositToken() public {
        // Remove the whitelisted token
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdtHomeToken);
        usdaiQueuedDepositor.removeWhitelistedTokens(tokens);

        vm.startPrank(user);

        usdtHomeToken.approve(address(oUsdaiUtility), 100);

        // Data for queued deposit on home chain
        bytes memory data = abi.encode(IUSDaiQueuedDepositor.QueueType.Deposit, user, 0);

        // Data for queued deposit on home chain
        vm.expectRevert(IOUSDaiUtility.QueuedDepositFailed.selector);
        oUsdaiUtility.localCompose(IOUSDaiUtility.ActionType.QueuedDeposit, address(usdtHomeToken), 100, data);
        vm.stopPrank();
    }

    function test__USDaiQueuedDeposit_RevertWhen_TransferringReceiptToken() public {
        uint256 amount = 1_000_000 ether;

        // User approves USDai to spend their USD
        vm.startPrank(user);
        usdtHomeToken.approve(address(oUsdaiUtility), amount);

        // Data for queued deposit on home chain
        bytes memory data = abi.encode(IUSDaiQueuedDepositor.QueueType.Deposit, user, 0);
        oUsdaiUtility.localCompose(IOUSDaiUtility.ActionType.QueuedDeposit, address(usdtHomeToken), amount, data);

        vm.expectRevert();
        /// forge-lint: disable-next-line
        IERC20(queuedUsdaiToken).transfer(address(usdaiQueuedDepositor), amount);

        vm.stopPrank();
    }

    function test__USDaiQueuedDeposit_RevertWhen_DepositCapExceeded() public {
        usdaiQueuedDepositor.updateDepositCap(10_000_000 * 1e18, false);

        (uint256 cap, uint256 counter) = usdaiQueuedDepositor.depositCapInfo();

        assertEq(cap, 10_000_000 * 1e18);
        assertEq(counter, 0);

        vm.startPrank(user);
        usdtHomeToken.approve(address(oUsdaiUtility), cap + 1);

        // Data for queued deposit on home chain
        bytes memory data = abi.encode(IUSDaiQueuedDepositor.QueueType.Deposit, user, 0);

        // Deposit the USD
        vm.expectRevert(IOUSDaiUtility.QueuedDepositFailed.selector);
        oUsdaiUtility.localCompose(IOUSDaiUtility.ActionType.QueuedDeposit, address(usdtHomeToken), cap + 1, data);
        vm.stopPrank();

        usdaiQueuedDepositor.updateDepositCap(cap + 1, false);

        vm.startPrank(user);
        oUsdaiUtility.localCompose(IOUSDaiUtility.ActionType.QueuedDeposit, address(usdtHomeToken), cap + 1, data);
        vm.stopPrank();

        (, counter) = usdaiQueuedDepositor.depositCapInfo();
        assertEq(counter, cap + 1);
    }
}
