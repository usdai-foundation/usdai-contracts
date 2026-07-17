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
     * @notice Loan timelock deposited
     * @param loanTermsHash Loan terms hash
     * @param usdaiAmount USDai amount
     * @param expiration Expiration timestamp
     */
    event LoanDepositTimelockDeposited(bytes32 indexed loanTermsHash, uint256 usdaiAmount, uint64 expiration);

    /**
     * @notice Loan timelock cancelled
     * @param loanTermsHash Loan terms hash
     * @param usdaiAmount USDai amount
     */
    event LoanDepositTimelockCancelled(bytes32 indexed loanTermsHash, uint256 usdaiAmount);

    /**
     * @notice Admin fee withdrawn
     * @param adminFeeAmount Admin fee amount
     */
    event AdminFeeWithdrawn(uint256 adminFeeAmount);

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit timelock balance
     * @return Deposit timelock balance
     */
    function depositTimelockBalance() external view returns (uint256);

    /**
     * @notice Loan router balances
     * @return Pending loan balance
     * @return Accrued loan interest balance
     */
    function loanRouterBalances() external view returns (uint256, uint256);

    /**
     * @notice Repayment balances
     * @return Repayment balance
     * @return Admin fee balance
     */
    function repaymentBalances() external view returns (uint256, uint256);

    /**
     * @notice Accrual rate
     * @return Accrual rate
     */
    function accrualRate() external view returns (uint256);

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit escrow loan timelock
     * @param loanTermsHash Loan terms hash
     * @param usdaiAmount USDai amount
     * @param interestRate Interest rate
     */
    function depositLoanEscrowTimelock(bytes32 loanTermsHash, uint256 usdaiAmount, uint256 interestRate) external;

    /**
     * @notice Cancel escrow loan timelock
     * @param loanTermsHash Loan terms hash
     */
    function cancelLoanEscrowTimelock(
        bytes32 loanTermsHash
    ) external;

    /**
     * @notice Deposit loan deposit timelock
     * @param loanTermsHash Loan terms hash
     * @param usdaiAmount USDai amount
     * @param expiration Expiration timestamp
     */
    function depositLoanDepositTimelock(bytes32 loanTermsHash, uint256 usdaiAmount, uint64 expiration) external;

    /**
     * @notice Cancel loan deposit timelock
     * @param loanTermsHash Loan terms hash
     */
    function cancelLoanDepositTimelock(
        bytes32 loanTermsHash
    ) external;

    /**
     * @notice Withdraw admin fee
     * @param adminFeeAmount Admin fee amount
     */
    function withdrawAdminFee(
        uint256 adminFeeAmount
    ) external;
}
