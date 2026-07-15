// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {BaseTest} from "../Base.t.sol";
import {IUSDai} from "../../src/interfaces/IUSDai.sol";

contract USDaiBaseYieldTest is BaseTest {
    uint256 internal usdaiAmount;

    function setUp() public override {
        super.setUp();

        vm.prank(users.admin);

        /* Set rate tiers */
        IUSDai.RateTier[] memory rateTiers = new IUSDai.RateTier[](2);
        rateTiers[0] = IUSDai.RateTier({rate: BASE_YIELD_RATE_1, threshold: BASE_YIELD_CUTOFF_1});
        rateTiers[1] = IUSDai.RateTier({rate: BASE_YIELD_RATE_2, threshold: BASE_YIELD_CUTOFF_2});
        baseYieldEscrow.setRateTiers(rateTiers);

        /* Set base yield accrual timestamp via storage slot */
        vm.store(
            address(usdai),
            bytes32(uint256(0xad76c5b481cb106971e0ae4c23a09cb5b1dc9dba5fad96d9694630df5e853900) + 2),
            bytes32(uint256(block.timestamp))
        );

        // User approves USDai to spend their USD
        vm.startPrank(users.normalUser1);
        PYUSD.approve(address(usdai), 957_033_503 * 1e6);

        // User deposits amount of USD into USDai (~957,027,799 USD)
        usdaiAmount = usdai.deposit(957_033_503 * 1e6, users.normalUser1);

        vm.stopPrank();
    }

    function test__BaseYieldAccrual() public {
        uint256 baseYieldAccruedBefore = usdai.baseYieldAccrued();
        assertEq(baseYieldAccruedBefore, 0);

        vm.warp(block.timestamp + 365 days);

        uint256 baseYieldAccruedAfter = usdai.baseYieldAccrued();

        assertApproxEqRel(baseYieldAccruedAfter, usdaiAmount * 450 / 10_000, 4e13);
    }

    function test__HarvestBaseYield() public {
        vm.warp(block.timestamp + 365 days);

        vm.prank(address(stakedUsdai));
        usdai.harvest();

        uint256 balanceAfter = usdai.balanceOf(address(stakedUsdai));
        assertApproxEqRel(balanceAfter, usdaiAmount * 450 / 10_000, 4e13);
    }

    function test__HarvestBaseYieldTwice() public {
        vm.warp(block.timestamp + 182 days);

        vm.startPrank(address(stakedUsdai));
        usdai.harvest();

        vm.warp(block.timestamp + 183 days);

        usdai.harvest();
        vm.stopPrank();

        uint256 balanceAfter = usdai.balanceOf(address(stakedUsdai));
        assertGt(balanceAfter, usdaiAmount * 450 / 10_000);
    }

    function test__ZeroRateNoAccrual() public {
        IUSDai.RateTier[] memory rateTiers = new IUSDai.RateTier[](0);

        vm.prank(users.admin);
        baseYieldEscrow.setRateTiers(rateTiers);

        vm.warp(block.timestamp + 365 days);

        uint256 baseYieldAfter = usdai.baseYieldAccrued();
        assertEq(baseYieldAfter, 0);
    }

    function test__LargeBalanceNoOverflow() public {
        uint256 depositAmount = 100_000_000_000 * 1e6;

        vm.startPrank(users.admin);
        PYUSD.approve(address(usdai), depositAmount);
        usdai.deposit(depositAmount, users.admin);
        vm.stopPrank();

        vm.warp(block.timestamp + 1095 days);

        uint256 baseYieldAfter = usdai.baseYieldAccrued();
        assertGt(baseYieldAfter, 0);
    }

    function testFuzz__HarvestTwice(
        uint256 harvestDays
    ) public {
        vm.assume(harvestDays >= 1);
        vm.assume(harvestDays < 365);

        vm.warp(block.timestamp + harvestDays * 1 days);

        vm.prank(address(stakedUsdai));
        usdai.harvest();

        vm.warp(block.timestamp + 365 days - harvestDays * 1 days);

        vm.prank(address(stakedUsdai));
        usdai.harvest();

        uint256 balanceAfter = usdai.balanceOf(address(stakedUsdai));
        assertGt(balanceAfter, usdaiAmount * 450 / 10_000);
    }

    function test__FrequentAccrualCalls() public {
        uint256 baseYieldAccruedInitial = usdai.baseYieldAccrued();
        assertEq(baseYieldAccruedInitial, 0);

        uint256[] memory accruedSnapshots = new uint256[](11);
        accruedSnapshots[0] = baseYieldAccruedInitial;

        uint256 timestamp = block.timestamp;

        /* Call _accrue() every second for 10 seconds by calling setBaseYieldRate with same rate */
        for (uint256 i = 1; i <= 10; i++) {
            /* Increment timestamp by 1 day */
            timestamp += 1 days;

            /* Warp to new timestamp */
            vm.warp(timestamp);

            /* Set base yield accrual */
            vm.prank(users.admin);

            /* No-op call just to simulate _accrue() */
            IUSDai.RateTier[] memory rateTiers = new IUSDai.RateTier[](2);
            rateTiers[0] = IUSDai.RateTier({rate: BASE_YIELD_RATE_1, threshold: BASE_YIELD_CUTOFF_1});
            rateTiers[1] = IUSDai.RateTier({rate: BASE_YIELD_RATE_2, threshold: BASE_YIELD_CUTOFF_2});
            baseYieldEscrow.setRateTiers(rateTiers);

            accruedSnapshots[i] = usdai.baseYieldAccrued();

            /* Verify yield continues to accrue even with frequent _accrue calls */
            assertGt(accruedSnapshots[i], accruedSnapshots[i - 1]);
        }

        uint256 baseYieldAccruedFinal = usdai.baseYieldAccrued();
        assertGt(baseYieldAccruedFinal, 0);
    }

    function testFuzz__HarvestBaseYield__RandomHarvests(
        uint256 numHarvests
    ) public {
        vm.assume(numHarvests > 0);
        vm.assume(numHarvests <= 100);

        uint256 startTimestamp = block.timestamp;
        uint256 finalHarvestTime = startTimestamp + 365 days;

        uint256 totalElapsedTime;
        for (uint256 i; i < numHarvests; i++) {
            uint256 elapsed = vm.randomUint(0, 365 days - totalElapsedTime);
            totalElapsedTime += elapsed;

            vm.warp(startTimestamp + elapsed);

            vm.prank(address(stakedUsdai));
            usdai.harvest();
        }

        vm.warp(finalHarvestTime);
        vm.prank(address(stakedUsdai));
        usdai.harvest();

        uint256 balanceAfter = usdai.balanceOf(address(stakedUsdai));
        assertGt(balanceAfter, usdaiAmount * 450 / 10_000);
    }
}
