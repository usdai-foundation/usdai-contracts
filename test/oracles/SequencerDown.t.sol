// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {BaseLoanRouterTest} from "../loanRouter/Base.t.sol";
import {MockArbitrumSequencerUptimeFeed} from "../mocks/MockArbitrumSequencerUptimeFeed.sol";

import {ChainlinkPriceOracle} from "src/oracles/ChainlinkPriceOracle.sol";

import {ILoanRouterV2} from "@usdai-loan-router-contracts/interfaces/ILoanRouterV2.sol";

/**
 * @title StakedUSDai sequencer downtime tests
 * @author USD.AI Foundation
 * @dev Verifies that critical StakedUSDai functions revert when the Arbitrum sequencer
 *      uptime feed reports the sequencer is down or still within the grace period.
 *
 *      The ChainlinkPriceOracle's sequencer uptime feed pointer is immutable, so we
 *      install a mock implementation at the live feed address with `vm.etch` and
 *      drive its returned values from the tests.
 *
 *      A USDC-denominated loan is originated in setUp so USDC ends up registered as a
 *      currency token on the loan router position manager. This is what causes
 *      `priceOracle.price(USDC)` (and therefore `_validateSequencer`) to be reached
 *      from the StakedUSDai NAV / share-price code paths.
 */
contract StakedUSDaiSequencerDownTest is BaseLoanRouterTest {
    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    MockArbitrumSequencerUptimeFeed internal mockFeed;

    /*------------------------------------------------------------------------*/
    /* Setup */
    /*------------------------------------------------------------------------*/

    function setUp() public override {
        super.setUp();

        /* Have a user actually deposit so totalShares > 0 and depositSharePrice/
           redemptionSharePrice exercise _assets() instead of short-circuiting.
            The narrow Uniswap pool (tick range [-1, 1]) is completely drained by
           BaseLoanRouterTest.simulateYieldDeposit, so deposit PYUSD directly to
           skip the swap and keep half the resulting USDai approved for reuse in tests. */
        deal(address(PYUSD), users.normalUser1, 1_000_000 ether);
        vm.startPrank(users.normalUser1);
        PYUSD.approve(address(usdai), 1_000_000 ether);
        uint256 usdaiAmount = usdai.deposit(address(PYUSD), 1_000_000 ether, 0, users.normalUser1);
        usdai.approve(address(stakedUsdai), usdaiAmount);
        stakedUsdai.deposit(usdaiAmount / 2, users.normalUser1);
        vm.stopPrank();

        /* Register a USDC-denominated loan so USDC enters the position manager's
           currency tokens set. This is what makes priceOracle.price(USDC) reachable
           inside StakedUSDai._assets(). */
        _registerLoan(1_000_000 * 1e6);

        /* Install mock feed at the immutable sequencer feed address used by ChainlinkPriceOracle. */
        MockArbitrumSequencerUptimeFeed mockImpl = new MockArbitrumSequencerUptimeFeed();
        vm.etch(SEQUENCER_UPTIME_FEED, address(mockImpl).code);
        mockFeed = MockArbitrumSequencerUptimeFeed(SEQUENCER_UPTIME_FEED);

        /* Default to "sequencer up + grace period elapsed" so setUp's assumptions hold and
           tests can flip to a failure mode explicitly. */
        mockFeed.setRoundData(0, block.timestamp - 7200);
    }

    /*------------------------------------------------------------------------*/
    /* Helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Register a USDC-denominated loan in the LoanRouter position manager by
     *         driving the V2 origination hook directly, pranking as the loan router.
     *         This seeds USDC into the currency tokens set (and a pending balance) so
     *         StakedUSDai._assets() reaches priceOracle.price(USDC) — and therefore
     *         _validateSequencer — without exercising the full origination flow.
     */
    function _registerLoan(
        uint256 principal
    ) internal {
        ILoanRouterV2.LoanTermsV2 memory loanTerms = createLoanTerms(principal);
        bytes32 loanTermsHash = loanRouter.loanTermsHash(loanTerms);
        vm.prank(address(loanRouter));
        stakedUsdai.onLoanOriginated(loanTerms, loanTermsHash, 0);
    }

    function _setSequencerDown() internal {
        /* answer != 0 indicates the sequencer is down. */
        mockFeed.setRoundData(1, block.timestamp);
    }

    function _setSequencerInGracePeriod() internal {
        /* answer == 0 (up) but startedAt within GRACE_PERIOD_TIME (3600s). */
        mockFeed.setRoundData(0, block.timestamp - 100);
    }

    /*------------------------------------------------------------------------*/
    /* Sanity check */
    /*------------------------------------------------------------------------*/

    function test__SequencerUp_StakedUSDaiFunctionsWork() public view {
        /* All of these go through ChainlinkPriceOracle.price(USDC) and therefore
           through _validateSequencer. They should succeed when the mock reports
           "up + grace elapsed". */
        stakedUsdai.nav();
        stakedUsdai.totalAssets();
        stakedUsdai.depositSharePrice();
        stakedUsdai.redemptionSharePrice();
        stakedUsdai.loanRouterBalances();
        stakedUsdai.convertToShares(1 ether);
        stakedUsdai.convertToAssets(1 ether);
    }

    /*------------------------------------------------------------------------*/
    /* SequencerDown reverts */
    /*------------------------------------------------------------------------*/

    function test__SequencerDown_RevertsWhen_Nav() public {
        _setSequencerDown();
        vm.expectRevert(ChainlinkPriceOracle.SequencerDown.selector);
        stakedUsdai.nav();
    }

    function test__SequencerDown_RevertsWhen_TotalAssets() public {
        _setSequencerDown();
        vm.expectRevert(ChainlinkPriceOracle.SequencerDown.selector);
        stakedUsdai.totalAssets();
    }

    function test__SequencerDown_RevertsWhen_DepositSharePrice() public {
        _setSequencerDown();
        vm.expectRevert(ChainlinkPriceOracle.SequencerDown.selector);
        stakedUsdai.depositSharePrice();
    }

    function test__SequencerDown_RevertsWhen_RedemptionSharePrice() public {
        _setSequencerDown();
        vm.expectRevert(ChainlinkPriceOracle.SequencerDown.selector);
        stakedUsdai.redemptionSharePrice();
    }

    function test__SequencerDown_RevertsWhen_LoanRouterBalances() public {
        _setSequencerDown();
        vm.expectRevert(ChainlinkPriceOracle.SequencerDown.selector);
        stakedUsdai.loanRouterBalances();
    }

    function test__SequencerDown_RevertsWhen_ConvertToShares() public {
        _setSequencerDown();
        vm.expectRevert(ChainlinkPriceOracle.SequencerDown.selector);
        stakedUsdai.convertToShares(1 ether);
    }

    function test__SequencerDown_RevertsWhen_ConvertToAssets() public {
        _setSequencerDown();
        vm.expectRevert(ChainlinkPriceOracle.SequencerDown.selector);
        stakedUsdai.convertToAssets(1 ether);
    }

    function test__SequencerDown_RevertsWhen_Deposit() public {
        /* normalUser1 still holds USDai with approval set on stakedUsdai from setUp. */
        _setSequencerDown();

        vm.prank(users.normalUser1);
        vm.expectRevert(ChainlinkPriceOracle.SequencerDown.selector);
        stakedUsdai.deposit(100 ether, users.normalUser1);
    }

    function test__SequencerDown_RevertsWhen_Mint() public {
        _setSequencerDown();

        vm.prank(users.normalUser1);
        vm.expectRevert(ChainlinkPriceOracle.SequencerDown.selector);
        stakedUsdai.mint(100 ether, users.normalUser1);
    }

    function test__SequencerDown_RevertsWhen_ServiceRedemptions() public {
        /* Open a redemption request prior to outage so serviceRedemptions has work to do. */
        vm.prank(users.normalUser1);
        stakedUsdai.requestRedeem(100 ether, users.normalUser1, users.normalUser1);

        _setSequencerDown();

        vm.prank(users.manager);
        vm.expectRevert(ChainlinkPriceOracle.SequencerDown.selector);
        stakedUsdai.serviceRedemptions(100 ether);
    }

    /*------------------------------------------------------------------------*/
    /* GracePeriodNotOver reverts */
    /*------------------------------------------------------------------------*/

    function test__SequencerGracePeriod_RevertsWhen_Nav() public {
        _setSequencerInGracePeriod();
        vm.expectRevert(ChainlinkPriceOracle.GracePeriodNotOver.selector);
        stakedUsdai.nav();
    }

    function test__SequencerGracePeriod_RevertsWhen_DepositSharePrice() public {
        _setSequencerInGracePeriod();
        vm.expectRevert(ChainlinkPriceOracle.GracePeriodNotOver.selector);
        stakedUsdai.depositSharePrice();
    }

    function test__SequencerGracePeriod_RevertsWhen_RedemptionSharePrice() public {
        _setSequencerInGracePeriod();
        vm.expectRevert(ChainlinkPriceOracle.GracePeriodNotOver.selector);
        stakedUsdai.redemptionSharePrice();
    }

    function test__SequencerGracePeriod_RevertsWhen_Deposit() public {
        _setSequencerInGracePeriod();

        vm.prank(users.normalUser1);
        vm.expectRevert(ChainlinkPriceOracle.GracePeriodNotOver.selector);
        stakedUsdai.deposit(100 ether, users.normalUser1);
    }

    function test__SequencerGracePeriod_RevertsWhen_ServiceRedemptions() public {
        vm.prank(users.normalUser1);
        stakedUsdai.requestRedeem(100 ether, users.normalUser1, users.normalUser1);

        _setSequencerInGracePeriod();

        vm.prank(users.manager);
        vm.expectRevert(ChainlinkPriceOracle.GracePeriodNotOver.selector);
        stakedUsdai.serviceRedemptions(100 ether);
    }
}
