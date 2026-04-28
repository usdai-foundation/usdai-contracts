// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {Vm} from "forge-std/Vm.sol";

import {BaseTest} from "../Base.t.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {SimpleInterestRateModel} from "@usdai-loan-router-contracts/rates/SimpleInterestRateModel.sol";
import {USDaiSwapAdapter} from "@usdai-loan-router-contracts/swapAdapters/USDaiSwapAdapter.sol";
import {ILoanRouter} from "@usdai-loan-router-contracts/interfaces/ILoanRouter.sol";

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
    uint64 internal constant LOAN_DURATION = 1080 days; // 3 years - 5 days
    uint64 internal constant REPAYMENT_INTERVAL = 30 days;
    uint64 internal constant GRACE_PERIOD_DURATION = 30 days;

    /* Rate constants (per second) */
    // 5% per annum = 0.05 / (365 * 86400) = ~1.585e-9 per second
    uint256 internal constant GRACE_PERIOD_RATE = 1585489599; // 5% APR in per-second rate (scaled by 1e18)

    // Interest rates for tranches (per second, scaled by 1e18)
    // 10% APR = ~3.171e-9 per second = 3171469679 (scaled by 1e18)
    uint256 internal constant RATE_10_PCT = 3171469679;

    /* Number of token IDs to wrap */
    uint256 internal constant NUM_TOKEN_IDS = 128;

    /*------------------------------------------------------------------------*/
    /* Contract instances */
    /*------------------------------------------------------------------------*/

    SimpleInterestRateModel internal interestRateModel;
    USDaiSwapAdapter internal usdaiSwapAdapter;

    TestERC721 internal testNFT;

    /*------------------------------------------------------------------------*/
    /* Test state */
    /*------------------------------------------------------------------------*/

    uint256 internal wrappedTokenId;
    uint256[] internal tokenIdsToWrap;
    bytes internal encodedBundle;

    // Second bundle for multi-loan tests
    uint256 internal wrappedTokenId2;
    uint256[] internal tokenIdsToWrap2;
    bytes internal encodedBundle2;

    /*------------------------------------------------------------------------*/
    /* Setup */
    /*------------------------------------------------------------------------*/

    function setUp() public virtual override {
        super.setUp();

        // Deploy test NFT
        deployTestNFT();

        // Deploy contracts
        deployInterestRateModel();
        deployUSDaiSwapAdapter();

        // Setup
        setupCollateralWrapper();
        simulateYieldDeposit(10_000_000 ether);
    }

    /*------------------------------------------------------------------------*/
    /* Deployment functions */
    /*------------------------------------------------------------------------*/

    function deployInterestRateModel() internal {
        vm.startPrank(users.deployer);
        interestRateModel = new SimpleInterestRateModel();
        vm.stopPrank();
    }

    function deployUSDaiSwapAdapter() internal {
        vm.startPrank(users.deployer);
        usdaiSwapAdapter = new USDaiSwapAdapter(address(usdai));
        depositTimelock.addSwapAdapter(address(usdai), address(usdaiSwapAdapter));
        vm.stopPrank();
    }

    function deployTestNFT() internal {
        vm.startPrank(users.deployer);
        testNFT = new TestERC721("TestNFT", "TNFT", "https://testnft.com/token/");
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* Setup functions */
    /*------------------------------------------------------------------------*/

    function setupCollateralWrapper() internal {
        // Mint NFTs to borrower
        vm.startPrank(users.deployer);

        // Create first array of token IDs to wrap
        tokenIdsToWrap = new uint256[](NUM_TOKEN_IDS);
        for (uint256 i = 0; i < NUM_TOKEN_IDS; i++) {
            uint256 tokenId = 1000 + i;
            testNFT.mint(users.borrower, tokenId);
            tokenIdsToWrap[i] = tokenId;
        }

        // Create second array of token IDs to wrap
        tokenIdsToWrap2 = new uint256[](NUM_TOKEN_IDS);
        for (uint256 i = 0; i < NUM_TOKEN_IDS; i++) {
            uint256 tokenId = 2000 + i;
            testNFT.mint(users.borrower, tokenId);
            tokenIdsToWrap2[i] = tokenId;
        }

        vm.stopPrank();

        // Wrap first bundle
        vm.startPrank(users.borrower);

        // Approve collateral wrapper to transfer NFTs
        testNFT.setApprovalForAll(address(bundleCollateralWrapper), true);

        // Record logs to capture BundleMinted event
        vm.recordLogs();

        // Mint first bundle (wrap NFTs)
        wrappedTokenId = bundleCollateralWrapper.mint(address(testNFT), tokenIdsToWrap);

        // Get the BundleMinted event and extract encodedBundle
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("BundleMinted(uint256,address,bytes)")) {
                encodedBundle = abi.decode(logs[i].data, (bytes));
                break;
            }
        }

        require(encodedBundle.length > 0, "Failed to capture encodedBundle from event");

        // Wrap second bundle
        vm.recordLogs();

        // Mint second bundle (wrap NFTs)
        wrappedTokenId2 = bundleCollateralWrapper.mint(address(testNFT), tokenIdsToWrap2);

        // Get the BundleMinted event and extract encodedBundle2
        Vm.Log[] memory logs2 = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs2.length; i++) {
            if (logs2[i].topics[0] == keccak256("BundleMinted(uint256,address,bytes)")) {
                encodedBundle2 = abi.decode(logs2[i].data, (bytes));
                break;
            }
        }

        require(encodedBundle2.length > 0, "Failed to capture encodedBundle2 from event");

        IERC721(bundleCollateralWrapper).setApprovalForAll(address(loanRouter), true);
        IERC20(USDC).approve(address(loanRouter), type(uint256).max);
        vm.stopPrank();
    }

    /*------------------------------------------------------------------------*/
    /* Helper functions */
    /*------------------------------------------------------------------------*/

    function createLoanTerms(
        uint256 principal
    ) internal view returns (ILoanRouter.LoanTerms memory) {
        return createLoanTerms(principal, wrappedTokenId, encodedBundle);
    }

    function createLoanTerms(
        uint256 principal,
        uint256 _wrappedTokenId,
        bytes memory _encodedBundle
    ) internal view returns (ILoanRouter.LoanTerms memory) {
        return createLoanTerms(principal, _wrappedTokenId, _encodedBundle, USDC);
    }

    function createLoanTerms(
        uint256 principal,
        uint256 _wrappedTokenId,
        bytes memory _encodedBundle,
        address currencyToken
    ) internal view returns (ILoanRouter.LoanTerms memory) {
        ILoanRouter.TrancheSpec[] memory trancheSpecs = new ILoanRouter.TrancheSpec[](1);

        trancheSpecs[0] = ILoanRouter.TrancheSpec({lender: address(stakedUsdai), amount: principal, rate: RATE_10_PCT});

        return ILoanRouter.LoanTerms({
            expiration: uint64(block.timestamp + 7 days),
            borrower: users.borrower,
            currencyToken: currencyToken,
            collateralToken: address(bundleCollateralWrapper),
            collateralTokenId: _wrappedTokenId,
            duration: LOAN_DURATION,
            repaymentInterval: REPAYMENT_INTERVAL,
            interestRateModel: address(interestRateModel),
            gracePeriodRate: GRACE_PERIOD_RATE,
            gracePeriodDuration: uint256(GRACE_PERIOD_DURATION),
            feeSpec: ILoanRouter.FeeSpec({
                originationFee: principal / 100, // 1% origination fee
                exitFee: 0
            }),
            trancheSpecs: trancheSpecs,
            collateralWrapperContext: _encodedBundle,
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
