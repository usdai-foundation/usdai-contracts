// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {BaseTest} from "../Base.t.sol";
import {IStakedUSDai} from "src/interfaces/IStakedUSDai.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract StakedUSDaiRedeemTest is BaseTest {
    uint256 internal requestedShares;
    uint256 internal initialBalance;
    address internal constant RANDOM_ADDRESS = address(0xdead);
    uint256 internal checkpoint;
    uint256 internal redemptionId;
    uint64 internal redemptionTimestamp;

    function setUp() public override {
        super.setUp();

        // User approves USDai to spend their USD
        vm.startPrank(users.normalUser1);
        PYUSD.approve(address(usdai), 1_000_000 ether);

        // User deposits USD into USDai
        initialBalance = usdai.deposit(1_000_000 ether, users.normalUser1);

        // User deposits USDai into StakedUSDai
        usdai.approve(address(stakedUsdai), initialBalance);
        requestedShares = stakedUsdai.deposit(initialBalance, users.normalUser1);

        // Get redemption timestamp
        redemptionTimestamp = stakedUsdai.redemptionTimestamp();

        // Request redeem
        redemptionId = stakedUsdai.requestRedeem(requestedShares, users.normalUser1, users.normalUser1);

        vm.stopPrank();

        checkpoint = block.timestamp;
    }

    function testFuzz__StakedUSDaiRedeem(
        uint256 shares
    ) public {
        vm.assume(shares > 0);
        vm.assume(shares < requestedShares);

        // Simulate yield deposit
        simulateYieldDeposit(1_000_000 ether);

        // Service redemption as manager
        serviceRedemptionAndWarp(requestedShares, true);

        (uint256 initialIndex,, uint256 initialTail,, uint256 initialRedemptionBalance) =
            stakedUsdai.redemptionQueueInfo();

        // Redeem
        vm.prank(users.normalUser1);
        uint256 assets = stakedUsdai.redeem(shares, users.normalUser1, users.normalUser1);

        // Get current redemption balance
        (
            uint256 currentIndex,
            uint256 currentHead,
            uint256 currentTail,
            uint256 currentPending,
            uint256 currentRedemptionBalance
        ) = stakedUsdai.redemptionQueueInfo();

        // Assert balances updated correctly
        assertEq(usdai.balanceOf(users.normalUser1), assets);
        assertEq(currentRedemptionBalance, initialRedemptionBalance - assets);
        assertEq(currentIndex, initialIndex);
        assertEq(currentHead, 0);
        assertEq(currentTail, initialTail);
        assertEq(currentPending, 0);

        // Assert redemption updated correctly
        (IStakedUSDai.Redemption memory redemption,) = stakedUsdai.redemption(redemptionId);
        assertEq(redemption.pendingShares, 0);
        assertGt(redemption.withdrawableAmount, 0);
        assertEq(redemption.redeemableShares, requestedShares - shares);
    }

    function test__ServiceRedemptions_When_RedemptionAmountIsZero() public {
        // Simulate extreme asset reduction
        bytes32 depositsStorageLocation = 0x2c5de62bb029e52f8f5651820547ac44294b098c752111b71e5fee4f80a66900;
        uint256 currentBalance = uint256(vm.load(address(stakedUsdai), depositsStorageLocation));
        vm.store(address(stakedUsdai), depositsStorageLocation, bytes32(currentBalance - (initialBalance - 1)));

        // Warp past redemption timestamp
        vm.warp(redemptionTimestamp + 1);

        // Try to service redemption
        vm.startPrank(users.manager);
        stakedUsdai.serviceRedemptions(requestedShares);
        vm.stopPrank();

        vm.warp(redemptionTimestamp + 1);

        // Try to redeem requested shares
        vm.startPrank(users.normalUser1);
        stakedUsdai.redeem(requestedShares, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiRedeem_RevertWhen_ZeroShares() public {
        // Simulate yield deposit
        simulateYieldDeposit(1_000_000 ether);

        // Service redemption as manager
        serviceRedemptionAndWarp(requestedShares, true);

        vm.startPrank(users.normalUser1);
        vm.expectRevert(IStakedUSDai.InvalidAmount.selector);
        stakedUsdai.redeem(0, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiRedeem_RevertWhen_ZeroReceiver() public {
        // Simulate yield deposit
        simulateYieldDeposit(1_000_000 ether);

        // Service redemption as manager
        serviceRedemptionAndWarp(requestedShares, true);

        vm.startPrank(users.normalUser1);
        vm.expectRevert(IStakedUSDai.InvalidAddress.selector);
        stakedUsdai.redeem(1 ether, address(0), users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiRedeem_RevertWhen_ZeroController() public {
        // Simulate yield deposit
        simulateYieldDeposit(1_000_000 ether);

        uint256 redemptionSharePrice3 = stakedUsdai.redemptionSharePrice();

        (uint256 index, uint256 head, uint256 tail, uint256 pending, uint256 balance) =
            stakedUsdai.redemptionQueueInfo();

        // Service redemption as manager
        serviceRedemptionAndWarp(requestedShares, true);

        vm.startPrank(users.normalUser1);
        vm.expectRevert(IStakedUSDai.InvalidAddress.selector);
        stakedUsdai.redeem(1 ether, users.normalUser1, address(0));
        vm.stopPrank();
    }

    function test__StakedUSDaiRedeem_RevertWhen_InsufficientShares() public {
        // Simulate yield deposit
        simulateYieldDeposit(1_000_000 ether);

        // Service redemption as manager
        serviceRedemptionAndWarp(requestedShares, true);

        vm.startPrank(users.normalUser1);
        vm.expectRevert(IStakedUSDai.InvalidRedemptionState.selector);
        stakedUsdai.redeem(requestedShares + 1, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiRedeem_RevertWhen_Blacklisted() public {
        // Simulate yield deposit
        simulateYieldDeposit(1_000_000 ether);

        // Service redemption as manager
        serviceRedemptionAndWarp(requestedShares, true);

        vm.prank(users.deployer);
        usdai.setBlacklist(users.normalUser1, true);

        vm.startPrank(users.normalUser1);
        vm.expectRevert(abi.encodeWithSelector(IStakedUSDai.BlacklistedAddress.selector, users.normalUser1));
        stakedUsdai.redeem(1 ether, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiRedeem_RevertWhen_Paused() public {
        // Simulate yield deposit
        simulateYieldDeposit(1_000_000 ether);

        // Service redemption as manager
        serviceRedemptionAndWarp(requestedShares, true);

        // Pause contract
        vm.prank(users.deployer);
        stakedUsdai.pause();

        vm.startPrank(users.normalUser1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        stakedUsdai.redeem(1 ether, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiRedeem_WithOperator() public {
        // Simulate yield deposit
        simulateYieldDeposit(1_000_000 ether);

        // Service redemption as manager
        serviceRedemptionAndWarp(requestedShares, true);

        // Set operator
        vm.prank(users.normalUser1);
        stakedUsdai.setOperator(users.normalUser2, true);

        // Redeem as operator
        vm.prank(users.normalUser2);
        uint256 assets = stakedUsdai.redeem(requestedShares, users.normalUser1, users.normalUser1);

        // Verify redemption worked
        assertEq(usdai.balanceOf(users.normalUser1), assets);
    }

    function test__StakedUSDaiRedeem_RevertWhen_NotOwnerOrOperator() public {
        // Simulate yield deposit
        simulateYieldDeposit(1_000_000 ether);

        // Service redemption as manager
        serviceRedemptionAndWarp(requestedShares, true);

        vm.startPrank(users.normalUser2);
        vm.expectRevert(IStakedUSDai.InvalidCaller.selector);
        stakedUsdai.redeem(1 ether, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiRedeem_RevertWhen_BeforeRedemptionTimestamp() public {
        // Simulate yield deposit
        simulateYieldDeposit(1_000_000 ether);

        // Try to redeem before redemption timestamp
        vm.startPrank(users.normalUser1);
        vm.expectRevert(IStakedUSDai.InvalidRedemptionState.selector);
        stakedUsdai.redeem(1 ether, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }
}
