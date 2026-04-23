// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IUSDai} from "../interfaces/IUSDai.sol";

import {ILoanRouterV1} from "@usdai-loan-router-contracts/interfaces/ILoanRouterV1.sol";
import {ILoanRouterV2} from "@usdai-loan-router-contracts/interfaces/ILoanRouterV2.sol";

import {LoanRouterPositionManager} from "./LoanRouterPositionManager.sol";
import {StakedUSDaiStorage} from "../StakedUSDaiStorage.sol";
import {PositionManager} from "./PositionManager.sol";

/**
 * @title Loan Router Position Manager Logic
 * @author USD.AI Foundation
 */
library LoanRouterPositionManagerLogic {
    using EnumerableSet for EnumerableSet.AddressSet;

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
     * @notice Unsupported currency
     * @param currency Currency address
     */
    error UnsupportedCurrency(address currency);

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
     * @notice Invalid amount
     */
    error InvalidAmount();

    /**
     * @notice Loan not found
     */
    error LoanNotFound();

    /**
     * @notice Duplicate deposit
     */
    error DuplicateDeposit();

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Validate hook context (V2 loan terms)
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
     * @notice Validate currency token
     * @param currencyToken Currency token address
     * @param usdai USDai
     * @param priceOracle Price oracle
     */
    function _validateCurrencyToken(address currencyToken, IUSDai usdai, IPriceOracle priceOracle) internal view {
        /* Validate currency token is either USDai, or supported by price oracle */
        if (
            currencyToken != address(usdai) && currencyToken != usdai.baseToken()
                && !priceOracle.supportedToken(currencyToken)
        ) {
            revert UnsupportedCurrency(currencyToken);
        }
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
        /* Accrue unscaled interest */
        accrual.accrued = accrual.accrued + accrual.rate * (block.timestamp - accrual.timestamp)
            - (oldAccrualRate * (timestamp - lastRepaymentTimestamp));

        /* Update timestamp */
        accrual.timestamp = uint64(block.timestamp);
    }

    /**
     * @notice Get value in USDai
     * @param usdai USDai
     * @param priceOracle Price oracle
     * @param currencyToken Currency token address
     * @param amount Amount of currency token
     * @return Value in USDai
     */
    function _value(
        IUSDai usdai,
        IPriceOracle priceOracle,
        address currencyToken,
        uint256 amount
    ) internal view returns (uint256) {
        /* If currency token is USDai, return amount */
        if (currencyToken == address(usdai)) return amount;

        /* If currency token is base token, return scaled amount */
        if (currencyToken == usdai.baseToken()) {
            return amount * (10 ** (18 - IERC20Metadata(currencyToken).decimals()));
        }

        /* Get price of currency token in terms of USDai */
        uint256 price = priceOracle.price(currencyToken);
        return Math.mulDiv(amount, price, 10 ** IERC20Metadata(currencyToken).decimals());
    }

    /**
     * @notice Handle interest accrued hook
     * @param loansStorage Loans storage
     * @param usdai USDai
     * @param token Token address
     * @param interest Interest amount
     * @param adminFeeRate Admin fee rate
     */
    function _escrowInterestAccrued(
        LoanRouterPositionManager.Loans storage loansStorage,
        IUSDai usdai,
        address token,
        uint256 interest,
        uint256 adminFeeRate
    ) internal {
        /* Validate currency token */
        if (token != address(usdai)) revert UnsupportedCurrency(token);

        /* Do nothing if interest is 0 */
        if (interest == 0) return;

        /* Register currency token */
        loansStorage.currencyTokens.add(token);

        /* Compute admin fee amount */
        uint256 adminFee = interest * adminFeeRate / BASIS_POINTS_SCALE;

        /* Update repayment balances */
        loansStorage.repaymentBalances[token].adminFee += adminFee;

        /* Update repayment balance with interest amount minus admin fee */
        loansStorage.repaymentBalances[token].repayment += interest - adminFee;
    }

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get loan router balances
     * @param loansStorage Loans storage
     * @param usdai USDai
     * @param priceOracle Price oracle
     * @return Claimable loan balance
     * @return Pending loan balance
     * @return Accrued loan interest balance
     */
    function loanRouterBalances(
        LoanRouterPositionManager.Loans storage loansStorage,
        IUSDai usdai,
        IPriceOracle priceOracle
    ) external view returns (uint256, uint256, uint256) {
        uint256 totalRepaymentBalance;
        uint256 totalPendingBalance;
        uint256 totalAccruedBalance;
        for (uint256 i; i < loansStorage.currencyTokens.length(); i++) {
            /* Get currency token */
            address currencyToken = loansStorage.currencyTokens.at(i);

            /* Get repayment balance in terms of USDai */
            totalRepaymentBalance +=
                _value(usdai, priceOracle, currencyToken, loansStorage.repaymentBalances[currencyToken].repayment);

            /* Get pending balances in terms of USDai */
            totalPendingBalance +=
                _value(usdai, priceOracle, currencyToken, loansStorage.pendingBalances[currencyToken]);

            /* Get currency token accrual */
            LoanRouterPositionManager.Accrual storage accrual = loansStorage.interestAccruals[currencyToken];

            /* Compute unscaled accrued interest */
            uint256 accrued =
                (accrual.accrued + accrual.rate * (block.timestamp - accrual.timestamp)) / FIXED_POINT_SCALE;

            /* Get accrued value in terms of USDai */
            totalAccruedBalance += _value(usdai, priceOracle, currencyToken, accrued);
        }

        /* Return loan router balance */
        return (totalRepaymentBalance, totalPendingBalance, totalAccruedBalance);
    }

    /*------------------------------------------------------------------------*/
    /* Hook Logic */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Handle deposit timelock refunded hook
     * @param loansStorage Loans storage
     * @param usdai USDai
     * @param priceOracle Price oracle
     * @param depositTimelock Deposit timelock
     * @param token Token address
     * @param amount Amount
     */
    function depositTimelockRefunded(
        LoanRouterPositionManager.Loans storage loansStorage,
        IUSDai usdai,
        IPriceOracle priceOracle,
        address depositTimelock,
        address token,
        uint256 amount
    ) external {
        /* Validate caller is deposit timelock */
        if (msg.sender != depositTimelock) revert InvalidCaller();

        /* Validate currency token */
        _validateCurrencyToken(token, usdai, priceOracle);

        /* Do nothing if amount is 0 */
        if (amount == 0) return;

        /* Register currency token */
        loansStorage.currencyTokens.add(token);

        /* Update repayment balance with refunded amount */
        loansStorage.repaymentBalances[token].repayment += amount;
    }

    /**
     * @notice Handle loan originated hook (V2)
     * @param depositTimelockStorage Deposit timelock storage
     * @param loansStorage Loans storage
     * @param loanTerms Loan terms
     * @param loanTermsHash Loan terms hash
     * @param trancheIndex Tranche index
     * @param usdai USDai
     * @param priceOracle Price oracle
     * @param loanRouter Loan router
     */
    function loanOriginated(
        LoanRouterPositionManager.DepositTimelock storage depositTimelockStorage,
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouterV2.LoanTermsV2 calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex,
        IUSDai usdai,
        IPriceOracle priceOracle,
        address loanRouter
    ) external {
        /* Validate hook context */
        _validateHookContext(loanTerms, trancheIndex, loanRouter);

        /* Validate currency token is either USDai, or supported by price oracle */
        _validateCurrencyToken(loanTerms.currencyToken, usdai, priceOracle);

        /* Subtract deposited USDai amount from deposit timelock balance */
        depositTimelockStorage.balance -= depositTimelockStorage.amounts[loanTermsHash];

        /* Delete deposit timelock amount for loan terms hash */
        delete depositTimelockStorage.amounts[loanTermsHash];

        /* Compute scaled accrual rate */
        uint256 accrualRate = loanTerms.trancheSpecs[trancheIndex].rate * loanTerms.trancheSpecs[trancheIndex].amount;

        /* Register currency token */
        loansStorage.currencyTokens.add(loanTerms.currencyToken);

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
     * @notice Handle loan repayment hook (V2)
     * @param loansStorage Loans storage
     * @param loanTerms Loan terms
     * @param loanTermsHash Loan terms hash
     * @param trancheIndex Tranche index
     * @param loanBalance Loan balance
     * @param principal Principal amount
     * @param interest Interest amount
     * @param adminFeeRate Admin fee rate
     * @param loanRouter Loan router
     */
    function loanRepayment(
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouterV2.LoanTermsV2 calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex,
        uint256 loanBalance,
        uint256 principal,
        uint256 interest,
        uint256 adminFeeRate,
        address loanRouter
    ) external {
        /* Validate hook context */
        _validateHookContext(loanTerms, trancheIndex, loanRouter);

        /* Get loan */
        LoanRouterPositionManager.Loan storage loan = loansStorage.loan[loanTermsHash];

        /* Compute admin fee amount */
        uint256 adminFee = interest * adminFeeRate / BASIS_POINTS_SCALE;

        /* Adjust for rounding losses and rounding gains */
        principal = loanBalance == 0 ? loan.pendingBalance : Math.min(loan.pendingBalance, principal);

        /* Update repayment balances */
        loansStorage.repaymentBalances[loanTerms.currencyToken].repayment += principal + interest - adminFee;
        loansStorage.repaymentBalances[loanTerms.currencyToken].adminFee += adminFee;

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
    }

    /**
     * @notice Handle loan fee paid hook (V2)
     * @param loansStorage Loans storage
     * @param loanTerms Loan terms
     * @param fee Fee paid
     */
    function loanFeePaid(
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouterV2.LoanTermsV2 calldata loanTerms,
        bytes32,
        uint8,
        uint256 fee,
        address loanRouter
    ) external {
        /* Validate caller is loan router */
        if (msg.sender != loanRouter) revert InvalidCaller();

        /* Update repayment balances */
        loansStorage.repaymentBalances[loanTerms.currencyToken].repayment += fee;
    }

    /**
     * @notice Handle loan liquidated hook (V2)
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
     * @notice Handle loan collateral liquidated hook (V2)
     * @param loansStorage Loans storage
     * @param loanTerms Loan terms
     * @param loanTermsHash Loan terms hash
     * @param trancheIndex Tranche index
     * @param principal Principal amount
     * @param interest Interest amount
     * @param adminFeeRate Admin fee rate
     * @param loanRouter Loan router
     */
    function loanCollateralLiquidated(
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouterV2.LoanTermsV2 calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex,
        uint256 principal,
        uint256 interest,
        uint256 adminFeeRate,
        address loanRouter
    ) external {
        /* Validate hook context */
        _validateHookContext(loanTerms, trancheIndex, loanRouter);

        /* Get loan */
        LoanRouterPositionManager.Loan memory loan = loansStorage.loan[loanTermsHash];

        /* Compute admin fee amount */
        uint256 adminFee = interest * adminFeeRate / BASIS_POINTS_SCALE;

        /* Update repayment balances */
        loansStorage.repaymentBalances[loanTerms.currencyToken].repayment += principal + interest - adminFee;
        loansStorage.repaymentBalances[loanTerms.currencyToken].adminFee += adminFee;

        /* Subtract loan balance from pending balances storage */
        loansStorage.pendingBalances[loanTerms.currencyToken] -= loan.pendingBalance;

        /* Get interest accrual */
        LoanRouterPositionManager.Accrual storage accrual = loansStorage.interestAccruals[loanTerms.currencyToken];

        /* Update accrued interest and timestamp */
        _accrue(accrual, loan.accrualRate, loan.liquidationTimestamp, loan.lastRepaymentTimestamp);

        /* Delete loan */
        delete loansStorage.loan[loanTermsHash];
    }

    /**
     * @notice Handle escrow cancelled interest accrued hook
     * @param loansStorage Loans storage
     * @param usdai USDai
     * @param interest Interest amount
     * @param adminFeeRate Admin fee rate
     */
    function escrowCancelled(
        LoanRouterPositionManager.Loans storage loansStorage,
        IUSDai usdai,
        uint256 interest,
        uint256 adminFeeRate
    ) external {
        _escrowInterestAccrued(loansStorage, usdai, address(usdai), interest, adminFeeRate);
    }

    /**
     * @notice Handle withdrawn escrow interest accrued hook
     * @param loansStorage Loans storage
     * @param usdai USDai
     * @param escrowTimelock Escrow timelock
     * @param token Token address
     * @param interest Interest amount
     * @param adminFeeRate Admin fee rate
     */
    function escrowWithdrawn(
        LoanRouterPositionManager.Loans storage loansStorage,
        IUSDai usdai,
        address escrowTimelock,
        address token,
        uint256 interest,
        uint256 adminFeeRate
    ) external {
        /* Validate caller is escrow timelock */
        if (msg.sender != escrowTimelock) revert InvalidCaller();

        _escrowInterestAccrued(loansStorage, usdai, token, interest, adminFeeRate);
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

        /* Approve USDai */
        IERC20(usdai).approve(timelock, usdaiAmount);

        /* Update deposits balance */
        depositsStorage.balance -= usdaiAmount;

        /* Update deposit timelock balance and amounts */
        depositTimelockStorage.balance += usdaiAmount;
        depositTimelockStorage.amounts[loanTermsHash] = usdaiAmount;
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

        /* Update deposits balance */
        depositsStorage.balance += usdaiAmount;

        /* Return USDai amount */
        return usdaiAmount;
    }

    /**
     * @notice Handle loan migrated hook
     * @param loansStorage Loans storage
     * @param loanTermsV1 V1 loan terms
     * @param loanTermsHashV1 V1 loan terms hash
     * @param loanTermsV2 V2 loan terms
     * @param loanTermsHashV2 V2 loan terms hash
     * @param originationTimestampV2 V2 origination timestamp
     * @param usdai USDai
     * @param priceOracle Price oracle
     * @param loanRouter Loan router
     */
    function loanMigrated(
        LoanRouterPositionManager.Loans storage loansStorage,
        ILoanRouterV1.LoanTerms calldata loanTermsV1,
        bytes32 loanTermsHashV1,
        ILoanRouterV2.LoanTermsV2 calldata loanTermsV2,
        bytes32 loanTermsHashV2,
        uint64 originationTimestampV2,
        IUSDai usdai,
        IPriceOracle priceOracle,
        address loanRouter
    ) external {
        /* Validate caller is V2 loan router and LRPM is the tranche 0 lender */
        _validateHookContext(loanTermsV2, 0, loanRouter);

        /* Validate V2 currency token */
        _validateCurrencyToken(loanTermsV2.currencyToken, usdai, priceOracle);

        /* Load V1 loan into memory */
        LoanRouterPositionManager.Loan memory loanV1 = loansStorage.loan[loanTermsHashV1];

        /* Revert if V1 loan is not tracked by this position manager */
        if (loanV1.lastRepaymentTimestamp == 0) revert LoanNotFound();

        /* Revert if V2 hash is already in use */
        if (loansStorage.loan[loanTermsHashV2].lastRepaymentTimestamp != 0) revert DuplicateOrigination();

        /* Get V1 currency accrual state */
        LoanRouterPositionManager.Accrual storage currencyAccrualV1 =
            loansStorage.interestAccruals[loanTermsV1.currencyToken];

        /* Remove V1 loan's past interest from V1 currency accrual pool */
        _accrue(currencyAccrualV1, loanV1.accrualRate, uint64(block.timestamp), loanV1.lastRepaymentTimestamp);

        /* Remove V1 accrual rate from V1 currency pool */
        currencyAccrualV1.rate -= loanV1.accrualRate;

        /* Remove V1 pending balance from V1 currency pool */
        loansStorage.pendingBalances[loanTermsV1.currencyToken] -= loanV1.pendingBalance;

        /* Delete V1 loan entry */
        delete loansStorage.loan[loanTermsHashV1];

        /* Compute V2 accrual rate */
        uint256 accrualRateV2 = loanTermsV2.trancheSpecs[0].rate * loanTermsV2.trancheSpecs[0].amount;

        /* Get V2 currency accrual state */
        LoanRouterPositionManager.Accrual storage currencyAccrualV2 =
            loansStorage.interestAccruals[loanTermsV2.currencyToken];

        /* Bring V2 currency accrual up to the current block */
        _accrue(currencyAccrualV2, 0, 0, 0);

        /* Get origination timestamp */
        uint64 lastRepaymentTimestamp =
            originationTimestampV2 == 0 ? loanV1.lastRepaymentTimestamp : originationTimestampV2;

        /* Inject normalized V1 past interest into V2 accrual pool */
        currencyAccrualV2.accrued += accrualRateV2 * (block.timestamp - lastRepaymentTimestamp);

        /* Add V2 accrual rate to V2 currency pool */
        currencyAccrualV2.rate += accrualRateV2;

        /* Register V2 currency token */
        loansStorage.currencyTokens.add(loanTermsV2.currencyToken);

        /* Add V2 pending balance to V2 currency pool */
        loansStorage.pendingBalances[loanTermsV2.currencyToken] += loanTermsV2.trancheSpecs[0].amount;

        /* Create V2 loan entry with migration timestamp as the start of interest accrual */
        loansStorage.loan[loanTermsHashV2] = LoanRouterPositionManager.Loan({
            accrualRate: accrualRateV2,
            pendingBalance: loanTermsV2.trancheSpecs[0].amount,
            lastRepaymentTimestamp: lastRepaymentTimestamp,
            liquidationTimestamp: 0
        });
    }

    /**
     * @notice Deposit loan repayment
     * @param depositsStorage Deposits storage
     * @param loansStorage Loans storage
     * @param usdai USDai
     * @param currencyToken Currency token address
     * @param depositAmount Deposit amount
     * @param usdaiAmountMinimum Minimum USDai amount
     * @param data Swap data
     * @return USDai deposit amount
     */
    function depositLoanRepayment(
        StakedUSDaiStorage.Deposits storage depositsStorage,
        LoanRouterPositionManager.Loans storage loansStorage,
        IUSDai usdai,
        address currencyToken,
        uint256 depositAmount,
        uint256 usdaiAmountMinimum,
        bytes calldata data
    ) external returns (uint256) {
        /* Validate repayment balance */
        if (depositAmount > loansStorage.repaymentBalances[currencyToken].repayment) {
            revert PositionManager.InsufficientBalance();
        }

        /* Update repayment balances */
        loansStorage.repaymentBalances[currencyToken].repayment -= depositAmount;

        /* Get USDai deposit amount */
        uint256 usdaiDepositAmount;
        if (currencyToken == address(usdai)) {
            usdaiDepositAmount = depositAmount;
        } else {
            /* Approve currency token */
            IERC20(currencyToken).forceApprove(address(usdai), depositAmount);

            /* Swap currency token to USDai */
            usdaiDepositAmount = usdai.deposit(currencyToken, depositAmount, usdaiAmountMinimum, address(this), data);
        }

        /* Update deposits balance */
        depositsStorage.balance += usdaiDepositAmount;

        /* Return USDai deposit amount */
        return usdaiDepositAmount;
    }
}
