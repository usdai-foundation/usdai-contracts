// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {BaseTest} from "../Base.t.sol";

import {IUSDai} from "../../src/interfaces/IUSDai.sol";

contract StakedUSDaiHarvestBaseYieldTest is BaseTest {
    uint256 internal usdaiAmount;

    function setUp() public override {
        super.setUp();

        vm.prank(users.admin);

        /* Set rate tiers */
        IUSDai.RateTier[] memory rateTiers = new IUSDai.RateTier[](2);
        rateTiers[0] = IUSDai.RateTier({rate: BASE_YIELD_RATE_1, threshold: BASE_YIELD_CUTOFF_1});
        rateTiers[1] = IUSDai.RateTier({rate: BASE_YIELD_RATE_2, threshold: BASE_YIELD_CUTOFF_2});
        baseYieldEscrow.setRateTiers(rateTiers);

        // User approves USDai to spend their USD
        vm.startPrank(users.normalUser1);
        PYUSD.approve(address(usdai), 957_033_503 * 1e6);

        // User deposits amount of USD into USDai (~957,027,799 USD)
        usdaiAmount = usdai.deposit(957_033_503 * 1e6, users.normalUser1);

        // Stake USDai
        usdai.approve(address(stakedUsdai), usdaiAmount);
        stakedUsdai.deposit(usdaiAmount, users.normalUser1);

        vm.stopPrank();

        /* Set base yield accrual timestamp via storage slot */
        vm.store(
            address(usdai),
            bytes32(uint256(0xad76c5b481cb106971e0ae4c23a09cb5b1dc9dba5fad96d9694630df5e853900) + 2),
            bytes32(uint256(block.timestamp))
        );
    }

    function test__StakedUSDaiHarvestBaseYield() public {
        vm.warp(block.timestamp + 365 days);

        uint256 navBefore = stakedUsdai.nav();
        uint256 redemptionSharePriceBefore = stakedUsdai.redemptionSharePrice();
        uint256 depositSharePriceBefore = stakedUsdai.depositSharePrice();

        vm.prank(users.manager);
        (uint256 usdaiYield, uint256 adminFee) = stakedUsdai.harvestBaseYield();

        // Verify yield
        assertApproxEqRel(usdaiYield + adminFee, usdaiAmount * 450 / 10_000, 4e13);

        // Verify no change to NAV, redemption share price, or deposit share price
        assertApproxEqRel(stakedUsdai.nav(), navBefore, 2e4);
        assertApproxEqRel(stakedUsdai.redemptionSharePrice(), redemptionSharePriceBefore, 6e3);
        assertApproxEqRel(stakedUsdai.depositSharePrice(), depositSharePriceBefore, 6e3);
    }
}
