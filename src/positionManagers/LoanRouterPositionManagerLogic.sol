// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import {IUSDai} from "../interfaces/IUSDai.sol";

import {ILoanRouterV2} from "@usdai-loan-router-contracts/interfaces/ILoanRouterV2.sol";

import {LoanRouterPositionManager} from "./LoanRouterPositionManager.sol";
import {StakedUSDaiStorage} from "../StakedUSDaiStorage.sol";
import {PositionManager} from "./PositionManager.sol";

/**
 * @title Loan Router Position Manager Logic
 * @author USD.AI Foundation
 */
library LoanRouterPositionManagerLogic {
    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Fixed point scale
     */
    uint256 private constant FIXED_POINT_SCALE = 1e18;

    /**
     * @notice Basis points scale
     */
    uint256 private constant BASIS_POINTS_SCALE = 10_000;

    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid caller
     */
    error InvalidCaller();

    /**
     * @notice Invalid lender
     */
    error InvalidLender();

    /**
     * @notice Duplicate origination
     */
    error DuplicateOrigination();

    /**
     * @notice Duplicate deposit
     */
    error DuplicateDeposit();

    /**
     * @notice Loan not found
     */
    error LoanNotFound();

    /**
     * @notice Invalid currency token
     */
    error InvalidCurrencyToken();

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Validate hook context
     * @param loanTerms Loan terms
     * @param trancheIndex Tranche index
     * @param loanRouter Loan router
     */
    function _validateHookContext(
        ILoanRouterV2.LoanTermsV2 calldata loanTerms,
        uint8 trancheIndex,
        address loanRouter
    ) internal view {
        /* Validate caller is loan router */
        if (msg.sender != loanRouter) revert InvalidCaller();

        /* Validate loan terms */
        if (loanTerms.trancheSpecs[trancheIndex].lender != address(this)) revert InvalidLender();
    }

    /**
     * @notice Update accrued interest and timestamp
     * @param accrual Accrual
     * @param oldAccrualRate Old accrual rate
     * @param timestamp Timestamp
     * @param lastRepaymentTimestamp Last repayment timestamp
     */
    function _accrue(
        LoanRouterPositionManager.Accrual storage accrual,
        uint256 oldAccrualRate,
        uint64 timestamp,
        uint64 lastRepaymentTimestamp
    ) internal {
        /* Accrue scaled interest */
        accrual.accrued = accrual.accrued + accrual.rate * (block.timestamp - accrual.timestamp)
            - (oldAccrualRate * (timestamp - lastRepaymentTimestamp));

        /* Update timestamp */
        accrual.timestamp = uint64(block.timestamp);
    }

    /**
     * @notice Handle interest accrued hook
     * @param depositsStorage Deposits storage
     * @param usdai USDai
     * @param adminFeeRate Admin fee rate
     * @param adminFeeRecipient Admin fee recipient
     * @param interest Interest amount
     */
    function _escrowInterestAccrued(
        StakedUSDaiStorage.Deposits storage depositsStorage,
        address usdai,
        uint256 adminFeeRate,
        address adminFeeRecipient,
        uint256 interest
    ) internal {
        /* Do nothing if interest is 0 */
        if (interest == 0) return;

        /* Compute admin fee amount */
        uint256 adminFee = interest * adminFeeRate / BASIS_POINTS_SCALE;

        /* Update deposit balance with interest amount minus admin fee */
        depositsStorage.balance += interest - adminFee;

        /* Transfer admin fee to recipient */
        if (adminFee != 0) IUSDai(usdai).transfer(adminFeeRecipient, adminFee);
    }

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get loan router balances
     * @param loansStorage Loans storage
     * @param usdai USDai
     * @return Pending loan balance
     * @return Accrued loan interest balance
     */
    function loanRouterBalances(
        LoanRouterPositionManager.Loans storage loansStorage,
        address usdai
    ) external view returns (uint256, uint256) {
        /* Get USDai accrual */
        LoanRouterPositionManager.Accrual storage accrual = loansStorage.interestAccruals[usdai];

        /* Compute unscaled accrued interest */
        uint256 accrued = (accrual.accrued + accrual.rate * (block.timestamp - accrual.timestamp)) / FIXED_POINT_SCALE;

        /* Return loan router balance */
        return (loansStorage.pendingBalances[usdai], accrued);
    }

    /*------------------------------------------------------------------------*/
    /* Hook Logic */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Handle deposit timelock withdrawn hook
     * @param depositsStorage Deposits storage
     * @param depositTimelock Deposit timelock
     * @param refundedAmount Refunded amount
     */
    function depositWithdrawn(
        StakedUSDaiStorage.Deposits storage depositsStorage,
        address depositTimelock,
        uint256 refundedAmount
    ) external {
        /* Validate caller is deposit timelock */
        if (msg.sender != depositTimelock) revert InvalidCaller();

        /* Do nothing if amount is 0 */
        if (refundedAmount == 0) return;

        /* Update deposit balance with refunded amount */
        depositsStorage.balance += refundedAmount;
    }

    /**
     * @notice Handle loan originated hook
     * @param depositTimelockStorage Deposit timelock storage
     * @param loansStorage Loans storage
     * @param loanTerms Loan terms
     * @param loanTermsHash Loan terms hash
     * @param trancheIndex Tranche index
     * @param usdai USDai
     * @param loanRouter Loan router
     */
    function loanOriginated(
        LoanRouterPositionManager.DepositTimelock storage depositTimelockStorage,
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouterV2.LoanTermsV2 calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex,
        address usdai,
        address loanRouter
    ) external {
        /* Validate hook context */
        _validateHookContext(loanTerms, trancheIndex, loanRouter);

        /* Validate USDai */
        if (loanTerms.currencyToken != usdai) revert InvalidCurrencyToken();

        /* Subtract deposited USDai amount from deposit timelock balance */
        depositTimelockStorage.balance -= depositTimelockStorage.amounts[loanTermsHash];

        /* Delete deposit timelock amount for loan terms hash */
        delete depositTimelockStorage.amounts[loanTermsHash];

        /* Compute scaled accrual rate */
        uint256 accrualRate = loanTerms.trancheSpecs[trancheIndex].rate * loanTerms.trancheSpecs[trancheIndex].amount;

        /* Validate loan not already tracked */
        if (loansStorage.loan[loanTermsHash].lastRepaymentTimestamp != 0) revert DuplicateOrigination();

        /* Update loan in loans storage */
        loansStorage.loan[loanTermsHash] = LoanRouterPositionManager.Loan(
            accrualRate, loanTerms.trancheSpecs[trancheIndex].amount, uint64(block.timestamp), 0
        );

        /* Add loan balance to currency token balances storage */
        loansStorage.pendingBalances[loanTerms.currencyToken] += loanTerms.trancheSpecs[trancheIndex].amount;

        /* Get interest accrual */
        LoanRouterPositionManager.Accrual storage accrual = loansStorage.interestAccruals[loanTerms.currencyToken];

        /* Update accrued interest and timestamp */
        _accrue(accrual, 0, 0, 0);

        /* Update unscaled rate */
        accrual.rate += accrualRate;
    }

    /**
     * @notice Handle loan repayment hook
     * @param depositsStorage Deposits storage
     * @param loansStorage Loans storage
     * @param loanTerms Loan terms
     * @param loanTermsHash Loan terms hash
     * @param trancheIndex Tranche index
     * @param loanBalance Loan balance
     * @param principal Principal amount
     * @param interest Interest amount
     * @param loanRouter Loan router
     * @param adminFeeRate Admin fee rate
     * @param adminFeeRecipient Admin fee recipient
     */
    function loanRepayment(
        StakedUSDaiStorage.Deposits storage depositsStorage,
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouterV2.LoanTermsV2 calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex,
        uint256 loanBalance,
        uint256 principal,
        uint256 interest,
        address loanRouter,
        uint256 adminFeeRate,
        address adminFeeRecipient
    ) external {
        /* Validate hook context */
        _validateHookContext(loanTerms, trancheIndex, loanRouter);

        /* Get loan */
        LoanRouterPositionManager.Loan storage loan = loansStorage.loan[loanTermsHash];

        /* Compute admin fee amount */
        uint256 adminFee = interest * adminFeeRate / BASIS_POINTS_SCALE;

        /* Adjust for rounding losses and rounding gains */
        principal = loanBalance == 0 ? loan.pendingBalance : Math.min(loan.pendingBalance, principal);

        /* Update deposit balance */
        depositsStorage.balance += principal + interest - adminFee;

        /* Update total pending loan balances */
        loansStorage.pendingBalances[loanTerms.currencyToken] -= principal;

        /* Compute new loan balance */
        uint256 newLoanBalance = loan.pendingBalance - principal;

        /* Compute scaled new accrual rate */
        uint256 newAccrualRate = loanTerms.trancheSpecs[trancheIndex].rate * newLoanBalance;

        /* Get interest accrual */
        LoanRouterPositionManager.Accrual storage accrual = loansStorage.interestAccruals[loanTerms.currencyToken];

        /* Update accrued interest and timestamp */
        _accrue(accrual, loan.accrualRate, uint64(block.timestamp), loan.lastRepaymentTimestamp);

        /* Update unscaled rate */
        accrual.rate = accrual.rate + newAccrualRate - loan.accrualRate;

        /* Delete loan if fully repaid */
        if (loanBalance == 0) {
            delete loansStorage.loan[loanTermsHash];
        } else {
            /* Update loan */
            loan.accrualRate = newAccrualRate;
            loan.pendingBalance = newLoanBalance;
            loan.lastRepaymentTimestamp = uint64(block.timestamp);
        }

        /* Transfer admin fee to recipient */
        if (adminFee != 0) IUSDai(loanTerms.currencyToken).transfer(adminFeeRecipient, adminFee);
    }

    /**
     * @notice Handle loan refinanced hook
     * @param depositTimelockStorage Deposit timelock storage
     * @param loansStorage Loans storage
     * @param oldLoanTerms Old loan terms
     * @param newLoanTerms New loan terms
     * @param oldLoanTermsHash Old loan terms hash
     * @param newLoanTermsHash New loan terms hash
     * @param trancheIndex Tranche index
     * @param cashOut Cash out amount
     * @param loanRouter Loan router
     */
    function loanRefinanced(
        LoanRouterPositionManager.DepositTimelock storage depositTimelockStorage,
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouterV2.LoanTermsV2 calldata oldLoanTerms,
        ILoanRouterV2.LoanTermsV2 calldata newLoanTerms,
        bytes32 oldLoanTermsHash,
        bytes32 newLoanTermsHash,
        uint8 trancheIndex,
        uint256 cashOut,
        address loanRouter
    ) external {
        /* Validate hook context */
        _validateHookContext(oldLoanTerms, 0, loanRouter);
        _validateHookContext(newLoanTerms, 0, loanRouter);

        /* Get loans */
        LoanRouterPositionManager.Loan memory oldLoan = loansStorage.loan[oldLoanTermsHash];
        LoanRouterPositionManager.Loan storage newLoan = loansStorage.loan[newLoanTermsHash];

        /* Revert if old loan is not tracked by this position manager */
        if (oldLoan.lastRepaymentTimestamp == 0) revert LoanNotFound();

        /* Revert if new loan is already tracked by this position manager */
        if (newLoan.lastRepaymentTimestamp != 0) revert DuplicateOrigination();

        /* Revert if old and new loan currency tokens are different */
        if (oldLoanTerms.currencyToken != newLoanTerms.currencyToken) revert InvalidCurrencyToken();

        /* If deposit timelock amount exists, subtract deposited USDai amount from deposit timelock balance */
        if (depositTimelockStorage.amounts[newLoanTermsHash] != 0) {
            depositTimelockStorage.balance -= depositTimelockStorage.amounts[newLoanTermsHash];

            /* Delete deposit timelock amount for loan terms hash */
            delete depositTimelockStorage.amounts[newLoanTermsHash];
        }

        /* Get currency accrual state */
        LoanRouterPositionManager.Accrual storage currencyAccrual =
            loansStorage.interestAccruals[oldLoanTerms.currencyToken];

        /* Check if old loan is a legacy escrow loan */
        (, uint256 repaymentCount,,) = ILoanRouterV2(loanRouter).loanState(oldLoanTermsHash);
        bool isLegacyEscrowLoan = repaymentCount == 0;

        /* Bring currency accrual up to the current block */
        if (isLegacyEscrowLoan) {
            /* Remove old loan's past interest */
            _accrue(currencyAccrual, oldLoan.accrualRate, uint64(block.timestamp), oldLoan.lastRepaymentTimestamp);
        } else {
            /* Bring currency accrual up to the current block */
            _accrue(currencyAccrual, 0, 0, 0);
        }

        /* Remove old accrual rate from currency pool */
        currencyAccrual.rate -= oldLoan.accrualRate;

        /* Delete old loan entry */
        delete loansStorage.loan[oldLoanTermsHash];

        /* Update total pending loan balance by the notional delta */
        loansStorage.pendingBalances[oldLoanTerms.currencyToken] += cashOut;

        /* Compute new pending balance */
        uint256 newPendingBalance = oldLoan.pendingBalance + cashOut;

        /* Compute new accrual rate on the outstanding balance */
        uint256 newAccrualRate = newLoanTerms.trancheSpecs[trancheIndex].rate * newPendingBalance;

        /* Add new accrual rate to currency pool */
        currencyAccrual.rate += newAccrualRate;

        /* Create loan entry carrying the outstanding balance forward */
        loansStorage.loan[newLoanTermsHash] = LoanRouterPositionManager.Loan({
            accrualRate: newAccrualRate,
            pendingBalance: newPendingBalance,
            lastRepaymentTimestamp: isLegacyEscrowLoan ? uint64(block.timestamp) : oldLoan.lastRepaymentTimestamp,
            liquidationTimestamp: 0
        });
    }

    /**
     * @notice Handle loan fee paid hook
     * @param depositsStorage Deposits storage
     * @param loanTerms Loan terms
     * @param fee Fee paid
     * @param usdai USDai
     * @param loanRouter Loan router
     */
    function loanFeePaid(
        StakedUSDaiStorage.Deposits storage depositsStorage,
        ILoanRouterV2.LoanTermsV2 calldata loanTerms,
        bytes32,
        uint8,
        uint256 fee,
        address usdai,
        address loanRouter
    ) external {
        /* Validate caller is loan router */
        if (msg.sender != loanRouter) revert InvalidCaller();

        /* Validate loan currency token is USDai */
        if (loanTerms.currencyToken != usdai) revert InvalidCurrencyToken();

        /* Update deposit balance */
        depositsStorage.balance += fee;
    }

    /**
     * @notice Handle loan liquidated hook
     * @param loansStorage Loans storage
     * @param loanTerms Loan terms
     * @param loanTermsHash Loan terms hash
     * @param trancheIndex Tranche index
     * @param loanRouter Loan router
     */
    function loanLiquidated(
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouterV2.LoanTermsV2 calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex,
        address loanRouter
    ) external {
        /* Validate hook context */
        _validateHookContext(loanTerms, trancheIndex, loanRouter);

        /* Get loan */
        LoanRouterPositionManager.Loan storage loan = loansStorage.loan[loanTermsHash];

        /* Get interest accrual */
        LoanRouterPositionManager.Accrual storage accrual = loansStorage.interestAccruals[loanTerms.currencyToken];

        /* Update accrued interest and timestamp */
        _accrue(accrual, 0, 0, 0);

        /* Update unscaled rate */
        accrual.rate -= loan.accrualRate;

        /* Update liquidation timestamp */
        loan.liquidationTimestamp = uint64(block.timestamp);
    }

    /**
     * @notice Handle loan collateral liquidated hook
     * @param depositsStorage Deposits storage
     * @param loansStorage Loans storage
     * @param loanTerms Loan terms
     * @param loanTermsHash Loan terms hash
     * @param trancheIndex Tranche index
     * @param principal Principal amount
     * @param interest Interest amount
     * @param loanRouter Loan router
     * @param adminFeeRate Admin fee rate
     * @param adminFeeRecipient Admin fee recipient
     */
    function loanCollateralLiquidated(
        StakedUSDaiStorage.Deposits storage depositsStorage,
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouterV2.LoanTermsV2 calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex,
        uint256 principal,
        uint256 interest,
        address loanRouter,
        uint256 adminFeeRate,
        address adminFeeRecipient
    ) external {
        /* Validate hook context */
        _validateHookContext(loanTerms, trancheIndex, loanRouter);

        /* Get loan */
        LoanRouterPositionManager.Loan memory loan = loansStorage.loan[loanTermsHash];

        /* Compute admin fee amount */
        uint256 adminFee = interest * adminFeeRate / BASIS_POINTS_SCALE;

        /* Update deposit balance */
        depositsStorage.balance += principal + interest - adminFee;

        /* Subtract loan balance from pending balances storage */
        loansStorage.pendingBalances[loanTerms.currencyToken] -= loan.pendingBalance;

        /* Get interest accrual */
        LoanRouterPositionManager.Accrual storage accrual = loansStorage.interestAccruals[loanTerms.currencyToken];

        /* Update accrued interest and timestamp */
        _accrue(accrual, loan.accrualRate, loan.liquidationTimestamp, loan.lastRepaymentTimestamp);

        /* Delete loan */
        delete loansStorage.loan[loanTermsHash];

        /* Transfer admin fee to recipient */
        if (adminFee != 0) IUSDai(loanTerms.currencyToken).transfer(adminFeeRecipient, adminFee);
    }

    /**
     * @notice Handle escrow cancelled interest accrued hook
     * @param depositsStorage Deposits storage
     * @param usdai USDai
     * @param adminFeeRate Admin fee rate
     * @param adminFeeRecipient Admin fee recipient
     * @param interest Interest amount
     */
    function escrowCancelled(
        StakedUSDaiStorage.Deposits storage depositsStorage,
        address usdai,
        uint256 adminFeeRate,
        address adminFeeRecipient,
        uint256 interest
    ) external {
        _escrowInterestAccrued(depositsStorage, usdai, adminFeeRate, adminFeeRecipient, interest);
    }

    /**
     * @notice Handle withdrawn escrow interest accrued hook
     * @param depositsStorage Deposits storage
     * @param usdai USDai
     * @param escrowTimelock Escrow timelock
     * @param adminFeeRate Admin fee rate
     * @param adminFeeRecipient Admin fee recipient
     * @param interest Interest amount
     */
    function escrowWithdrawn(
        StakedUSDaiStorage.Deposits storage depositsStorage,
        address usdai,
        address escrowTimelock,
        uint256 adminFeeRate,
        address adminFeeRecipient,
        uint256 interest
    ) external {
        /* Validate caller is escrow timelock */
        if (msg.sender != escrowTimelock) revert InvalidCaller();

        _escrowInterestAccrued(depositsStorage, usdai, adminFeeRate, adminFeeRecipient, interest);
    }

    /**
     * @notice Deposit funds
     * @param depositsStorage Deposits storage
     * @param redemptionStateStorage Redemption state storage
     * @param depositTimelockStorage Deposit timelock storage
     * @param usdai USDai
     * @param usdaiAmount USDai amount
     * @param loanTermsHash Loan terms hash
     * @param timelock Timelock
     */
    function depositFunds(
        StakedUSDaiStorage.Deposits storage depositsStorage,
        StakedUSDaiStorage.RedemptionState storage redemptionStateStorage,
        LoanRouterPositionManager.DepositTimelock storage depositTimelockStorage,
        address usdai,
        uint256 usdaiAmount,
        bytes32 loanTermsHash,
        address timelock
    ) external {
        /* Get USDai balance */
        uint256 usdaiBalance = depositsStorage.balance - redemptionStateStorage.balance;

        /* Validate USDai balance */
        if (usdaiAmount > usdaiBalance) revert PositionManager.InsufficientBalance();

        /* Validate not already deposited */
        if (depositTimelockStorage.amounts[loanTermsHash] != 0) revert DuplicateDeposit();

        /* Update deposit balance */
        depositsStorage.balance -= usdaiAmount;

        /* Update deposit timelock balance and amounts */
        depositTimelockStorage.balance += usdaiAmount;
        depositTimelockStorage.amounts[loanTermsHash] = usdaiAmount;

        /* Approve USDai */
        IERC20(usdai).approve(timelock, usdaiAmount);
    }

    /**
     * @notice Withdraw funds
     * @param depositsStorage Deposits storage
     * @param depositTimelockStorage Deposit timelock storage
     * @param loanTermsHash Loan terms hash
     * @return USDai amount
     */
    function withdrawFunds(
        StakedUSDaiStorage.Deposits storage depositsStorage,
        LoanRouterPositionManager.DepositTimelock storage depositTimelockStorage,
        bytes32 loanTermsHash
    ) external returns (uint256) {
        /* Get USDai amount */
        uint256 usdaiAmount = depositTimelockStorage.amounts[loanTermsHash];

        /* Update deposit timelock balance */
        depositTimelockStorage.balance -= usdaiAmount;

        /* Delete deposit timelock amount for loan terms hash */
        delete depositTimelockStorage.amounts[loanTermsHash];

        /* Update deposit balance */
        depositsStorage.balance += usdaiAmount;

        /* Return USDai amount */
        return usdaiAmount;
    }
}
