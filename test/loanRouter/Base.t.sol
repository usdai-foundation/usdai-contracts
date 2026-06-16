// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BaseTest} from "../Base.t.sol";

import {ILoanRouterV2} from "@usdai-loan-router-contracts/interfaces/ILoanRouterV2.sol";

import {TestERC721} from "test/tokens/TestERC721.sol";

/**
 * @title Base test setup for LoanRouter Position Manager
 * @author USD.AI Foundation
 */
abstract contract BaseLoanRouterTest is BaseTest {
    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /* Time constants */
    uint16 internal constant DURATION_DAYS = 1080; // 3 years - 5 days
    uint8 internal constant REPAYMENT_DAY = 1;
    uint64 internal constant GRACE_PERIOD_DURATION = 30 days;

    /* Rate constants (per second) */
    uint256 internal constant GRACE_PERIOD_RATE = 1585489599; // 5% APR in per-second rate (scaled by 1e18)
    uint256 internal constant RATE_10_PCT = 3171469679; // 10% APR (per-second, 1e18 scaled)

    /* Number of NFTs minted for collateral */
    uint256 internal constant NUM_TOKEN_IDS = 128;

    /*------------------------------------------------------------------------*/
    /* Contract instances */
    /*------------------------------------------------------------------------*/

    address internal interestRateModel;
    address internal usdaiSwapAdapter;
    address internal originationFeeModel;

    TestERC721 internal testNFT;

    /*------------------------------------------------------------------------*/
    /* Test state */
    /*------------------------------------------------------------------------*/

    uint256[] internal collateralTokenIds;
    uint256[] internal collateralTokenIds2;

    /*------------------------------------------------------------------------*/
    /* Setup */
    /*------------------------------------------------------------------------*/

    function setUp() public virtual override {
        super.setUp();

        deployTestNFT();
        deploySentinels();

        setupCollateral();
        simulateYieldDeposit(10_000_000 ether);
    }

    /*------------------------------------------------------------------------*/
    /* Deployment functions */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Stuff plausible non-zero addresses into LoanTermsV2 fields that the mock
     *         router never dereferences. Real fee/rate/adapter contracts would replace
     *         these in production.
     */
    function deploySentinels() internal {
        interestRateModel = makeAddr("interestRateModel");
        usdaiSwapAdapter = makeAddr("usdaiSwapAdapter");
        originationFeeModel = makeAddr("originationFeeModel");
    }

    function deployTestNFT() internal {
        vm.startPrank(users.deployer);
        testNFT = new TestERC721("TestNFT", "TNFT", "https://testnft.com/token/");
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* Setup functions */
    /*------------------------------------------------------------------------*/

    function setupCollateral() internal {
        vm.startPrank(users.deployer);

        collateralTokenIds = new uint256[](NUM_TOKEN_IDS);
        for (uint256 i = 0; i < NUM_TOKEN_IDS; i++) {
            uint256 tokenId = 1000 + i;
            testNFT.mint(users.borrower, tokenId);
            collateralTokenIds[i] = tokenId;
        }

        collateralTokenIds2 = new uint256[](NUM_TOKEN_IDS);
        for (uint256 i = 0; i < NUM_TOKEN_IDS; i++) {
            uint256 tokenId = 2000 + i;
            testNFT.mint(users.borrower, tokenId);
            collateralTokenIds2[i] = tokenId;
        }

        vm.stopPrank();

        vm.startPrank(users.borrower);
        testNFT.setApprovalForAll(address(collateralTimelock), true);
        IERC20(USDC).approve(address(loanRouter), type(uint256).max);
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* Helper functions */
    /*------------------------------------------------------------------------*/

    function createLoanTerms(
        uint256 principal
    ) internal view virtual returns (ILoanRouterV2.LoanTermsV2 memory) {
        return createLoanTerms(principal, collateralTokenIds);
    }

    function createLoanTerms(
        uint256 principal,
        uint256[] memory _collateralTokenIds
    ) internal view virtual returns (ILoanRouterV2.LoanTermsV2 memory) {
        return createLoanTerms(principal, _collateralTokenIds, USDC);
    }

    function createLoanTerms(
        uint256 principal,
        uint256[] memory _collateralTokenIds,
        address currencyToken
    ) internal view returns (ILoanRouterV2.LoanTermsV2 memory) {
        ILoanRouterV2.TrancheSpec[] memory trancheSpecs = new ILoanRouterV2.TrancheSpec[](1);
        trancheSpecs[0] =
            ILoanRouterV2.TrancheSpec({lender: address(stakedUsdai), amount: principal, rate: RATE_10_PCT});

        ILoanRouterV2.FeeSpec[] memory feeSpecs = new ILoanRouterV2.FeeSpec[](1);
        feeSpecs[0] = ILoanRouterV2.FeeSpec({
            kind: ILoanRouterV2.FeeKind.Origination,
            recipient: users.feeRecipient,
            model: originationFeeModel,
            options: abi.encode(uint256(principal / 100))
        });

        return ILoanRouterV2.LoanTermsV2({
            expiration: uint64(block.timestamp + 7 days),
            borrower: users.borrower,
            currencyToken: currencyToken,
            collateralToken: address(testNFT),
            collateralTokenIds: _collateralTokenIds,
            trancheSpecs: trancheSpecs,
            feeSpecs: feeSpecs,
            interestRateSpec: ILoanRouterV2.InterestRateSpec({
                model: interestRateModel,
                options: abi.encode(uint64(GRACE_PERIOD_DURATION), uint256(GRACE_PERIOD_RATE))
            }),
            repaymentSpec: ILoanRouterV2.RepaymentSpec({
                day: REPAYMENT_DAY,
                totalDurationDays: DURATION_DAYS,
                timezoneOffsetSeconds: 0
            }),
            approvalAddresses: new address[](0),
            options: ""
        });
    }

    function warp(
        uint256 timeInSeconds
    ) internal {
        vm.warp(block.timestamp + timeInSeconds);
    }

    function calculateExpectedInterest(
        uint256 principal,
        uint256 rate,
        uint256 duration
    ) internal pure returns (uint256) {
        return (principal * rate * duration) / FIXED_POINT_SCALE;
    }
}
