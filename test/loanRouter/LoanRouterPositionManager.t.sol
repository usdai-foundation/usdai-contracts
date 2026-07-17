// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {ICollateralTimelock} from "@usdai-loan-router-contracts/interfaces/ICollateralTimelock.sol";
import {IDepositTimelock} from "@usdai-loan-router-contracts/interfaces/IDepositTimelock.sol";
import {ILoanRouterV2} from "@usdai-loan-router-contracts/interfaces/ILoanRouterV2.sol";

import {LoanRouterPositionManagerLogic} from "src/positionManagers/LoanRouterPositionManagerLogic.sol";

import {BaseLoanRouterTest} from "./Base.t.sol";

contract LoanRouterPositionManagerTest is BaseLoanRouterTest {
    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    bytes32 internal constant LOAN_HASH = keccak256("test-loan");
    uint256 internal constant DEPOSIT_AMOUNT = 1_000_000 ether;

    /*------------------------------------------------------------------------*/
    /* Helpers */
    /*------------------------------------------------------------------------*/

    function _depositIntoTimelock() internal {
        vm.prank(users.manager);
        stakedUsdai.depositLoanDepositTimelock(LOAN_HASH, DEPOSIT_AMOUNT, uint64(block.timestamp + 7 days));
    }

    /**
     * @notice Originate a loan by calling the onLoanOriginated hook directly under a loan
     *         router prank, skipping the collateral timelock, deposit timelock, and fee model
     *         since none of them affect the accrual rate accounting under test
     * @param loanTermsHash Loan terms hash
     * @param principal Principal amount in USDai
     * @param rate Accrual rate per second scaled by 1e18
     * @return loanTerms Loan terms used for origination
     */
    function _originateLoanDirect(
        bytes32 loanTermsHash,
        uint256 principal,
        uint256 rate
    ) internal returns (ILoanRouterV2.LoanTermsV2 memory loanTerms) {
        // Build loan terms with StakedUSDai as the tranche lender
        loanTerms = createLoanTerms(principal, collateralTokenIds, address(usdai));

        // Set the accrual rate under test
        loanTerms.trancheSpecs[0].rate = rate;

        // Call the origination hook as the loan router
        vm.prank(address(loanRouter));
        stakedUsdai.onLoanOriginated(loanTerms, loanTermsHash, 0);
    }

    /*------------------------------------------------------------------------*/
    /* Wiring */
    /*------------------------------------------------------------------------*/

    function test__LoanRouterDeployed() public view {
        assertTrue(address(loanRouter) != address(0), "loanRouter not deployed");
        assertTrue(address(depositTimelock) != address(0), "depositTimelock not deployed");
    }

    function test__InitialBalances() public view {
        assertEq(stakedUsdai.depositTimelockBalance(), 0, "depositTimelockBalance not 0");
        (uint256 pending, uint256 accrued) = stakedUsdai.loanRouterBalances();
        assertEq(pending, 0, "pendingBalance not 0");
        assertEq(accrued, 0, "accruedBalance not 0");
        assertEq(stakedUsdai.accrualRate(), 0, "accrualRate not 0");
    }

    /*------------------------------------------------------------------------*/
    /* accrualRate() */
    /*------------------------------------------------------------------------*/

    function test__AccrualRate_IncreasesOnLoanOriginated() public {
        uint256 principal = 500_000 ether;

        // Originate a loan at the fixed test rate
        _originateLoanDirect(keccak256("loan-1"), principal, RATE_10_PCT);

        // The pool rate equals the single loan's contribution
        assertEq(stakedUsdai.accrualRate(), RATE_10_PCT * principal, "accrualRate wrong after origination");
    }

    function test__AccrualRate_SumsAcrossMultipleLoans() public {
        uint256 principalOne = 500_000 ether;
        uint256 principalTwo = 250_000 ether;

        // Originate two loans at different rates and principals
        _originateLoanDirect(keccak256("loan-1"), principalOne, RATE_10_PCT);
        _originateLoanDirect(keccak256("loan-2"), principalTwo, GRACE_PERIOD_RATE);

        // The pool rate equals the sum of both loans' contributions
        assertEq(
            stakedUsdai.accrualRate(),
            RATE_10_PCT * principalOne + GRACE_PERIOD_RATE * principalTwo,
            "accrualRate wrong across multiple loans"
        );
    }

    function test__AccrualRate_ZeroOnFullRepayment() public {
        uint256 principal = 500_000 ether;
        bytes32 loanTermsHash = keccak256("loan-1");

        // Originate a loan
        ILoanRouterV2.LoanTermsV2 memory loanTerms = _originateLoanDirect(loanTermsHash, principal, RATE_10_PCT);

        // Repay the loan in full
        vm.prank(address(loanRouter));
        stakedUsdai.onLoanRepayment(loanTerms, loanTermsHash, 0, 0, principal, 1_000 ether, 0);

        // The pool rate returns to 0
        assertEq(stakedUsdai.accrualRate(), 0, "accrualRate not 0 after full repayment");
    }

    function test__AccrualRate_ReflectsNewRateOnPartialRepayment() public {
        uint256 principal = 500_000 ether;
        uint256 principalRepaid = 200_000 ether;
        bytes32 loanTermsHash = keccak256("loan-1");

        // Originate a loan
        ILoanRouterV2.LoanTermsV2 memory loanTerms = _originateLoanDirect(loanTermsHash, principal, RATE_10_PCT);

        // Repay a portion of the principal, leaving the loan active
        vm.prank(address(loanRouter));
        stakedUsdai.onLoanRepayment(
            loanTerms, loanTermsHash, 0, principal - principalRepaid, principalRepaid, 500 ether, 0
        );

        // The pool rate reflects the loan's new, lower balance
        assertEq(
            stakedUsdai.accrualRate(),
            RATE_10_PCT * (principal - principalRepaid),
            "accrualRate wrong after partial repayment"
        );
    }

    function test__AccrualRate_DecreasesOnLiquidation() public {
        uint256 principalOne = 500_000 ether;
        uint256 principalTwo = 250_000 ether;
        bytes32 loanTermsHashOne = keccak256("loan-1");
        bytes32 loanTermsHashTwo = keccak256("loan-2");

        // Originate two loans
        ILoanRouterV2.LoanTermsV2 memory loanTermsOne =
            _originateLoanDirect(loanTermsHashOne, principalOne, RATE_10_PCT);
        _originateLoanDirect(loanTermsHashTwo, principalTwo, GRACE_PERIOD_RATE);

        // Liquidate the first loan
        vm.prank(address(loanRouter));
        stakedUsdai.onLoanLiquidated(loanTermsOne, loanTermsHashOne, 0);

        // The pool rate keeps only the second loan's contribution
        assertEq(stakedUsdai.accrualRate(), GRACE_PERIOD_RATE * principalTwo, "accrualRate wrong after liquidation");
    }

    /*------------------------------------------------------------------------*/
    /* onLoanFeePaid() */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deploy the real AbsoluteFeeModel from the loan-router artifacts so an
     *         origination fee is computed by a genuine fee model rather than a sentinel.
     */
    function _deployAbsoluteFeeModel() internal returns (address) {
        string memory json = vm.readFile("externalOut/AbsoluteFeeModel.sol/AbsoluteFeeModel.json");
        return _deployFromHex(vm.parseJsonString(json, ".bytecode.object"), "");
    }

    /**
     * @notice Originate a USDai loan through the real LoanRouterV2 with an Origination fee
     *         whose recipient is the StakedUSDai position manager. The router computes the
     *         fee with AbsoluteFeeModel, transfers it to StakedUSDai, and invokes the real
     *         onLoanFeePaid() hook — no hand-rolled hook call.
     *
     *         StakedUSDai is both the tranche lender (so onLoanOriginated registers the
     *         currency and pending balance) and the fee recipient (so onLoanFeePaid books
     *         the fee into the deposit balance). The fee equals the FeeSpec options amount,
     *         which createLoanTerms sets to principal / 100. USDai (18 decimals) needs no
     *         oracle conversion, so the booked fee and pending balance are exact.
     * @return fee Origination fee paid, in USDai (currency) units
     */
    function _originateLoanWithOriginationFee(
        uint256 principal
    ) internal returns (uint256 fee) {
        address feeModel = _deployAbsoluteFeeModel();

        /* Build loan terms; redirect the origination fee to a real model paid to StakedUSDai */
        ILoanRouterV2.LoanTermsV2 memory loanTerms = createLoanTerms(principal, collateralTokenIds, address(usdai));
        loanTerms.feeSpecs[0].model = feeModel;
        loanTerms.feeSpecs[0].recipient = address(stakedUsdai);
        fee = abi.decode(loanTerms.feeSpecs[0].options, (uint256));

        bytes32 loanTermsHash = keccak256(abi.encode(block.chainid, loanTerms));
        uint64 expiration = loanTerms.expiration;

        /* Borrower escrows the collateral for this loan into the collateral timelock */
        vm.prank(users.borrower);
        ICollateralTimelock(address(collateralTimelock)).deposit(
            address(loanRouter), loanTermsHash, address(testNFT), collateralTokenIds, expiration
        );

        /* Fund StakedUSDai with the principal (on top of any existing balance) and deposit it */
        deal(address(usdai), address(stakedUsdai), IERC20(address(usdai)).balanceOf(address(stakedUsdai)) + principal);
        vm.startPrank(address(stakedUsdai));
        IERC20(address(usdai)).approve(address(depositTimelock), principal);
        IDepositTimelock(address(depositTimelock)).deposit(
            address(loanRouter), loanTermsHash, address(usdai), principal, expiration
        );
        vm.stopPrank();

        /* Grant the originator role and originate the loan on-chain (deposit timelock funded) */
        vm.prank(users.admin);
        IAccessControl(address(loanRouter)).grantRole(keccak256("ORIGINATOR_ROLE"), users.admin);

        ILoanRouterV2.LenderDepositInfo[] memory depositInfos = new ILoanRouterV2.LenderDepositInfo[](1);
        depositInfos[0] =
            ILoanRouterV2.LenderDepositInfo({depositType: ILoanRouterV2.DepositType.DepositTimelock, data: ""});

        vm.prank(users.admin);
        loanRouter.originate(loanTerms, depositInfos, new bytes[](0));
    }

    function test__OnLoanFeePaid_OriginationFeeBookedIntoDepositBalance() public {
        uint256 principal = 1_000 ether;

        uint256 usdaiBefore = IERC20(address(usdai)).balanceOf(address(stakedUsdai));
        (uint256 depositBalanceBefore,) = stakedUsdai.balances();

        uint256 fee = _originateLoanWithOriginationFee(principal);

        // The fee model returns a non-zero fee; otherwise the hook is never reached
        assertGt(fee, 0, "origination fee is zero");

        // The router transferred exactly the fee in USDai to StakedUSDai (it deposited the full
        // principal into the timelock, so its net balance change is the received fee)
        assertEq(
            IERC20(address(usdai)).balanceOf(address(stakedUsdai)) - usdaiBefore,
            fee,
            "fee not transferred to recipient"
        );

        // onLoanFeePaid booked the fee into the deposit balance; USDai needs no oracle conversion
        (uint256 depositBalanceAfter,) = stakedUsdai.balances();
        assertEq(depositBalanceAfter - depositBalanceBefore, fee, "fee not booked into deposit balance");

        // The principal remains tracked as pending loan balance (registered by onLoanOriginated)
        (uint256 pending,) = stakedUsdai.loanRouterBalances();
        assertEq(pending, principal, "principal not tracked as pending");
    }

    function test__RevertWhen_OnLoanFeePaid_CallerNotLoanRouter() public {
        ILoanRouterV2.LoanTermsV2 memory loanTerms = createLoanTerms(1_000 ether, collateralTokenIds, address(usdai));

        // Only the loan router may invoke the fee hook
        vm.prank(users.borrower);
        vm.expectRevert(LoanRouterPositionManagerLogic.InvalidCaller.selector);
        stakedUsdai.onLoanFeePaid(loanTerms, LOAN_HASH, 0, 1e6);
    }
}
