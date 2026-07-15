// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {BaseTest} from "../Base.t.sol";
import {IStakedUSDai} from "src/interfaces/IStakedUSDai.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract StakedUSDaiDepositTest is BaseTest {
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
    }

    function testFuzz__StakedUSDaiDeposit(
        uint256 amount
    ) public {
        vm.assume(amount > 1e6);
        vm.assume(amount <= initialBalance);

        uint256 initialAssets = stakedUsdai.totalAssets();

        // User approves StakedUSDai to spend their USDai
        vm.startPrank(users.normalUser1);
        usdai.approve(address(stakedUsdai), amount);

        // Calculate expected shares
        uint256 expectedShares = stakedUsdai.convertToShares(amount);
        uint256 previewDeposit = stakedUsdai.previewDeposit(amount);

        // Assert preview deposit matches expected shares
        assertEq(previewDeposit, expectedShares);

        // User deposits USDai into StakedUSDai
        uint256 shares = stakedUsdai.deposit(amount, users.normalUser1);

        // Assert shares received matches expected
        assertEq(shares, expectedShares);

        // Assert user's StakedUSDai balance is shares
        assertEq(stakedUsdai.balanceOf(users.normalUser1), shares);

        // Assert user's USDai balance decreased by amount
        assertEq(usdai.balanceOf(users.normalUser1), initialBalance - amount);

        // Assert total assets increased
        assertEq(stakedUsdai.totalAssets(), initialAssets + amount);

        vm.stopPrank();
    }

    function testFuzz__StakedUSDaiDeposit_SharePriceConsistencyMultipleDeposits(
        uint256[5] memory depositAmounts
    ) public {
        // First make a proper initial deposit to get past LOCKED_SHARES
        vm.startPrank(users.normalUser1);
        PYUSD.approve(address(usdai), 1_000_000 ether);
        uint256 initialUsdaiBalance = usdai.deposit(1_000_000 ether, users.normalUser1);
        usdai.approve(address(stakedUsdai), initialUsdaiBalance);
        stakedUsdai.deposit(initialUsdaiBalance, users.normalUser1);
        vm.stopPrank();

        // Track share prices for each deposit
        uint256[] memory sharePrices = new uint256[](depositAmounts.length);

        // Make multiple deposits with different amounts
        for (uint256 i = 0; i < depositAmounts.length; i++) {
            // Bound deposit amount to reasonable range
            depositAmounts[i] = bound(depositAmounts[i], 1 ether, 1_000_000 ether);

            vm.startPrank(users.normalUser2);
            PYUSD.approve(address(usdai), depositAmounts[i]);
            uint256 usdaiBalance = usdai.deposit(depositAmounts[i], users.normalUser2);

            usdai.approve(address(stakedUsdai), usdaiBalance);
            uint256 shares = stakedUsdai.deposit(usdaiBalance, users.normalUser2);
            vm.stopPrank();

            // Calculate and store share price
            sharePrices[i] = (usdaiBalance * 1e18) / shares;

            // If not first deposit, verify share price is consistent
            if (i > 1) {
                uint256 priceDiff = sharePrices[i] > sharePrices[i - 1]
                    ? sharePrices[i] - sharePrices[i - 1]
                    : sharePrices[i - 1] - sharePrices[i];
                assertLt(priceDiff, 1, "Share prices should remain consistent");
            }
        }
    }

    function test__StakedUSDaiDeposit_SameAsMint() public view {
        uint256 shares = stakedUsdai.convertToShares(1_000_000 ether);
        uint256 assets = stakedUsdai.convertToAssets(shares);
        assertEq(assets, 1_000_000 ether);
    }

    function test__StakedUSDaiDeposit_RevertWhen_ZeroAmount() public {
        vm.startPrank(users.normalUser1);
        vm.expectRevert(IStakedUSDai.InvalidAmount.selector);
        stakedUsdai.deposit(0, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiDeposit_RevertWhen_ZeroAddress() public {
        vm.startPrank(users.normalUser1);
        vm.expectRevert(IStakedUSDai.InvalidAddress.selector);
        stakedUsdai.deposit(1 ether, address(0));
        vm.stopPrank();
    }

    function test__StakedUSDaiDeposit_RevertWhen_Blacklisted() public {
        vm.prank(users.deployer);
        usdai.setBlacklist(users.normalUser1, true);

        vm.startPrank(users.normalUser1);
        vm.expectRevert(abi.encodeWithSelector(IStakedUSDai.BlacklistedAddress.selector, users.normalUser1));
        stakedUsdai.deposit(1 ether, users.normalUser1);
        vm.stopPrank();
    }

    function test__StakedUSDaiDeposit_RevertWhen_Paused() public {
        // Pause contract
        vm.prank(users.deployer);
        stakedUsdai.pause();

        vm.startPrank(users.normalUser1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        stakedUsdai.deposit(1 ether, users.normalUser1);
        vm.stopPrank();
    }
}
