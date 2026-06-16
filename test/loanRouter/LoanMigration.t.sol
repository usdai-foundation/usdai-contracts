// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {ILoanRouterV1} from "@usdai-loan-router-contracts/interfaces/ILoanRouterV1.sol";
import {ILoanRouterV2} from "@usdai-loan-router-contracts/interfaces/ILoanRouterV2.sol";

import {BaseLoanRouterTest} from "./Base.t.sol";

import {LoanRouterPositionManagerLogic} from "src/positionManagers/LoanRouterPositionManagerLogic.sol";

/**
 * @title Loan Migration Tests
 * @author USD.AI Foundation
 * @notice End-to-end tests for onLoanMigrated() on StakedUSDai. Covers same-currency
 *         (USDC -> USDC) and cross-currency (USDC -> USDai) paths, NAV preservation,
 *         state cleanup, and revert conditions.
 *
 * Flow mirrored from migrateLoan() in LoanRouterV2.sol:
 *   1. V1 hash = ILoanRouterV1.loanTermsHash(v1Terms)  (here: keccak256(abi.encode(v1Terms)))
 *   2. computeMigration() validates terms and returns V2 hash = keccak256(abi.encode(chainid, v2Terms))
 *   3. LoanRouterV2 initialises the V2 loan, acquires collateral, mints position NFT
 *      (onLoanOriginated is SKIPPED; isMigration = true)
 *   4. onLoanMigrated() is called on the tranche-0 lender (StakedUSDai)
 *
 * _registerV1Loan() seeds LRPM storage the way the V1 origination hook would have,
 * before any migration call. It is not part of the migration flow itself.
 */
contract LoanMigrationTest is BaseLoanRouterTest {
    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * V1 loan duration: 90 days
     */
    uint64 internal constant V1_DURATION = uint64(90 * 86400);

    /**
     * V1 repayment interval: 30 days
     */
    uint64 internal constant V1_REPAYMENT_INTERVAL = uint64(30 * 86400);

    /*------------------------------------------------------------------------*/
    /* Setup */
    /*------------------------------------------------------------------------*/

    function setUp() public override {
        super.setUp();
    }

    /*------------------------------------------------------------------------*/
    /* Term builders */
    /*------------------------------------------------------------------------*/

    /**
     * @param collateralTokenId_ Lets two loans with identical amounts use
     *        different collateral IDs so their hashes differ.
     */
    function _buildV1Terms(
        uint256 principal,
        address currencyToken,
        uint256 collateralTokenId_
    ) internal view returns (ILoanRouterV1.LoanTerms memory) {
        // Build a single-tranche spec at RATE_10_PCT
        ILoanRouterV1.TrancheSpec[] memory tranches = new ILoanRouterV1.TrancheSpec[](1);

        tranches[0] = ILoanRouterV1.TrancheSpec({lender: address(stakedUsdai), amount: principal, rate: RATE_10_PCT});

        return ILoanRouterV1.LoanTerms({
            expiration: uint64(block.timestamp + 7 days),
            borrower: users.borrower,
            currencyToken: currencyToken,
            collateralToken: address(testNFT),
            collateralTokenId: collateralTokenId_,
            duration: V1_DURATION,
            repaymentInterval: V1_REPAYMENT_INTERVAL,
            interestRateModel: interestRateModel,
            gracePeriodRate: GRACE_PERIOD_RATE,
            gracePeriodDuration: GRACE_PERIOD_DURATION,
            feeSpec: ILoanRouterV1.FeeSpec({originationFee: 0, exitFee: 0}),
            trancheSpecs: tranches,
            collateralWrapperContext: "",
            options: ""
        });
    }

    function _buildV2Terms(
        uint256 principal,
        address currencyToken,
        uint256 collateralTokenId_
    ) internal view returns (ILoanRouterV2.LoanTermsV2 memory) {
        // Build a single-tranche spec at RATE_10_PCT
        ILoanRouterV2.TrancheSpec[] memory tranches = new ILoanRouterV2.TrancheSpec[](1);

        tranches[0] = ILoanRouterV2.TrancheSpec({lender: address(stakedUsdai), amount: principal, rate: RATE_10_PCT});

        uint256[] memory tokenIds = new uint256[](1);

        tokenIds[0] = collateralTokenId_;

        return ILoanRouterV2.LoanTermsV2({
            expiration: uint64(block.timestamp + 7 days),
            borrower: users.borrower,
            currencyToken: currencyToken,
            collateralToken: address(testNFT),
            collateralTokenIds: tokenIds,
            trancheSpecs: tranches,
            feeSpecs: new ILoanRouterV2.FeeSpec[](0),
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

    /*------------------------------------------------------------------------*/
    /* Hash helpers — match the real production computation */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Approximates ILoanRouterV1.loanTermsHash(). The real V1 router
     *         uses its own hash scheme; keccak256(abi.encode(terms)) is
     *         sufficient for test key consistency.
     */
    function _hashV1Terms(
        ILoanRouterV1.LoanTerms memory v1Terms
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v1Terms));
    }

    /**
     * @notice Matches LoanLogicV2._hashLoanTerms():
     *         keccak256(abi.encode(block.chainid, loanTerms)).
     *         This is what computeMigration() returns as loanTermsHashV2.
     */
    function _hashV2Terms(
        ILoanRouterV2.LoanTermsV2 memory v2Terms
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, v2Terms));
    }

    /*------------------------------------------------------------------------*/
    /* Setup and assertion helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Seed LRPM storage with the V1 loan's pendingBalance and accrualRate.
     *         Simulates the V1 origination hook that would have registered this loan
     *         in LRPM storage before any migration call.
     *         Note: onLoanOriginated is NOT called during migrateLoan(); this is
     *         pre-migration setup only.
     */
    function _registerV1Loan(ILoanRouterV1.LoanTerms memory v1Terms, bytes32 hashV1) internal {
        // V2-shaped terms so the V2 onLoanOriginated path sets pendingBalance and accrualRate
        ILoanRouterV2.LoanTermsV2 memory v1AsV2 =
            _buildV2Terms(v1Terms.trancheSpecs[0].amount, v1Terms.currencyToken, v1Terms.collateralTokenId);

        // prank as loanRouter so msg.sender == stakedUsdai._loanRouterV2
        vm.prank(address(loanRouter));
        stakedUsdai.onLoanOriginated(v1AsV2, hashV1, 0);
    }

    /**
     * @notice Force-register a loan at an explicit hash (no term-hash consistency).
     *         Only used to pre-occupy a storage slot in edge-case revert tests.
     */
    function _registerLoanAtHash(
        bytes32 hash,
        address currencyToken,
        uint256 principal,
        uint256 collateralTokenId_
    ) internal {
        // Loan terms do not have to correspond to hash — LRPM never validates this
        vm.prank(address(loanRouter));
        stakedUsdai.onLoanOriginated(_buildV2Terms(principal, currencyToken, collateralTokenId_), hash, 0);
    }

    /**
     * @notice Assert the V1 loan was deleted from LRPM storage by attempting
     *         a second migration on the same V1 hash, which must revert with LoanNotFound.
     *         LoanNotFound fires before DuplicateOrigination, so the sentinel V2 hash
     *         does not need to be free.
     */
    function _assertV1LoanGone(
        bytes32 hashV1,
        ILoanRouterV1.LoanTerms memory v1Terms,
        ILoanRouterV2.LoanTermsV2 memory v2Terms,
        bytes32 hashV2
    ) internal {
        // Reuse the same V2 hash and terms; LoanNotFound fires first
        vm.prank(address(loanRouter));

        vm.expectRevert(LoanRouterPositionManagerLogic.LoanNotFound.selector);

        stakedUsdai.onLoanMigrated(v1Terms, hashV1, v2Terms, hashV2, 0);
    }

    /**
     * @notice Assert the V2 loan is present in LRPM storage.
     * @dev loanOriginated has no duplicate check so we probe loanMigrated instead.
     *      loanMigrated checks LoanNotFound before DuplicateOrigination, so we seed a
     *      sentinel V1 entry then attempt to migrate it to hashV2 — DuplicateOrigination
     *      fires because hashV2 is already occupied.  vm.revertTo cleans up the sentinel.
     */
    function _assertV2LoanPresent(bytes32 hashV2, ILoanRouterV2.LoanTermsV2 memory v2Terms) internal {
        bytes32 sentinelHash = keccak256(abi.encodePacked("sentinel", hashV2));
        uint256 snap = vm.snapshot();

        _registerLoanAtHash(sentinelHash, v2Terms.currencyToken, v2Terms.trancheSpecs[0].amount, collateralTokenIds[1]);

        vm.expectRevert(LoanRouterPositionManagerLogic.DuplicateOrigination.selector);
        vm.prank(address(loanRouter));
        stakedUsdai.onLoanMigrated(
            _buildV1Terms(v2Terms.trancheSpecs[0].amount, v2Terms.currencyToken, collateralTokenIds[1]),
            sentinelHash,
            v2Terms,
            hashV2,
            0
        );

        vm.revertTo(snap);
    }

    /*------------------------------------------------------------------------*/
    /* Same-currency tests (USDC -> USDC) */
    /*------------------------------------------------------------------------*/

    function test_SameCurrency_NavUnchanged() public {
        uint256 principal = 1_000e6;

        // V1 terms and hash computed at origination time (T0)
        ILoanRouterV1.LoanTerms memory v1Terms = _buildV1Terms(principal, USDC, collateralTokenIds[0]);

        bytes32 hashV1 = _hashV1Terms(v1Terms);

        _registerV1Loan(v1Terms, hashV1);

        // Warp 30 days so accrued interest is non-zero at migration
        warp(30 days);

        // V2 terms and hash computed at migration time (T1); different expiration → different hash
        ILoanRouterV2.LoanTermsV2 memory v2Terms = _buildV2Terms(principal, USDC, collateralTokenIds[0]);

        bytes32 hashV2 = _hashV2Terms(v2Terms);

        // Snapshot LRPM balances immediately before the hook call
        (uint256 repaymentBefore, uint256 pendingBefore, uint256 accruedBefore) = stakedUsdai.loanRouterBalances();

        vm.prank(address(loanRouter));

        stakedUsdai.onLoanMigrated(v1Terms, hashV1, v2Terms, hashV2, 0);

        // All three balance components must be exactly equal for same-currency (no oracle conversion)
        (uint256 repaymentAfter, uint256 pendingAfter, uint256 accruedAfter) = stakedUsdai.loanRouterBalances();

        assertEq(repaymentBefore, repaymentAfter, "repayment changed");

        assertEq(pendingBefore, pendingAfter, "pending changed");

        assertEq(accruedBefore, accruedAfter, "accrued changed");

        // V1 loan entry must be gone; V2 must be present
        _assertV1LoanGone(hashV1, v1Terms, v2Terms, hashV2);

        _assertV2LoanPresent(hashV2, v2Terms);
    }

    /*------------------------------------------------------------------------*/
    /* Cross-currency tests (USDC 6 dec -> USDai 18 dec) */
    /*------------------------------------------------------------------------*/

    function test_CrossCurrency_NavUnchanged() public {
        uint256 v1Principal = 1_000e6;

        // V1 terms and hash at origination (T0)
        ILoanRouterV1.LoanTerms memory v1Terms = _buildV1Terms(v1Principal, USDC, collateralTokenIds[0]);

        bytes32 hashV1 = _hashV1Terms(v1Terms);

        _registerV1Loan(v1Terms, hashV1);

        // Warp 30 days so accrued interest is non-zero at migration
        warp(30 days);

        // V2 terms at migration time (T1); amount scaled 6-dec -> 18-dec
        uint256 v2Principal = v1Principal * 1e12;

        ILoanRouterV2.LoanTermsV2 memory v2Terms = _buildV2Terms(v2Principal, address(usdai), collateralTokenIds[0]);

        bytes32 hashV2 = _hashV2Terms(v2Terms);

        (uint256 repaymentBefore, uint256 pendingBefore, uint256 accruedBefore) = stakedUsdai.loanRouterBalances();

        vm.prank(address(loanRouter));

        stakedUsdai.onLoanMigrated(v1Terms, hashV1, v2Terms, hashV2, 0);

        // Total NAV within 0.1%: the ~0.01% deviation is the real USDC/USDai oracle spread
        // (Chainlink USDC feed at Arbitrum block 333898546: $1.0000806; PYUSD mock: $0.9999796)
        (uint256 repaymentAfter, uint256 pendingAfter, uint256 accruedAfter) = stakedUsdai.loanRouterBalances();

        uint256 totalBefore = repaymentBefore + pendingBefore + accruedBefore;

        uint256 totalAfter = repaymentAfter + pendingAfter + accruedAfter;

        assertApproxEqRel(totalBefore, totalAfter, 1e15, "total NAV changed beyond oracle spread");

        // Repayment pool untouched
        assertEq(repaymentBefore, repaymentAfter, "repayment changed");

        // Pending switches from USDC-oracle-priced to USDai 1:1.
        // Expected value is v1Principal scaled by the fixed 10^12 decimal factor, not v2Principal
        // (which was derived from that same factor — asserting against it directly would be circular).
        assertEq(pendingAfter, uint256(v1Principal) * 1e12, "USDai pending wrong");

        _assertV1LoanGone(hashV1, v1Terms, v2Terms, hashV2);

        _assertV2LoanPresent(hashV2, v2Terms);
    }

    /*------------------------------------------------------------------------*/
    /* Edge cases */
    /*------------------------------------------------------------------------*/

    function test_MigrateAtOrigination_ZeroAccruedInterest() public {
        // No warp: V1 and V2 terms built at same block, zero elapsed time
        uint256 principal = 1_000e6;

        ILoanRouterV1.LoanTerms memory v1Terms = _buildV1Terms(principal, USDC, collateralTokenIds[0]);

        bytes32 hashV1 = _hashV1Terms(v1Terms);

        _registerV1Loan(v1Terms, hashV1);

        ILoanRouterV2.LoanTermsV2 memory v2Terms = _buildV2Terms(principal, USDC, collateralTokenIds[0]);

        bytes32 hashV2 = _hashV2Terms(v2Terms);

        (uint256 repaymentBefore, uint256 pendingBefore, uint256 accruedBefore) = stakedUsdai.loanRouterBalances();

        vm.prank(address(loanRouter));

        stakedUsdai.onLoanMigrated(v1Terms, hashV1, v2Terms, hashV2, 0);

        (uint256 repaymentAfter, uint256 pendingAfter, uint256 accruedAfter) = stakedUsdai.loanRouterBalances();

        // No time has passed so nothing should have accrued in either snapshot
        assertEq(accruedBefore, 0, "accrued before not zero");

        assertEq(accruedAfter, 0, "accrued after not zero");

        assertEq(pendingBefore, pendingAfter, "pending changed");

        assertEq(repaymentBefore, repaymentAfter, "repayment changed");
    }

    function test_TwoMigrationsPreserveNav() public {
        // Two independent USDC loans with different principals (different hashes)
        uint256 principalA = 1_000e6;

        uint256 principalB = 500e6;

        // V1 terms at T0; different amounts give different hashes
        ILoanRouterV1.LoanTerms memory v1TermsA = _buildV1Terms(principalA, USDC, collateralTokenIds[0]);

        ILoanRouterV1.LoanTerms memory v1TermsB = _buildV1Terms(principalB, USDC, collateralTokenIds[0]);

        bytes32 hashV1A = _hashV1Terms(v1TermsA);

        bytes32 hashV1B = _hashV1Terms(v1TermsB);

        _registerV1Loan(v1TermsA, hashV1A);

        _registerV1Loan(v1TermsB, hashV1B);

        warp(30 days);

        // V2 terms at T1; different amounts give different V2 hashes
        ILoanRouterV2.LoanTermsV2 memory v2TermsA = _buildV2Terms(principalA, USDC, collateralTokenIds[0]);

        ILoanRouterV2.LoanTermsV2 memory v2TermsB = _buildV2Terms(principalB, USDC, collateralTokenIds[0]);

        bytes32 hashV2A = _hashV2Terms(v2TermsA);

        bytes32 hashV2B = _hashV2Terms(v2TermsB);

        (uint256 repaymentBefore, uint256 pendingBefore, uint256 accruedBefore) = stakedUsdai.loanRouterBalances();

        vm.startPrank(address(loanRouter));

        stakedUsdai.onLoanMigrated(v1TermsA, hashV1A, v2TermsA, hashV2A, 0);

        stakedUsdai.onLoanMigrated(v1TermsB, hashV1B, v2TermsB, hashV2B, 0);

        vm.stopPrank();

        (uint256 repaymentAfter, uint256 pendingAfter, uint256 accruedAfter) = stakedUsdai.loanRouterBalances();

        assertEq(repaymentBefore, repaymentAfter, "repayment changed");

        assertEq(pendingBefore, pendingAfter, "pending changed");

        assertEq(accruedBefore, accruedAfter, "accrued changed");
    }

    function test_CrossAndSameCurrencyMigrations_NavUnchanged() public {
        // Loan A: USDC -> USDai (cross-currency)
        // Loan B: USDC -> USDC (same-currency)
        // Both loans have same principal and currency; they differ by collateral token ID
        // so their V1 hashes are distinct
        uint256 v1Principal = 1_000e6;

        uint256 v2PrincipalA = v1Principal * 1e12;

        // V1 terms at T0; different collateral IDs prevent hash collision
        ILoanRouterV1.LoanTerms memory v1TermsA = _buildV1Terms(v1Principal, USDC, collateralTokenIds[0]);

        ILoanRouterV1.LoanTerms memory v1TermsB = _buildV1Terms(v1Principal, USDC, collateralTokenIds[1]);

        bytes32 hashV1A = _hashV1Terms(v1TermsA);

        bytes32 hashV1B = _hashV1Terms(v1TermsB);

        _registerV1Loan(v1TermsA, hashV1A);

        _registerV1Loan(v1TermsB, hashV1B);

        warp(30 days);

        // V2 terms at T1
        ILoanRouterV2.LoanTermsV2 memory v2TermsA = _buildV2Terms(v2PrincipalA, address(usdai), collateralTokenIds[0]);

        ILoanRouterV2.LoanTermsV2 memory v2TermsB = _buildV2Terms(v1Principal, USDC, collateralTokenIds[1]);

        bytes32 hashV2A = _hashV2Terms(v2TermsA);

        bytes32 hashV2B = _hashV2Terms(v2TermsB);

        (uint256 repaymentBefore, uint256 pendingBefore, uint256 accruedBefore) = stakedUsdai.loanRouterBalances();

        vm.startPrank(address(loanRouter));

        stakedUsdai.onLoanMigrated(v1TermsA, hashV1A, v2TermsA, hashV2A, 0);

        stakedUsdai.onLoanMigrated(v1TermsB, hashV1B, v2TermsB, hashV2B, 0);

        vm.stopPrank();

        (uint256 repaymentAfter, uint256 pendingAfter, uint256 accruedAfter) = stakedUsdai.loanRouterBalances();

        // Same-currency preserves exactly; cross-currency has oracle spread -> use approx on total
        assertApproxEqRel(
            repaymentBefore + pendingBefore + accruedBefore,
            repaymentAfter + pendingAfter + accruedAfter,
            1e15,
            "total NAV changed beyond oracle spread"
        );

        // Accrued must carry over from both pools
        assertApproxEqRel(accruedBefore, accruedAfter, 1e15, "accrued changed beyond oracle spread");
    }

    /*------------------------------------------------------------------------*/
    /* Revert cases */
    /*------------------------------------------------------------------------*/

    function test_RevertWhen_CallerNotLoanRouter() public {
        // InvalidCaller fires before any loan lookup — no setup needed
        ILoanRouterV1.LoanTerms memory v1Terms = _buildV1Terms(1_000e6, USDC, collateralTokenIds[0]);

        ILoanRouterV2.LoanTermsV2 memory v2Terms = _buildV2Terms(1_000e6, USDC, collateralTokenIds[0]);

        vm.prank(users.borrower);

        vm.expectRevert(LoanRouterPositionManagerLogic.InvalidCaller.selector);

        stakedUsdai.onLoanMigrated(v1Terms, _hashV1Terms(v1Terms), v2Terms, _hashV2Terms(v2Terms), 0);
    }

    function test_RevertWhen_LenderNotStakedUsdai() public {
        // InvalidLender fires before any loan lookup — no setup needed
        ILoanRouterV1.LoanTerms memory v1Terms = _buildV1Terms(1_000e6, USDC, collateralTokenIds[0]);

        ILoanRouterV2.LoanTermsV2 memory v2Terms = _buildV2Terms(1_000e6, USDC, collateralTokenIds[0]);

        // Swap in a wrong lender so _validateHookContext rejects it
        v2Terms.trancheSpecs[0].lender = users.borrower;

        vm.prank(address(loanRouter));

        vm.expectRevert(LoanRouterPositionManagerLogic.InvalidLender.selector);

        stakedUsdai.onLoanMigrated(v1Terms, _hashV1Terms(v1Terms), v2Terms, _hashV2Terms(v2Terms), 0);
    }

    function test_RevertWhen_V1LoanNotFound() public {
        // Never register the V1 loan — LoanNotFound fires when the slot is empty
        ILoanRouterV1.LoanTerms memory v1Terms = _buildV1Terms(1_000e6, USDC, collateralTokenIds[0]);

        ILoanRouterV2.LoanTermsV2 memory v2Terms = _buildV2Terms(1_000e6, USDC, collateralTokenIds[0]);

        vm.prank(address(loanRouter));

        vm.expectRevert(LoanRouterPositionManagerLogic.LoanNotFound.selector);

        stakedUsdai.onLoanMigrated(v1Terms, _hashV1Terms(v1Terms), v2Terms, _hashV2Terms(v2Terms), 0);
    }

    function test_RevertWhen_V2HashAlreadyUsed() public {
        uint256 principal = 1_000e6;

        ILoanRouterV1.LoanTerms memory v1Terms = _buildV1Terms(principal, USDC, collateralTokenIds[0]);

        bytes32 hashV1 = _hashV1Terms(v1Terms);

        _registerV1Loan(v1Terms, hashV1);

        ILoanRouterV2.LoanTermsV2 memory v2Terms = _buildV2Terms(principal, USDC, collateralTokenIds[0]);

        bytes32 hashV2 = _hashV2Terms(v2Terms);

        // Pre-occupy the V2 storage slot with a different loan
        _registerLoanAtHash(hashV2, USDC, principal, collateralTokenIds[0]);

        vm.prank(address(loanRouter));

        vm.expectRevert(LoanRouterPositionManagerLogic.DuplicateOrigination.selector);

        stakedUsdai.onLoanMigrated(v1Terms, hashV1, v2Terms, hashV2, 0);
    }

    function test_RevertWhen_SameV1AndV2Hash() public {
        // V1 slot is occupied, so using the same hash for V2 triggers DuplicateOrigination
        uint256 principal = 1_000e6;

        ILoanRouterV1.LoanTerms memory v1Terms = _buildV1Terms(principal, USDC, collateralTokenIds[0]);

        bytes32 hashV1 = _hashV1Terms(v1Terms);

        _registerV1Loan(v1Terms, hashV1);

        ILoanRouterV2.LoanTermsV2 memory v2Terms = _buildV2Terms(principal, USDC, collateralTokenIds[0]);

        vm.prank(address(loanRouter));

        vm.expectRevert(LoanRouterPositionManagerLogic.DuplicateOrigination.selector);

        // Pass hashV1 as the V2 hash — the occupied slot triggers DuplicateOrigination
        stakedUsdai.onLoanMigrated(v1Terms, hashV1, v2Terms, hashV1, 0);
    }

    /*------------------------------------------------------------------------*/
    /* Continued-accrual tests */
    /*------------------------------------------------------------------------*/

    function test_ContinuedAccrualAfterMigration_SameCurrency() public {
        // Register V1 USDC loan at T0, warp 30 days to T1, migrate, warp 30 more days to T2.
        // The accrual delta T1->T2 must equal the accrual delta T0->T1 because the same
        // currency and same rate are used before and after migration.
        uint256 principal = 1_000e6;

        ILoanRouterV1.LoanTerms memory v1Terms = _buildV1Terms(principal, USDC, collateralTokenIds[0]);

        bytes32 hashV1 = _hashV1Terms(v1Terms);

        _registerV1Loan(v1Terms, hashV1);

        warp(30 days);

        ILoanRouterV2.LoanTermsV2 memory v2Terms = _buildV2Terms(principal, USDC, collateralTokenIds[0]);

        bytes32 hashV2 = _hashV2Terms(v2Terms);

        vm.prank(address(loanRouter));

        stakedUsdai.onLoanMigrated(v1Terms, hashV1, v2Terms, hashV2, 0);

        // Snapshot accrued at T1 right after migration
        (,, uint256 accruedAtMigration) = stakedUsdai.loanRouterBalances();

        warp(30 days);

        // Snapshot accrued at T2 = T1 + 30 days
        (,, uint256 accruedAtT2) = stakedUsdai.loanRouterBalances();

        // Both windows are 30 days at the same rate and oracle price, so the deltas must be equal.
        // Tolerance of 1 wei accommodates floor(2A/1e18) != 2*floor(A/1e18) rounding.
        // Any real rate change would cause a difference proportional to the principal, not 1 wei.
        assertApproxEqAbs(accruedAtT2 - accruedAtMigration, accruedAtMigration, 1, "accrual rate changed by migration");
    }

    function test_ContinuedAccrualAfterMigration_CrossCurrency() public {
        // After USDC->USDai migration the USDai accrual delta must match the exact formula.
        // Exact equality is possible because USDai needs no oracle conversion.
        // If the USDC pool had any residual accrual rate, accruedAtT2 would exceed expectedDelta.
        uint256 v1Principal = 1_000e6;

        ILoanRouterV1.LoanTerms memory v1Terms = _buildV1Terms(v1Principal, USDC, collateralTokenIds[0]);

        bytes32 hashV1 = _hashV1Terms(v1Terms);

        _registerV1Loan(v1Terms, hashV1);

        warp(30 days);

        // V2 principal scaled from 6-dec to 18-dec
        ILoanRouterV2.LoanTermsV2 memory v2Terms =
            _buildV2Terms(v1Principal * 1e12, address(usdai), collateralTokenIds[0]);

        bytes32 hashV2 = _hashV2Terms(v2Terms);

        vm.prank(address(loanRouter));

        stakedUsdai.onLoanMigrated(v1Terms, hashV1, v2Terms, hashV2, 0);

        (,, uint256 accruedAtMigration) = stakedUsdai.loanRouterBalances();

        warp(30 days);

        (,, uint256 accruedAtT2) = stakedUsdai.loanRouterBalances();

        // accrualRateV2 = RATE_10_PCT * (v1Principal * 1e12)
        // delta = accrualRateV2 * 30 days / FIXED_POINT_SCALE
        uint256 expectedDelta = uint256(RATE_10_PCT) * v1Principal * 1e12 * uint256(30 * 86400) / FIXED_POINT_SCALE;

        assertEq(accruedAtT2 - accruedAtMigration, expectedDelta, "cross-currency accrual rate wrong");
    }

    /*------------------------------------------------------------------------*/
    /* Partial V1 repayment before migration */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Simulate a partial V1 repayment via the mock router.
     *         triggerLoanRepayment uses try/catch, so verify the pending balance
     *         dropped to confirm the hook executed.
     */
    function _triggerPartialRepayment(
        ILoanRouterV1.LoanTerms memory v1Terms,
        bytes32 hashV1,
        uint256 remainingBalance,
        uint256 principalPaid
    ) internal {
        // V2-shaped terms with the matching currency and lender so _validateHookContext passes
        ILoanRouterV2.LoanTermsV2 memory repayTerms =
            _buildV2Terms(v1Terms.trancheSpecs[0].amount, v1Terms.currencyToken, v1Terms.collateralTokenId);

        // loanBalance > 0 signals a partial repayment; the loan is NOT deleted
        vm.prank(address(loanRouter));
        stakedUsdai.onLoanRepayment(repayTerms, hashV1, 0, remainingBalance, principalPaid, 0, 0);
    }

    function test_PartialV1Repayment_ThenMigration() public {
        // T0: register V1 USDC 1000e6
        // T1: partial repayment — 200e6 paid, 800e6 remains, lastRepaymentTimestamp = T1
        // T2: migrate — pendingBalanceV2 derives from 800e6, injection uses T1 not T0
        uint256 originalPrincipal = 1_000e6;

        uint256 remainingBalance = 800e6;

        uint256 principalPaid = 200e6;

        ILoanRouterV1.LoanTerms memory v1Terms = _buildV1Terms(originalPrincipal, USDC, collateralTokenIds[0]);

        bytes32 hashV1 = _hashV1Terms(v1Terms);

        _registerV1Loan(v1Terms, hashV1);

        // Warp 30 days; make partial repayment at T1
        warp(30 days);

        (uint256 repaymentBeforeRepay, uint256 pendingBeforeRepay,) = stakedUsdai.loanRouterBalances();

        _triggerPartialRepayment(v1Terms, hashV1, remainingBalance, principalPaid);

        // Confirm the repayment hook executed: pending dropped, repayment balance rose
        (uint256 repaymentAfterRepay, uint256 pendingAfterRepay,) = stakedUsdai.loanRouterBalances();

        assertGt(pendingBeforeRepay, pendingAfterRepay, "partial repayment did not reduce pending");

        assertGt(repaymentAfterRepay, repaymentBeforeRepay, "partial repayment did not raise repayment balance");

        // Warp 30 more days then migrate at T2
        warp(30 days);

        ILoanRouterV2.LoanTermsV2 memory v2Terms = _buildV2Terms(remainingBalance, USDC, collateralTokenIds[0]);

        bytes32 hashV2 = _hashV2Terms(v2Terms);

        (uint256 repaymentBefore, uint256 pendingBefore, uint256 accruedBefore) = stakedUsdai.loanRouterBalances();

        vm.prank(address(loanRouter));

        stakedUsdai.onLoanMigrated(v1Terms, hashV1, v2Terms, hashV2, 0);

        (uint256 repaymentAfter, uint256 pendingAfter, uint256 accruedAfter) = stakedUsdai.loanRouterBalances();

        // NAV must be exactly preserved: same currency, same oracle, same rate
        assertEq(repaymentBefore, repaymentAfter, "repayment changed");

        assertEq(pendingBefore, pendingAfter, "pending changed");

        assertEq(accruedBefore, accruedAfter, "accrued changed");

        // Pending reflects the post-repayment balance (800e6), not the original (1000e6)
        assertEq(pendingAfter, pendingAfterRepay, "migration used wrong pendingBalance");

        // V1 gone, V2 present
        _assertV1LoanGone(hashV1, v1Terms, v2Terms, hashV2);

        _assertV2LoanPresent(hashV2, v2Terms);
    }

    /*------------------------------------------------------------------------*/
    /* Post-migration origination */
    /*------------------------------------------------------------------------*/

    function test_MigrationThenOrigination() public {
        // Migrate a USDC loan, then originate a second USDC loan in the same pool.
        // The two pending balances should combine additively.
        uint256 migratedPrincipal = 1_000e6;

        uint256 newPrincipal = 500e6;

        ILoanRouterV1.LoanTerms memory v1Terms = _buildV1Terms(migratedPrincipal, USDC, collateralTokenIds[0]);

        bytes32 hashV1 = _hashV1Terms(v1Terms);

        _registerV1Loan(v1Terms, hashV1);

        // Migrate at T0 — no warp keeps the formula simple
        ILoanRouterV2.LoanTermsV2 memory v2Terms = _buildV2Terms(migratedPrincipal, USDC, collateralTokenIds[0]);

        bytes32 hashV2 = _hashV2Terms(v2Terms);

        vm.prank(address(loanRouter));

        stakedUsdai.onLoanMigrated(v1Terms, hashV1, v2Terms, hashV2, 0);

        (, uint256 pendingAfterMigration,) = stakedUsdai.loanRouterBalances();

        // Originate a fresh V2 USDC loan with a different collateral ID (different hash)
        ILoanRouterV2.LoanTermsV2 memory freshV2Terms = _buildV2Terms(newPrincipal, USDC, collateralTokenIds[1]);

        bytes32 freshHashV2 = _hashV2Terms(freshV2Terms);

        vm.prank(address(loanRouter));
        stakedUsdai.onLoanOriginated(freshV2Terms, freshHashV2, 0);

        (, uint256 pendingAfterOrigination,) = stakedUsdai.loanRouterBalances();

        // pendingAfterOrigination / pendingAfterMigration = (1000 + 500) / 1000 = 3/2.
        // This ratio holds exactly regardless of oracle price.
        assertEq(pendingAfterOrigination * 2, pendingAfterMigration * 3, "post-migration origination NAV wrong");
    }

    /*------------------------------------------------------------------------*/
    /* Amount mismatch — V2 principal one dollar below V1 */
    /*------------------------------------------------------------------------*/

    function test_V2PrincipalOneDollarLow_NavDropsByPrincipalPlusAccruedDelta() public {
        // V1: 1000 USDC. V2: 999 USDC ($1 less).
        // Same per-unit rate (RATE_10_PCT) but different amounts, so
        // accrualRateV2 = RATE_10_PCT * 999e6 != accrualRateV1 = RATE_10_PCT * 1000e6.
        // Expected NAV loss = $1 in pending + 10% APR on $1 for 30 days in accrued,
        // both scaled from USDC (6 dec) to USDai (18 dec) via the base-token factor 1e12.
        uint256 v1Principal = 1_000e6;
        uint256 v2Principal = 999e6;

        ILoanRouterV1.LoanTerms memory v1Terms = _buildV1Terms(v1Principal, USDC, collateralTokenIds[0]);

        bytes32 hashV1 = _hashV1Terms(v1Terms);

        _registerV1Loan(v1Terms, hashV1);

        uint256 elapsed = 30 days;

        warp(elapsed);

        ILoanRouterV2.LoanTermsV2 memory v2Terms = _buildV2Terms(v2Principal, USDC, collateralTokenIds[0]);

        bytes32 hashV2 = _hashV2Terms(v2Terms);

        (uint256 repaymentBefore, uint256 pendingBefore, uint256 accruedBefore) = stakedUsdai.loanRouterBalances();

        uint256 navBefore = repaymentBefore + pendingBefore + accruedBefore;

        vm.prank(address(loanRouter));

        stakedUsdai.onLoanMigrated(v1Terms, hashV1, v2Terms, hashV2, 0);

        (uint256 repaymentAfter, uint256 pendingAfter, uint256 accruedAfter) = stakedUsdai.loanRouterBalances();

        uint256 navAfter = repaymentAfter + pendingAfter + accruedAfter;

        // Repayment pool is untouched by migration.
        assertEq(repaymentBefore, repaymentAfter, "repayment changed");

        // Pending drops by approximately the $1 principal difference scaled to USDai.
        // USDC routes through the Chainlink oracle (not the flat 1e12 base-token path),
        // so the exact drop depends on the oracle price. 0.1% covers the spread.
        assertApproxEqRel(pendingBefore - pendingAfter, (v1Principal - v2Principal) * 1e12, 1e15, "pending drop wrong");

        // NAV loss = principal drop + accrued drop, oracle-converted.
        // The formula uses the flat 1e12 factor as a reference; 0.1% covers the oracle spread.
        uint256 principalDiff = v1Principal - v2Principal;

        uint256 accrualDiff = RATE_10_PCT * principalDiff * elapsed / FIXED_POINT_SCALE;

        uint256 expectedLoss = (principalDiff + accrualDiff) * 1e12;

        assertApproxEqRel(navBefore - navAfter, expectedLoss, 1e15, "NAV loss wrong");
    }

    /*------------------------------------------------------------------------*/
    /* Unsupported V2 currency */
    /*------------------------------------------------------------------------*/

    function test_RevertWhen_UnsupportedV2Currency() public {
        // _validateCurrencyToken rejects currencies not in USDai, baseToken, or the oracle
        uint256 principal = 1_000e6;

        ILoanRouterV1.LoanTerms memory v1Terms = _buildV1Terms(principal, USDC, collateralTokenIds[0]);

        bytes32 hashV1 = _hashV1Terms(v1Terms);

        _registerV1Loan(v1Terms, hashV1);

        // Use address(testNFT) as currency: not USDai, not PYUSD base, not in oracle
        ILoanRouterV2.LoanTermsV2 memory v2Terms = _buildV2Terms(principal, address(testNFT), collateralTokenIds[0]);

        bytes32 hashV2 = _hashV2Terms(v2Terms);

        vm.prank(address(loanRouter));

        vm.expectRevert(
            abi.encodeWithSelector(LoanRouterPositionManagerLogic.UnsupportedCurrency.selector, address(testNFT))
        );

        stakedUsdai.onLoanMigrated(v1Terms, hashV1, v2Terms, hashV2, 0);
    }

    /*------------------------------------------------------------------------*/
    /* Repayment after migration */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Fully repay a migrated V2 loan through the repayment hook.
     *         loanBalance == 0 deletes the loan and settles its accrued interest.
     * @param interest Cash interest booked into the repayment pool
     */
    function _triggerFullV2Repayment(
        ILoanRouterV2.LoanTermsV2 memory v2Terms,
        bytes32 hashV2,
        uint256 interest
    ) internal {
        vm.prank(address(loanRouter));
        stakedUsdai.onLoanRepayment(v2Terms, hashV2, 0, 0, v2Terms.trancheSpecs[0].amount, interest, 0);
    }

    /**
     * @notice Partially repay a migrated V2 loan through the repayment hook.
     *         loanBalance > 0 keeps the loan alive and resets lastRepaymentTimestamp.
     */
    function _triggerPartialV2Repayment(
        ILoanRouterV2.LoanTermsV2 memory v2Terms,
        bytes32 hashV2,
        uint256 remainingBalance,
        uint256 principalPaid,
        uint256 interest
    ) internal {
        vm.prank(address(loanRouter));
        stakedUsdai.onLoanRepayment(v2Terms, hashV2, 0, remainingBalance, principalPaid, interest, 0);
    }

    /**
     * @notice A full repayment of a migrated loan must drive accrued interest back to zero.
     *         Migration injects the pre-migration interest window into the V2 pool, and the
     *         V2 loan anchors lastRepaymentTimestamp at the V1 timestamp (T0), so the full
     *         repayment settles the entire T0->T2 window.
     *         The previous code anchored at the migration time (T1), so the repayment only
     *         settled T1->T2 and left a permanent residual of RATE_10_PCT * 1000e6 * 30 days
     *         in the accrued pool, overstating NAV forever.
     */
    function test_FullRepaymentAfterMigration_SameCurrency_NoResidualAccrued() public {
        // T0: register V1 USDC loan. T1 = T0 + 30d: migrate. T2 = T1 + 30d: full repayment.
        uint256 principal = 1_000e6;

        ILoanRouterV1.LoanTerms memory v1Terms = _buildV1Terms(principal, USDC, collateralTokenIds[0]);

        bytes32 hashV1 = _hashV1Terms(v1Terms);

        _registerV1Loan(v1Terms, hashV1);

        warp(30 days);

        ILoanRouterV2.LoanTermsV2 memory v2Terms = _buildV2Terms(principal, USDC, collateralTokenIds[0]);

        bytes32 hashV2 = _hashV2Terms(v2Terms);

        vm.prank(address(loanRouter));

        stakedUsdai.onLoanMigrated(v1Terms, hashV1, v2Terms, hashV2, 0);

        warp(30 days);

        (uint256 repaymentBefore,, uint256 accruedBefore) = stakedUsdai.loanRouterBalances();

        // Accrued spans the full 60-day T0->T2 window, not just the post-migration 30 days
        assertGt(accruedBefore, 0, "no accrued interest before repayment");

        // Book a cash interest payment. The exact value is arbitrary: it lands in the repayment
        // pool and never feeds the accrued pool, which settles off the loan's stored timestamp.
        _triggerFullV2Repayment(v2Terms, hashV2, 100e6);

        (uint256 repaymentAfter, uint256 pendingAfter, uint256 accruedAfter) = stakedUsdai.loanRouterBalances();

        // No phantom residual survives a full repayment
        assertEq(accruedAfter, 0, "accrued not cleared after full repayment");

        // Principal fully repaid
        assertEq(pendingAfter, 0, "pending not cleared after full repayment");

        // Interest counted once, as cash in the repayment pool
        assertGt(repaymentAfter, repaymentBefore, "repayment cash not booked");
    }

    /**
     * @notice Cross-currency variant. USDai needs no oracle conversion, so accrued is exact:
     *         the residual the old code would leave is an exact nonzero value, and the fix
     *         drives accrued to exactly zero after a full repayment.
     */
    function test_FullRepaymentAfterMigration_CrossCurrency_NoResidualAccrued() public {
        uint256 v1Principal = 1_000e6;

        uint256 v2Principal = v1Principal * 1e12;

        ILoanRouterV1.LoanTerms memory v1Terms = _buildV1Terms(v1Principal, USDC, collateralTokenIds[0]);

        bytes32 hashV1 = _hashV1Terms(v1Terms);

        _registerV1Loan(v1Terms, hashV1);

        warp(30 days);

        ILoanRouterV2.LoanTermsV2 memory v2Terms = _buildV2Terms(v2Principal, address(usdai), collateralTokenIds[0]);

        bytes32 hashV2 = _hashV2Terms(v2Terms);

        vm.prank(address(loanRouter));

        stakedUsdai.onLoanMigrated(v1Terms, hashV1, v2Terms, hashV2, 0);

        warp(30 days);

        // accrualRateV2 spans 60 days of the loan: 30 injected days + 30 post-migration days
        uint256 accrualRateV2 = uint256(RATE_10_PCT) * v2Principal;

        uint256 expectedAccrued = accrualRateV2 * uint256(60 * 86400) / FIXED_POINT_SCALE;

        (,, uint256 accruedBefore) = stakedUsdai.loanRouterBalances();

        assertEq(accruedBefore, expectedAccrued, "accrued before repayment wrong");

        // The previous code would have left accrualRateV2 * 30 days here after full repayment

        // Borrower pays the full 60-day interest in cash
        _triggerFullV2Repayment(v2Terms, hashV2, expectedAccrued);

        (,, uint256 accruedAfter) = stakedUsdai.loanRouterBalances();

        // Accrued returns to exactly zero with no residual
        assertEq(accruedAfter, 0, "accrued not cleared after full repayment");
    }

    /**
     * @notice A partial repayment of the migrated loan must settle the full pre-migration
     *         injected interest, not just the post-migration window. Immediately after the
     *         partial repayment accrued is zero, because the fixed code settles T0->T2 in full
     *         and resets the loan timestamp; the remaining balance then accrues forward.
     */
    function test_PartialRepaymentAfterMigration_CrossCurrency_SettlesInjectedInterest() public {
        uint256 v1Principal = 1_000e6;

        uint256 v2Principal = v1Principal * 1e12;

        ILoanRouterV1.LoanTerms memory v1Terms = _buildV1Terms(v1Principal, USDC, collateralTokenIds[0]);

        bytes32 hashV1 = _hashV1Terms(v1Terms);

        _registerV1Loan(v1Terms, hashV1);

        warp(30 days);

        ILoanRouterV2.LoanTermsV2 memory v2Terms = _buildV2Terms(v2Principal, address(usdai), collateralTokenIds[0]);

        bytes32 hashV2 = _hashV2Terms(v2Terms);

        vm.prank(address(loanRouter));

        stakedUsdai.onLoanMigrated(v1Terms, hashV1, v2Terms, hashV2, 0);

        warp(30 days);

        // Repay half the principal; the loan stays alive with the remaining balance
        uint256 principalPaid = v2Principal / 2;

        uint256 remainingBalance = v2Principal - principalPaid;

        // Cash interest value is arbitrary: it lands in the repayment pool, not the accrued pool
        _triggerPartialV2Repayment(v2Terms, hashV2, remainingBalance, principalPaid, 100e18);

        (,, uint256 accruedAfterPartial) = stakedUsdai.loanRouterBalances();

        // The injected pre-migration interest is settled in full, leaving no residual
        assertEq(accruedAfterPartial, 0, "injected interest not settled by partial repayment");

        // The remaining balance accrues forward from the repayment instant
        warp(30 days);

        uint256 expectedForward = uint256(RATE_10_PCT) * remainingBalance * uint256(30 * 86400) / FIXED_POINT_SCALE;

        (,, uint256 accruedForward) = stakedUsdai.loanRouterBalances();

        assertEq(accruedForward, expectedForward, "post-repayment accrual rate wrong");
    }
}
