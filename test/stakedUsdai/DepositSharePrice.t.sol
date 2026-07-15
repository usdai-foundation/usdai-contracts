// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {BaseTest} from "../Base.t.sol";

contract StakedUSDaiDepositSharePriceTest is BaseTest {
    uint256 internal initialBalance;

    function setUp() public override {
        super.setUp();

        // User approves USDai to spend their USD
        vm.startPrank(users.normalUser1);
        PYUSD.approve(address(usdai), 10_000_000 ether);

        // User deposits USD into USDai
        initialBalance = usdai.deposit(10_000_000 ether, users.normalUser1);

        vm.stopPrank();
    }

    function test__StakedUSDaiDeposit() public {
        // User approves StakedUSDai to spend their USDai
        vm.startPrank(users.normalUser1);
        usdai.approve(address(stakedUsdai), 1_000_000 ether);

        // Assert preview deposit matches convertToShares
        assertEq(stakedUsdai.previewDeposit(1_000_000 ether), stakedUsdai.convertToShares(1_000_000 ether));

        // User deposits USDai into StakedUSDai
        uint256 shares = stakedUsdai.deposit(1_000_000 ether, users.normalUser1);

        // Assert shares received matches
        assertEq(shares, 1_000_000 ether - LOCKED_SHARES, "Shares mismatch");

        // Assert user's StakedUSDai balance is shares less locked shares
        assertEq(
            stakedUsdai.balanceOf(users.normalUser1), 1_000_000 ether - LOCKED_SHARES, "StakedUSDai balance mismatch"
        );

        // Assert user's USDai balance decreased by amount
        assertEq(usdai.balanceOf(users.normalUser1), initialBalance - 1_000_000 ether, "USDai balance mismatch");

        // Assert total assets increased
        assertEq(stakedUsdai.totalAssets(), 1_000_000 ether, "Total assets mismatch");

        vm.stopPrank();

        // Simulate yield deposit
        simulateYieldDeposit(1_000_000 ether);

        // Assert total assets increased
        assertEq(stakedUsdai.totalAssets(), 2_000_000 ether, "Total assets mismatch");

        // Assert deposit share price increased
        assertEq(
            stakedUsdai.depositSharePrice(),
            (2_000_000 ether * FIXED_POINT_SCALE) / (shares + LOCKED_SHARES),
            "Deposit share price mismatch"
        );

        // Get redemption timestamp
        uint64 redemptionTimestamp = stakedUsdai.redemptionTimestamp();

        // User requests redemption of half of shares
        vm.prank(users.normalUser1);
        stakedUsdai.requestRedeem(shares / 2, users.normalUser1, users.normalUser1);

        // Assert total assets is unchanged
        assertEq(stakedUsdai.totalAssets(), 2_000_000 ether, "Total assets mismatch");

        // Assert deposit share price unchanged
        uint256 depositSharePrice = stakedUsdai.depositSharePrice();
        assertEq(
            depositSharePrice,
            (2_000_000 ether * FIXED_POINT_SCALE) / (shares + LOCKED_SHARES),
            "Deposit share price mismatch"
        );

        // Warp past redemption timestamp
        vm.warp(redemptionTimestamp + 1);

        // Service redemption
        uint256 amountProcessed = serviceRedemptionAndWarp(shares / 2, false);

        // Assert total assets is decreased
        uint256 remainingAssets = 2_000_000 ether - amountProcessed;
        assertEq(stakedUsdai.totalAssets(), remainingAssets, "Total assets mismatch");

        // Assert deposit share price unchanged
        assertEq(
            stakedUsdai.depositSharePrice(),
            depositSharePrice, // same as before servicing redemptions
            "Deposit share price mismatch"
        );
    }
}
