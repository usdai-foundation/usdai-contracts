// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {ICollateralTimelock} from "@usdai-loan-router-contracts/interfaces/ICollateralTimelock.sol";
import {IDepositTimelock} from "@usdai-loan-router-contracts/interfaces/IDepositTimelock.sol";
import {ILoanRouterV2} from "@usdai-loan-router-contracts/interfaces/ILoanRouterV2.sol";

import {StakedUSDai} from "src/StakedUSDai.sol";
import {IStakedUSDai} from "src/interfaces/IStakedUSDai.sol";

import {BaseLoanRouterTest} from "./Base.t.sol";

/**
 * @title Refinance behavior
 * @author USD.AI Foundation
 *
 * @notice Originates a real USDai loan through the local LoanRouterV2 with StakedUSDai as the
 *         lender, warps forward, then refinances it to a lower rate. The tests assert the
 *         router state, the StakedUSDai loan state, the pool accrual rate change, and the NAV
 *         drop caused by the rate cut over the elapsed window.
 */
contract RefinanceTest is BaseLoanRouterTest {
    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /* Seconds in a year for effective rate checks */
    uint256 internal constant SECONDS_PER_YEAR = 31_536_000;

    /* StakedUSDai loans storage location (erc7201:stakedUSDai.loans) */
    bytes32 internal constant LOANS_STORAGE_LOCATION =
        0xeedf9bea8709bd441d5da250df505e80fc82bec74f9f1df28edf19fa1ed4bd00;

    /* Loan principal originated for every refinance test */
    uint256 internal constant PRINCIPAL = 1_000_000 ether;

    /* Origination rate applied to the loan (per second, 1e18 scaled) */
    uint256 internal constant ORIGINATION_RATE = RATE_10_PCT;

    /* Refinance target rate below the origination rate so NAV drops (per second, 1e18 scaled) */
    uint256 internal constant NEW_RATE = GRACE_PERIOD_RATE; // 5% APR

    /* Elapsed window between origination and refinance */
    uint256 internal constant ELAPSED = 30 days;

    /*------------------------------------------------------------------------*/
    /* Snapshot */
    /*------------------------------------------------------------------------*/

    /**
     * @notice StakedUSDai loan accounting snapshot
     * @param accrualRate Loan accrual rate
     * @param pendingBalance Loan pending balance
     * @param lastRepaymentTimestamp Loan last repayment timestamp
     * @param poolRate Currency pool accrual rate
     */
    struct LoanSnapshot {
        uint256 accrualRate;
        uint256 pendingBalance;
        uint64 lastRepaymentTimestamp;
        uint256 poolRate;
    }

    /*------------------------------------------------------------------------*/
    /* Setup */
    /*------------------------------------------------------------------------*/

    function setUp() public override {
        /* Deploy the full local stack and seed StakedUSDai */
        super.setUp();

        /* Grant the originator role to this test so it can refinance */
        vm.prank(users.admin);
        IAccessControl(address(loanRouter)).grantRole(keccak256("ORIGINATOR_ROLE"), address(this));
    }

    /*------------------------------------------------------------------------*/
    /* Per loan refinance */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Refinancing lands the new rate on the outstanding balance
     */
    function test__RefinanceLoan() public {
        /* Originate a loan and warp past the origination */
        (ILoanRouterV2.LoanTermsV2 memory terms,) = _originateLoan(PRINCIPAL, ORIGINATION_RATE);

        /* Advance time so interest has accrued */
        vm.warp(block.timestamp + ELAPSED);

        /* Refinance to the lower rate and assert the state transition */
        _assertRefinance(terms, NEW_RATE);
    }

    /**
     * @notice Refinancing only lowers NAV and never raises it
     */
    function test__RefinanceLowersNav() public {
        /* Originate a loan and warp past the origination */
        (ILoanRouterV2.LoanTermsV2 memory terms,) = _originateLoan(PRINCIPAL, ORIGINATION_RATE);

        /* Advance time so interest has accrued */
        vm.warp(block.timestamp + ELAPSED);

        /* Read NAV before the refinance */
        uint256 navBefore = IStakedUSDai(address(stakedUsdai)).nav();

        /* Refinance to the lower rate */
        ILoanRouterV2(address(loanRouter)).refinance(terms, _reprice(terms, NEW_RATE));

        /* Read NAV after the refinance */
        uint256 navAfter = IStakedUSDai(address(stakedUsdai)).nav();

        /* The refinance lowered NAV */
        assertLt(navAfter, navBefore, "refinance did not lower NAV");

        /* The drop is small relative to NAV */
        assertLt(navBefore - navAfter, navBefore / 1000, "drop unexpectedly large");
    }

    /*------------------------------------------------------------------------*/
    /* Reverts */
    /*------------------------------------------------------------------------*/

    /**
     * @notice A caller without the originator role cannot refinance
     */
    function test__RevertWhen_CallerNotRefinancer() public {
        /* Originate a loan */
        (ILoanRouterV2.LoanTermsV2 memory terms,) = _originateLoan(PRINCIPAL, ORIGINATION_RATE);

        /* Build the repriced terms */
        ILoanRouterV2.LoanTermsV2 memory newTerms = _reprice(terms, NEW_RATE);

        /* An account without the originator role is rejected */
        vm.prank(address(0xBEEF));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(0xBEEF), keccak256("ORIGINATOR_ROLE")
            )
        );
        ILoanRouterV2(address(loanRouter)).refinance(terms, newTerms);
    }

    /**
     * @notice Changing the principal amount is rejected
     */
    function test__RevertWhen_PrincipalChanged() public {
        /* Originate a loan */
        (ILoanRouterV2.LoanTermsV2 memory terms,) = _originateLoan(PRINCIPAL, ORIGINATION_RATE);

        /* Build the repriced terms */
        ILoanRouterV2.LoanTermsV2 memory newTerms = _reprice(terms, NEW_RATE);

        /* Raise the tranche amount so principal no longer matches */
        newTerms.trancheSpecs[0].amount += 1 ether;

        /* The router rejects the mismatched principal */
        vm.expectRevert(ILoanRouterV2.InvalidAmount.selector);
        ILoanRouterV2(address(loanRouter)).refinance(terms, newTerms);
    }

    /**
     * @notice Refinancing changes only the tranche rate, not principal, collateral, or parties
     */
    function test__RefinanceChangesOnlyRate() public {
        /* Originate a loan */
        (ILoanRouterV2.LoanTermsV2 memory terms,) = _originateLoan(PRINCIPAL, ORIGINATION_RATE);

        /* Build the repriced terms */
        ILoanRouterV2.LoanTermsV2 memory newTerms = _reprice(terms, NEW_RATE);

        /* The rate is the only tranche field that changed */
        assertTrue(newTerms.trancheSpecs[0].rate != terms.trancheSpecs[0].rate, "rate unchanged");
        assertEq(newTerms.trancheSpecs[0].amount, terms.trancheSpecs[0].amount, "amount changed");
        assertEq(newTerms.trancheSpecs[0].lender, terms.trancheSpecs[0].lender, "lender changed");

        /* The borrower, currency, and collateral are unchanged */
        assertEq(newTerms.borrower, terms.borrower, "borrower changed");
        assertEq(newTerms.currencyToken, terms.currencyToken, "currency changed");
        assertEq(newTerms.collateralToken, terms.collateralToken, "collateral token changed");
        assertEq(newTerms.collateralTokenIds.length, terms.collateralTokenIds.length, "collateral count changed");
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Refinance a loan and assert the router state, the StakedUSDai loan state,
     *         the pool accrual rate change, and the NAV drop
     * @param oldTerms Old loan terms
     * @param newRate New per second rate scaled by 1e18
     */
    function _assertRefinance(ILoanRouterV2.LoanTermsV2 memory oldTerms, uint256 newRate) internal {
        /* Hash the old terms */
        bytes32 oldHash = keccak256(abi.encode(block.chainid, oldTerms));

        /* Snapshot before */
        LoanSnapshot memory before = _snapshot(oldHash);

        /* Read NAV before */
        uint256 navBefore = IStakedUSDai(address(stakedUsdai)).nav();

        /* Read aggregate balances before */
        (uint256 pendingBefore,) = StakedUSDai(address(stakedUsdai)).loanRouterBalances();

        /* Old loan is active before */
        (ILoanRouterV2.LoanStatus statusBefore,, uint64 originationBefore, uint256 routerBalanceBefore) =
            ILoanRouterV2(address(loanRouter)).loanState(oldHash);
        assertEq(uint8(statusBefore), uint8(ILoanRouterV2.LoanStatus.Active), "old loan not active");

        /* Build new terms with only the rate changed */
        ILoanRouterV2.LoanTermsV2 memory newTerms = _reprice(oldTerms, newRate);
        bytes32 newHash = keccak256(abi.encode(block.chainid, newTerms));

        /* Elapsed window since the last repayment */
        uint256 elapsed = block.timestamp - before.lastRepaymentTimestamp;

        /* Refinance */
        ILoanRouterV2(address(loanRouter)).refinance(oldTerms, newTerms);

        /* Router marked the old loan as repaid */
        (ILoanRouterV2.LoanStatus oldStatusAfter,,,) = ILoanRouterV2(address(loanRouter)).loanState(oldHash);
        assertEq(uint8(oldStatusAfter), uint8(ILoanRouterV2.LoanStatus.Repaid), "old loan not repaid");

        /* Router created the new loan with the same balance and origination */
        (ILoanRouterV2.LoanStatus newStatus,, uint64 newOrigination, uint256 newRouterBalance) =
            ILoanRouterV2(address(loanRouter)).loanState(newHash);
        assertEq(uint8(newStatus), uint8(ILoanRouterV2.LoanStatus.Active), "new loan not active");
        assertEq(newRouterBalance, routerBalanceBefore, "router balance changed");
        assertEq(newOrigination, originationBefore, "origination changed");

        /* StakedUSDai cleared the old loan entry */
        LoanSnapshot memory oldAfter = _snapshot(oldHash);
        assertEq(oldAfter.lastRepaymentTimestamp, 0, "old loan entry not cleared");

        /* StakedUSDai created the new loan carrying the outstanding balance forward */
        LoanSnapshot memory newLoan = _snapshot(newHash);
        assertEq(newLoan.pendingBalance, before.pendingBalance, "pending balance not carried forward");
        assertEq(newLoan.lastRepaymentTimestamp, before.lastRepaymentTimestamp, "repayment timestamp changed");

        /* New accrual rate is the new rate applied to the outstanding balance */
        uint256 expectedNewAccrualRate = newRate * before.pendingBalance;
        assertEq(newLoan.accrualRate, expectedNewAccrualRate, "new accrual rate wrong");

        /* Effective APR equals the target rate on the outstanding balance */
        assertApproxEqAbs(
            newLoan.accrualRate * SECONDS_PER_YEAR / newLoan.pendingBalance,
            newRate * SECONDS_PER_YEAR,
            SECONDS_PER_YEAR,
            "effective rate off target"
        );

        /* Pool accrual rate moved by exactly the rate delta */
        assertEq(
            newLoan.poolRate, before.poolRate - before.accrualRate + expectedNewAccrualRate, "pool rate delta wrong"
        );

        /* NAV dropped by the rate cut over the elapsed window, net of the admin fee */
        uint256 grossDrop = (before.accrualRate - expectedNewAccrualRate) * elapsed / FIXED_POINT_SCALE;
        uint256 expectedNetDrop = grossDrop - (grossDrop * LOAN_ROUTER_ADMIN_FEE_RATE / BASIS_POINTS_SCALE);
        assertApproxEqAbs(navBefore - IStakedUSDai(address(stakedUsdai)).nav(), expectedNetDrop, 1e13, "NAV drop wrong");

        /* Aggregate pending balance is untouched by the refinance */
        (uint256 pendingAfter,) = StakedUSDai(address(stakedUsdai)).loanRouterBalances();
        assertEq(pendingAfter, pendingBefore, "aggregate pending changed");
    }

    /**
     * @notice Originate a USDai loan through the real LoanRouterV2 with StakedUSDai as the lender
     * @param principal Principal amount in USDai
     * @param rate Origination rate per second scaled by 1e18
     * @return terms Loan terms
     * @return loanTermsHash Loan terms hash
     */
    function _originateLoan(
        uint256 principal,
        uint256 rate
    ) internal returns (ILoanRouterV2.LoanTermsV2 memory terms, bytes32 loanTermsHash) {
        /* Build USDai loan terms with the origination rate */
        terms = createLoanTerms(principal, collateralTokenIds, address(usdai));
        terms.trancheSpecs[0].rate = rate;

        /* Point the origination fee at a real fee model the router can call */
        terms.feeSpecs[0].model = _deployAbsoluteFeeModel();

        /* Hash the loan terms */
        loanTermsHash = keccak256(abi.encode(block.chainid, terms));

        /* Read the expiration for the timelock deposits */
        uint64 expiration = terms.expiration;

        /* Borrower escrows the collateral into the collateral timelock */
        vm.prank(users.borrower);
        ICollateralTimelock(address(collateralTimelock)).deposit(
            address(loanRouter), loanTermsHash, address(testNFT), collateralTokenIds, expiration
        );

        /* Fund StakedUSDai with the principal on top of any existing balance */
        deal(address(usdai), address(stakedUsdai), IERC20(address(usdai)).balanceOf(address(stakedUsdai)) + principal);

        /* Deposit the principal into the deposit timelock */
        vm.startPrank(address(stakedUsdai));
        IERC20(address(usdai)).approve(address(depositTimelock), principal);
        IDepositTimelock(address(depositTimelock)).deposit(
            address(loanRouter), loanTermsHash, address(usdai), principal, expiration
        );
        vm.stopPrank();

        /* Grant the originator role to the admin */
        vm.prank(users.admin);
        IAccessControl(address(loanRouter)).grantRole(keccak256("ORIGINATOR_ROLE"), users.admin);

        /* Build the deposit info for the deposit timelock */
        ILoanRouterV2.LenderDepositInfo[] memory depositInfos = new ILoanRouterV2.LenderDepositInfo[](1);
        depositInfos[0] =
            ILoanRouterV2.LenderDepositInfo({depositType: ILoanRouterV2.DepositType.DepositTimelock, data: ""});

        /* Originate the loan on-chain */
        vm.prank(users.admin);
        loanRouter.originate(terms, depositInfos, new bytes[](0));
    }

    /**
     * @notice Deploy the real AbsoluteFeeModel from the loan-router artifacts
     * @return Fee model address
     */
    function _deployAbsoluteFeeModel() internal returns (address) {
        /* Read the artifact bytecode */
        string memory json = vm.readFile("externalOut/AbsoluteFeeModel.sol/AbsoluteFeeModel.json");

        /* Deploy the fee model with no constructor arguments */
        return _deployFromHex(vm.parseJsonString(json, ".bytecode.object"), "");
    }

    /**
     * @notice Read the StakedUSDai loan and pool accrual state for a loan hash
     * @param loanHash Loan terms hash
     * @return snapshot Loan accounting snapshot
     */
    function _snapshot(
        bytes32 loanHash
    ) internal view returns (LoanSnapshot memory snapshot) {
        /* Loan mapping lives at base slot plus five */
        bytes32 loanSlot = keccak256(abi.encode(loanHash, uint256(LOANS_STORAGE_LOCATION) + 5));

        /* Read accrual rate, pending balance, and packed timestamps */
        snapshot.accrualRate = uint256(vm.load(address(stakedUsdai), loanSlot));
        snapshot.pendingBalance = uint256(vm.load(address(stakedUsdai), bytes32(uint256(loanSlot) + 1)));
        snapshot.lastRepaymentTimestamp = uint64(uint256(vm.load(address(stakedUsdai), bytes32(uint256(loanSlot) + 2))));

        /* Interest accruals mapping lives at base slot plus four, rate at offset one */
        bytes32 accrualSlot = keccak256(abi.encode(address(usdai), uint256(LOANS_STORAGE_LOCATION) + 4));
        snapshot.poolRate = uint256(vm.load(address(stakedUsdai), bytes32(uint256(accrualSlot) + 1)));
    }

    /**
     * @notice Build new loan terms from old terms with a repriced first tranche
     * @param oldTerms Old loan terms
     * @param newRate New per second rate scaled by 1e18
     * @return terms Repriced loan terms
     */
    function _reprice(
        ILoanRouterV2.LoanTermsV2 memory oldTerms,
        uint256 newRate
    ) internal view returns (ILoanRouterV2.LoanTermsV2 memory terms) {
        /* Deep copy the old terms so mutations do not alias the original */
        terms = abi.decode(abi.encode(oldTerms), (ILoanRouterV2.LoanTermsV2));

        /* Change only the first tranche rate */
        terms.trancheSpecs[0].rate = newRate;

        /* Keep the new offer valid regardless of the refinance timing */
        terms.expiration = uint64(block.timestamp + 30 days);
    }
}
