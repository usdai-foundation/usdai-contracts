// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {BaseTest} from "../Base.t.sol";
import {StakedUSDai} from "src/StakedUSDai.sol";
import {IStakedUSDai} from "src/interfaces/IStakedUSDai.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PositionManager} from "src/positionManagers/PositionManager.sol";

contract StakedUSDaiRequestRedeemTest is BaseTest {
    uint256 sharesBalance;

    function setUp() public override {
        super.setUp();

        // User approves USDai to spend their USD
        vm.startPrank(users.normalUser1);
        PYUSD.approve(address(usdai), 1_000_000 ether);

        // User deposits USD into USDai
        uint256 initialBalance = usdai.deposit(1_000_000 ether, users.normalUser1);

        // User deposits USDai into StakedUSDai
        usdai.approve(address(stakedUsdai), initialBalance);
        sharesBalance = stakedUsdai.deposit(initialBalance, users.normalUser1);

        vm.stopPrank();
    }

    function test__StakedUSDaiRequestRedeem_Multiple() public {
        // Get redemption timestamp
        uint64 redemptionTimestamp = stakedUsdai.redemptionTimestamp();

        // Request redeem
        vm.startPrank(users.normalUser1);
        uint256 redemptionId1 = stakedUsdai.requestRedeem(300_000 ether, users.normalUser1, users.normalUser1);
        uint256 redemptionId2 = stakedUsdai.requestRedeem(300_000 ether, users.normalUser1, users.normalUser1);
        uint256 redemptionId3 = stakedUsdai.requestRedeem(300_000 ether, users.normalUser1, users.normalUser1);

        // Assert redemption ID is correct
        assertEq(redemptionId1, 1);
        assertEq(redemptionId2, 2);
        assertEq(redemptionId3, 3);

        // Get redemption info
        (StakedUSDai.Redemption memory redemption1,) = stakedUsdai.redemption(redemptionId1);
        (StakedUSDai.Redemption memory redemption2,) = stakedUsdai.redemption(redemptionId2);
        (StakedUSDai.Redemption memory redemption3,) = stakedUsdai.redemption(redemptionId3);

        // Assert redemption info
        assertEq(redemption1.prev, 0);
        assertEq(redemption1.next, 2);
        assertEq(redemption1.pendingShares, 300_000 ether);
        assertEq(redemption1.redeemableShares, 0);
        assertEq(redemption1.withdrawableAmount, 0);
        assertEq(redemption1.controller, users.normalUser1);
        assertEq(redemption1.redemptionTimestamp, redemptionTimestamp);

        assertEq(redemption2.prev, 1);
        assertEq(redemption2.next, 3);
        assertEq(redemption2.pendingShares, 300_000 ether);
        assertEq(redemption2.redeemableShares, 0);
        assertEq(redemption2.withdrawableAmount, 0);
        assertEq(redemption2.controller, users.normalUser1);
        assertEq(redemption2.redemptionTimestamp, redemptionTimestamp);

        assertEq(redemption3.prev, 2);
        assertEq(redemption3.next, 0);
        assertEq(redemption3.pendingShares, 300_000 ether);
        assertEq(redemption3.redeemableShares, 0);
        assertEq(redemption3.withdrawableAmount, 0);
        assertEq(redemption3.controller, users.normalUser1);
        assertEq(redemption3.redemptionTimestamp, redemptionTimestamp);

        // Get redemption state info
        (uint256 index1, uint256 head1, uint256 tail1, uint256 pending1, uint256 balance1) =
            stakedUsdai.redemptionQueueInfo();

        // Assert redemption state info
        assertEq(index1, 3);
        assertEq(head1, 1);
        assertEq(tail1, 3);
        assertEq(pending1, 900_000 ether);
        assertEq(balance1, 0);

        // Assert user's StakedUSDai balance decreased
        assertEq(stakedUsdai.balanceOf(users.normalUser1), sharesBalance - 900_000 ether);

        vm.stopPrank();

        // Simulate yield deposit
        simulateYieldDeposit(100_000 ether);

        // Service redemption and warp
        serviceRedemptionAndWarp(300_000 ether, true);

        // Get next redemption timestamp
        redemptionTimestamp = stakedUsdai.redemptionTimestamp();

        vm.prank(users.normalUser1);
        uint256 redemptionId4 = stakedUsdai.requestRedeem(90_000 ether, users.normalUser1, users.normalUser1);

        // Assert redemption ID is correct
        assertEq(redemptionId4, 4);

        // Get redemption info
        (StakedUSDai.Redemption memory redemption4,) = stakedUsdai.redemption(redemptionId4);

        // Assert redemption info
        assertEq(redemption4.prev, 3);
        assertEq(redemption4.next, 0);
        assertEq(redemption4.pendingShares, 90_000 ether);
        assertEq(redemption4.redeemableShares, 0);
        assertEq(redemption4.withdrawableAmount, 0);
        assertEq(redemption4.controller, users.normalUser1);
        assertEq(redemption4.redemptionTimestamp, redemptionTimestamp);

        // Get redemption state info
        (uint256 index2, uint256 head2, uint256 tail2, uint256 pending2, uint256 balance2) =
            stakedUsdai.redemptionQueueInfo();

        // Assert redemption state info
        (StakedUSDai.Redemption memory redemption5,) = stakedUsdai.redemption(redemptionId1);
        assertEq(index2, 4);
        assertEq(head2, 2);
        assertEq(tail2, 4);
        assertEq(pending2, 690_000 ether);
        assertEq(balance2, redemption5.withdrawableAmount);
    }

    function testFuzz__StakedUSDaiRequestRedeem(
        uint256 shares
    ) public {
        vm.assume(shares > 1e18);
        vm.assume(shares <= sharesBalance);

        // Get redemption timestamp
        uint64 redemptionTimestamp = stakedUsdai.redemptionTimestamp();

        // Request redeem
        vm.startPrank(users.normalUser1);
        uint256 redemptionId = stakedUsdai.requestRedeem(shares, users.normalUser1, users.normalUser1);

        // Assert redemption ID is correct
        assertEq(redemptionId, 1);

        // Get redemption info
        (StakedUSDai.Redemption memory redemption,) = stakedUsdai.redemption(redemptionId);

        // Assert redemption info
        assertEq(redemption.prev, 0);
        assertEq(redemption.next, 0);
        assertEq(redemption.pendingShares, shares);
        assertEq(redemption.redeemableShares, 0);
        assertEq(redemption.withdrawableAmount, 0);
        assertEq(redemption.controller, users.normalUser1);
        assertEq(redemption.redemptionTimestamp, redemptionTimestamp);

        // Get redemption state info
        (uint256 index, uint256 head, uint256 tail, uint256 pending, uint256 balance) =
            stakedUsdai.redemptionQueueInfo();

        // Assert redemption state info
        assertEq(index, 1);
        assertEq(head, redemptionId);
        assertEq(tail, redemptionId);
        assertEq(pending, shares);
        assertEq(balance, 0);

        // Assert user's StakedUSDai balance decreased
        assertEq(stakedUsdai.balanceOf(users.normalUser1), sharesBalance - shares);

        vm.stopPrank();
    }

    function test__StakedUSDaiRequestRedeem_RevertWhen_ZeroShares() public {
        vm.startPrank(users.normalUser1);
        vm.expectRevert(IStakedUSDai.InvalidAmount.selector);
        stakedUsdai.requestRedeem(0, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiRequestRedeem_RevertWhen_ZeroController() public {
        vm.startPrank(users.normalUser1);
        vm.expectRevert(IStakedUSDai.InvalidAddress.selector);
        stakedUsdai.requestRedeem(1 ether, address(0), users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiRequestRedeem_RevertWhen_ZeroOwner() public {
        vm.startPrank(users.normalUser1);
        vm.expectRevert(IStakedUSDai.InvalidAddress.selector);
        stakedUsdai.requestRedeem(1 ether, users.normalUser1, address(0));
        vm.stopPrank();
    }

    function test__StakedUSDaiRequestRedeem_RevertWhen_InsufficientBalance() public {
        uint256 balance = stakedUsdai.balanceOf(users.normalUser1);
        vm.startPrank(users.normalUser1);
        vm.expectRevert(PositionManager.InsufficientBalance.selector);
        stakedUsdai.requestRedeem(balance + 1, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiRequestRedeem_RevertWhen_Blacklisted() public {
        vm.prank(users.deployer);
        usdai.setBlacklist(users.normalUser1, true);

        vm.startPrank(users.normalUser1);
        vm.expectRevert(abi.encodeWithSelector(IStakedUSDai.BlacklistedAddress.selector, users.normalUser1));
        stakedUsdai.requestRedeem(1 ether, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiRequestRedeem_RevertWhen_Paused() public {
        // Pause contract
        vm.prank(users.deployer);
        stakedUsdai.pause();

        vm.startPrank(users.normalUser1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        stakedUsdai.requestRedeem(1 ether, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiRequestRedeem_RevertWhen_TooManyActiveRedemptions() public {
        uint256 maxRedemptions = 50; // MAX_ACTIVE_REDEMPTIONS_COUNT from contract
        uint256 amount = 1 ether;

        // Create max number of redemptions
        for (uint256 i = 0; i < maxRedemptions; i++) {
            vm.startPrank(users.normalUser1);
            stakedUsdai.requestRedeem(amount, users.normalUser1, users.normalUser1);
        }

        // Try to create one more redemption
        vm.expectRevert(IStakedUSDai.InvalidRedemptionState.selector);
        vm.startPrank(users.normalUser1);
        stakedUsdai.requestRedeem(amount, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiRequestRedeem_WithOperator() public {
        // Set operator
        vm.startPrank(users.normalUser1);
        stakedUsdai.setOperator(users.normalUser2, true);
        vm.stopPrank();

        // Request redeem as operator
        vm.startPrank(users.normalUser2);
        uint256 redemptionId = stakedUsdai.requestRedeem(sharesBalance, users.normalUser1, users.normalUser1);

        // Verify redemption was created
        (StakedUSDai.Redemption memory redemption,) = stakedUsdai.redemption(redemptionId);
        assertEq(redemption.pendingShares, sharesBalance);
        assertEq(redemption.controller, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiRequestRedeem_RevertWhen_NotOwnerOrOperator() public {
        vm.startPrank(users.normalUser2);
        vm.expectRevert(IStakedUSDai.InvalidCaller.selector);
        stakedUsdai.requestRedeem(1 ether, users.normalUser1, users.normalUser1);
        vm.stopPrank();
    }
}
