// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Loan Router Position Manager Interface
 * @author USD.AI Foundation
 */
interface ILoanRouterPositionManager {
    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid timelock cancellation
     */
    error InvalidTimelockCancellation();

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Loan escrow timelock deposited
     * @param loanTermsHash Loan terms hash
     * @param usdaiAmount USDai amount
     * @param interestRate Interest rate
     */
    event LoanEscrowTimelockDeposited(bytes32 indexed loanTermsHash, uint256 usdaiAmount, uint256 interestRate);

    /**
     * @notice Loan escrow timelock withdrawn
     * @param loanTermsHash Loan terms hash
     * @param interestAmount Interest amount (in USDai)
     */
    event LoanEscrowTimelockWithdrawn(bytes32 indexed loanTermsHash, uint256 interestAmount);

    /**
     * @notice Loan escrow timelock cancelled
     * @param loanTermsHash Loan terms hash
     * @param usdaiAmount Deposited USDai amount
     * @param interestAmount Interest amount (in USDai)
     */
    event LoanEscrowTimelockCancelled(bytes32 indexed loanTermsHash, uint256 usdaiAmount, uint256 interestAmount);

    /**
     * @notice Loan repayment deposited
     * @param currencyToken Currency token
     * @param depositAmount Deposit amount
     * @param usdaiDepositAmount USDai deposit amount
     */
    event LoanRepaymentDeposited(address indexed currencyToken, uint256 depositAmount, uint256 usdaiDepositAmount);

    /**
     * @notice Admin fee withdrawn
     * @param currencyToken Currency token
     * @param adminFeeAmount Admin fee amount
     * @param usdaiDepositAmount USDai deposit amount
     */
    event AdminFeeWithdrawn(address indexed currencyToken, uint256 adminFeeAmount, uint256 usdaiDepositAmount);

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit timelock balance
     * @return Deposit timelock balance
     */
    function depositTimelockBalance() external view returns (uint256);

    /**
     * @notice Loan router balance
     * @return Repayment loan balance
     * @return Pending loan balance
     * @return Accrued loan interest balance
     */
    function loanRouterBalances() external view returns (uint256, uint256, uint256);

    /**
     * @notice Repayment balances
     * @param currencyToken Currency token
     * @return Repayment balance
     * @return Admin fee balance
     */
    function repaymentBalances(
        address currencyToken
    ) external view returns (uint256, uint256);

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit escrow loan timelock
     * @param loanTermsHash Loan terms hash
     * @param usdaiAmount USDai amount
     * @param interestRate Interest rate
     */
    function depositEscrowLoanTimelock(bytes32 loanTermsHash, uint256 usdaiAmount, uint256 interestRate) external;

    /**
     * @notice Cancel escrow loan timelock
     * @param loanTermsHash Loan terms hash
     */
    function cancelEscrowLoanTimelock(
        bytes32 loanTermsHash
    ) external;

    /**
     * @notice Deposit loan repayment
     * @param currencyToken Currency token
     * @param depositAmount Deposit amount
     * @param usdaiAmountMinimum Minimum USDai amount
     * @param data Swap data
     */
    function depositLoanRepayment(
        address currencyToken,
        uint256 depositAmount,
        uint256 usdaiAmountMinimum,
        bytes calldata data
    ) external;

    /**
     * @notice Withdraw admin fee
     * @param currencyToken Currency token
     * @param adminFeeAmount Admin fee amount
     * @param usdaiAmountMinimum Minimum USDai amount
     * @param data Swap data
     */
    function withdrawAdminFee(
        address currencyToken,
        uint256 adminFeeAmount,
        uint256 usdaiAmountMinimum,
        bytes calldata data
    ) external;
}
