// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {BaseTest} from "../Base.t.sol";
import {IUSDai} from "src/interfaces/IUSDai.sol";

contract USDaiDepositTest is BaseTest {
    /*------------------------------------------------------------------------*/
    /* Retroactive Yield Inflation Fix Tests */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Sets up rate tiers and initializes base yield accrual timestamp
     */
    function _setupBaseYield() internal {
        /* Set rate tiers */
        vm.prank(users.admin);
        IUSDai.RateTier[] memory rateTiers = new IUSDai.RateTier[](2);
        rateTiers[0] = IUSDai.RateTier({rate: BASE_YIELD_RATE_1, threshold: BASE_YIELD_CUTOFF_1});
        rateTiers[1] = IUSDai.RateTier({rate: BASE_YIELD_RATE_2, threshold: BASE_YIELD_CUTOFF_2});
        baseYieldEscrow.setRateTiers(rateTiers);

        /* Initialize base yield accrual timestamp via storage slot */
        vm.store(
            address(usdai),
            bytes32(uint256(0xad76c5b481cb106971e0ae4c23a09cb5b1dc9dba5fad96d9694630df5e853900) + 2),
            bytes32(uint256(block.timestamp))
        );
    }

    function test__RetroactiveYieldInflation_FixVerification() public {
        _setupBaseYield();

        /* Test constants */
        uint256 initialDeposit = 1_000_000 * 1e6; // 1M PYUSD (protocol TVL)
        uint256 flashLoanAmount = 100_000_000 * 1e6; // 100M PYUSD flash loan
        uint256 timeElapsed = 24 hours;

        /* Setup: Initial deposit to establish protocol TVL */
        vm.startPrank(users.admin);
        PYUSD.approve(address(usdai), initialDeposit);
        usdai.deposit(initialDeposit, users.admin);
        vm.stopPrank();

        /* Warp time forward to simulate staleness */
        vm.warp(block.timestamp + timeElapsed);

        /* Record total accrued yield BEFORE attacker deposit (this is a view - includes pending) */
        uint256 totalAccruedBefore = usdai.baseYieldAccrued();

        /* Simulate flash loan by giving attacker tokens */
        deal(address(PYUSD), users.normalUser1, flashLoanAmount);

        /* Attacker deposits flash loan */
        vm.startPrank(users.normalUser1);
        PYUSD.approve(address(usdai), flashLoanAmount);
        uint256 usdaiMinted = usdai.deposit(flashLoanAmount, users.normalUser1);
        vm.stopPrank();

        /* After deposit, _accrue() was called and stored the yield.
         * totalAccruedBefore already included the pending yield (view function).
         * With the fix, yield was calculated on OLD balance before token transfer. */
        uint256 totalAccruedAfter = usdai.baseYieldAccrued();

        /* After attacker deposit, accrued should be same (no new time elapsed) */
        assertEq(totalAccruedAfter, totalAccruedBefore, "No additional yield should accrue from flash loan deposit");
    }

    /*------------------------------------------------------------------------*/
    /* Standard Deposit Tests */
    /*------------------------------------------------------------------------*/

    function testFuzz__USDaiDeposit(
        uint256 amount
    ) public {
        vm.assume(amount > 0);
        vm.assume(amount <= 10_000_000 ether);

        uint256 usdBalance = PYUSD.balanceOf(users.normalUser1);

        // User approves USDai to spend their USD
        vm.startPrank(users.normalUser1);
        PYUSD.approve(address(usdai), amount);

        // User deposits 1000 USD into USDai
        uint256 usdaiAmount = usdai.deposit(amount, users.normalUser1);

        // Assert user's USDai balance increased by usdaiAmount
        assertEq(usdai.balanceOf(users.normalUser1), usdaiAmount);

        // Assert user's USD balance decreased by amount
        assertEq(PYUSD.balanceOf(users.normalUser1), usdBalance - amount);

        vm.stopPrank();
    }

    function test__USDaiDepositBlacklistedAddress() public {
        vm.startPrank(users.deployer);
        usdai.setBlacklist(users.normalUser1, true);
        vm.stopPrank();

        vm.startPrank(users.normalUser1);
        vm.expectRevert(abi.encodeWithSelector(IUSDai.BlacklistedAddress.selector, users.normalUser1));
        usdai.deposit(100 ether, users.normalUser1);
        vm.stopPrank();
    }
}
