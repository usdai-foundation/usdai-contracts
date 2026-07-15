// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {BaseTest} from "../Base.t.sol";
import {StakedUSDai} from "src/StakedUSDai.sol";
import {IStakedUSDai} from "src/interfaces/IStakedUSDai.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract StakedUSDaiWithdrawTest is BaseTest {
    uint256 internal withdrawableAmount;
    uint256 internal redemptionId;
    uint64 internal redemptionTimestamp;

    function setUp() public override {
        super.setUp();

        // User approves USDai to spend their USD
        vm.startPrank(users.normalUser1);
        PYUSD.approve(address(usdai), 1_000_000 ether);

        // User deposits USD into USDai
        uint256 initialBalance = usdai.deposit(1_000_000 ether, users.normalUser1);

        // User deposits USDai into StakedUSDai
        usdai.approve(address(stakedUsdai), initialBalance);
        uint256 requestedShares = stakedUsdai.deposit(initialBalance, users.normalUser1);

        // Get redemption timestamp
        uint64 redemptionTimestamp = stakedUsdai.redemptionTimestamp();

        // Request redeem
        redemptionId = stakedUsdai.requestRedeem(requestedShares, users.normalUser1, users.normalUser1);

        vm.stopPrank();

        // Service redemption as manager
        vm.startPrank(users.manager);
        PYUSD.approve(address(usdai), 1_000_000 ether);

        // User deposits USD into USDai
        uint256 serviceAmount = usdai.deposit(1_000_000 ether, address(stakedUsdai));

        // Warp past redemption timestamp
        vm.warp(redemptionTimestamp + 1);

        // Assert balance is correct
        require(usdai.balanceOf(address(stakedUsdai)) == initialBalance + serviceAmount);
        stakedUsdai.serviceRedemptions(requestedShares);
        vm.stopPrank();

        // Get withdrawable amount
        (StakedUSDai.Redemption memory redemption,) = stakedUsdai.redemption(1);
        withdrawableAmount = redemption.withdrawableAmount;

        // Warp past timelock
        vm.warp(redemptionTimestamp + 1);
    }

    function testFuzz__StakedUSDaiWithdraw(
        uint256 amount
    ) public {
        vm.assume(amount > 0);
        vm.assume(amount < withdrawableAmount);

        (uint256 initialIndex,, uint256 initialTail,, uint256 initialRedemptionBalance) =
            stakedUsdai.redemptionQueueInfo();

        // Withdraw
        vm.prank(users.normalUser1);
        stakedUsdai.withdraw(amount, users.normalUser1, users.normalUser1);

        // Get current redemption balance
        (
            uint256 currentIndex,
            uint256 currentHead,
            uint256 currentTail,
            uint256 currentPending,
            uint256 currentRedemptionBalance
        ) = stakedUsdai.redemptionQueueInfo();

        // Assert balances updated correctly
        assertEq(usdai.balanceOf(users.normalUser1), amount);
        assertEq(currentRedemptionBalance, initialRedemptionBalance - amount);
        assertEq(currentIndex, initialIndex);
        assertEq(currentHead, 0);
        assertEq(currentTail, initialTail);
        assertEq(currentPending, 0);

        // Assert redemption updated correctly
        (IStakedUSDai.Redemption memory redemption,) = stakedUsdai.redemption(redemptionId);
        assertEq(redemption.pendingShares, 0);
        assertEq(redemption.withdrawableAmount, withdrawableAmount - amount);
        assertGt(redemption.redeemableShares, 0);
    }

    function test__StakedUSDaiWithdraw_RevertWhen_ZeroAmount() public {
        vm.startPrank(users.normalUser1);
        vm.expectRevert(IStakedUSDai.InvalidAmount.selector);
        stakedUsdai.withdraw(0, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiWithdraw_RevertWhen_ZeroReceiver() public {
        vm.startPrank(users.normalUser1);
        vm.expectRevert(IStakedUSDai.InvalidAddress.selector);
        stakedUsdai.withdraw(1 ether, address(0), users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiWithdraw_RevertWhen_ZeroController() public {
        vm.startPrank(users.normalUser1);
        vm.expectRevert(IStakedUSDai.InvalidAddress.selector);
        stakedUsdai.withdraw(1 ether, users.normalUser1, address(0));
        vm.stopPrank();
    }

    function test__StakedUSDaiWithdraw_RevertWhen_InsufficientBalance() public {
        vm.startPrank(users.normalUser1);
        vm.expectRevert(IStakedUSDai.InvalidRedemptionState.selector);
        stakedUsdai.withdraw(withdrawableAmount + 1, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiWithdraw_RevertWhen_Blacklisted() public {
        vm.prank(users.deployer);
        usdai.setBlacklist(users.normalUser1, true);

        vm.startPrank(users.normalUser1);
        vm.expectRevert(abi.encodeWithSelector(IStakedUSDai.BlacklistedAddress.selector, users.normalUser1));
        stakedUsdai.withdraw(1 ether, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiWithdraw_RevertWhen_Paused() public {
        // Pause contract
        vm.prank(users.deployer);
        stakedUsdai.pause();

        vm.startPrank(users.normalUser1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        stakedUsdai.withdraw(1 ether, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiWithdraw_WithOperator() public {
        // Set operator
        vm.prank(users.normalUser1);
        stakedUsdai.setOperator(users.normalUser2, true);

        uint256 initialBalance = usdai.balanceOf(users.normalUser1);

        // Withdraw as operator
        vm.prank(users.normalUser2);
        stakedUsdai.withdraw(1 ether, users.normalUser1, users.normalUser1);

        // Verify withdrawal worked
        assertEq(usdai.balanceOf(users.normalUser1), initialBalance + 1 ether);
    }

    function test__StakedUSDaiWithdraw_RevertWhen_NotOwnerOrOperator() public {
        vm.startPrank(users.normalUser2);
        vm.expectRevert(IStakedUSDai.InvalidCaller.selector);
        stakedUsdai.withdraw(1 ether, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }
}
