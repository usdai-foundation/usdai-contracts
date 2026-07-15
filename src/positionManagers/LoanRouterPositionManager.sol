// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {PositionManager} from "./PositionManager.sol";
import {StakedUSDaiStorage} from "../StakedUSDaiStorage.sol";

import {ILoanRouterPositionManager} from "../interfaces/ILoanRouterPositionManager.sol";

import {IEscrowTimelock} from "@usdai-loan-router-contracts/interfaces/IEscrowTimelock.sol";
import {IEscrowTimelockHooks} from "@usdai-loan-router-contracts/interfaces/IEscrowTimelockHooks.sol";
import {IDepositTimelock} from "@usdai-loan-router-contracts/interfaces/IDepositTimelock.sol";
import {IDepositTimelockHooks} from "@usdai-loan-router-contracts/interfaces/IDepositTimelockHooks.sol";
import {ILoanRouterV2} from "@usdai-loan-router-contracts/interfaces/ILoanRouterV2.sol";
import {ILoanRouterV2Hooks} from "@usdai-loan-router-contracts/interfaces/ILoanRouterV2Hooks.sol";

import {LoanRouterPositionManagerLogic} from "./LoanRouterPositionManagerLogic.sol";

/**
 * @title Loan Router Position Manager
 * @author USD.AI Foundation
 */
abstract contract LoanRouterPositionManager is
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PositionManager,
    StakedUSDaiStorage,
    ILoanRouterPositionManager,
    IEscrowTimelockHooks,
    IDepositTimelockHooks,
    ILoanRouterV2Hooks
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit timelock storage location
     * @dev keccak256(abi.encode(uint256(keccak256("stakedUSDai.depositTimelock")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant DEPOSIT_TIMELOCK_STORAGE_LOCATION =
        0x7fab4664d57f16410d3bcb5fb74c23268a2f6f0b7b67ca2a4a44fc24e93b6300;

    /**
     * @notice Loans storage location
     * @dev keccak256(abi.encode(uint256(keccak256("stakedUSDai.loans")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant LOANS_STORAGE_LOCATION = 0xeedf9bea8709bd441d5da250df505e80fc82bec74f9f1df28edf19fa1ed4bd00;

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Repayment
     * @param repayment Repayment amount
     * @param adminFee Admin fee amount
     */
    struct Repayment {
        uint256 repayment;
        uint256 adminFee;
    }

    /**
     * @notice Accrual state
     * @param accrued Accrued interest
     * @param rate Accrual rate
     * @param timestamp Last accrual timestamp
     */
    struct Accrual {
        uint256 accrued;
        uint256 rate;
        uint64 timestamp;
    }

    /**
     * @notice Loan
     * @param accrualRate Accrual rate
     * @param pendingBalance Pending balance
     * @param lastRepaymentTimestamp Last repayment timestamp
     * @param liquidationTimestamp Liquidation timestamp
     */
    struct Loan {
        uint256 accrualRate;
        uint256 pendingBalance;
        uint64 lastRepaymentTimestamp;
        uint64 liquidationTimestamp;
    }

    /**
     * @custom:storage-location erc7201:stakedUSDai.loans
     * @param currencyTokens Currency tokens set (deprecated)
     * @param repaymentBalances Repayment balances per currency token (deprecated)
     * @param pendingBalances Pending loan balances per currency token
     * @param interestAccruals Interest accruals per currency token
     * @param loan Loan state by loan terms hash
     */
    struct Loans {
        EnumerableSet.AddressSet currencyTokens;
        mapping(address => Repayment) repaymentBalances;
        mapping(address => uint256) pendingBalances;
        mapping(address => Accrual) interestAccruals;
        mapping(bytes32 => Loan) loan;
    }

    /**
     * @custom:storage-location erc7201:stakedUSDai.depositTimelock
     * @param balance Deposit timelock USDai balance
     * @param amounts Deposit amount for each loan terms hash
     */
    struct DepositTimelock {
        uint256 balance;
        mapping(bytes32 => uint256) amounts;
    }

    /*------------------------------------------------------------------------*/
    /* Immutable state */
    /*------------------------------------------------------------------------*/

    /**
     * @notice V2 loan router
     */
    address internal immutable _loanRouterV2;

    /**
     * @notice Escrow timelock
     */
    address internal immutable _escrowTimelock;

    /**
     * @notice Deposit timelock
     */
    address internal immutable _depositTimelock;

    /**
     * @notice Admin fee rate
     */
    uint256 internal immutable _loanRouterAdminFeeRate;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Constructor
     * @param loanRouterV2_ V2 loan router
     * @param loanRouterAdminFeeRate_ Loan router admin fee rate
     */
    constructor(address loanRouterV2_, uint256 loanRouterAdminFeeRate_) {
        _loanRouterV2 = loanRouterV2_;

        _escrowTimelock = ILoanRouterV2(loanRouterV2_).escrowTimelock();
        _depositTimelock = ILoanRouterV2(loanRouterV2_).depositTimelock();
        _loanRouterAdminFeeRate = loanRouterAdminFeeRate_;
    }

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function depositTimelockBalance() public view returns (uint256) {
        /* Return USDai balance in deposit timelock */
        return _getDepositTimelockStorage().balance;
    }

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function loanRouterBalances() public view returns (uint256, uint256) {
        return LoanRouterPositionManagerLogic.loanRouterBalances(_getLoansStorage(), address(_usdai));
    }

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function accrualRate() external view returns (uint256) {
        return _getLoansStorage().interestAccruals[address(_usdai)].rate;
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get reference to deposit timelock storage
     *
     * @return $ Reference to deposit timelock storage
     */
    function _getDepositTimelockStorage() internal pure returns (DepositTimelock storage $) {
        assembly {
            $.slot := DEPOSIT_TIMELOCK_STORAGE_LOCATION
        }
    }

    /**
     * @notice Get reference to loans storage
     *
     * @return $ Reference to loans storage
     */
    function _getLoansStorage() internal pure returns (Loans storage $) {
        assembly {
            $.slot := LOANS_STORAGE_LOCATION
        }
    }

    /**
     * @inheritdoc PositionManager
     */
    function _assets(
        PositionManager.ValuationType valuationType
    ) internal view virtual override returns (uint256) {
        (uint256 pendingLoanBalance, uint256 accruedLoanInterestBalance) = loanRouterBalances();

        /* Get accrued escrow interest balance */
        uint256 accruedEscrowInterestBalance = IEscrowTimelock(_escrowTimelock).accrued();

        /* Return total assets in terms of USDai */
        return depositTimelockBalance() + pendingLoanBalance
            + (
                (valuationType == PositionManager.ValuationType.OPTIMISTIC)
                    ? (accruedLoanInterestBalance - (accruedLoanInterestBalance * _loanRouterAdminFeeRate / BASIS_POINTS_SCALE))
                        + (
                            accruedEscrowInterestBalance
                                - (accruedEscrowInterestBalance * _loanRouterAdminFeeRate / BASIS_POINTS_SCALE)
                        )
                    : 0
            );
    }

    /*------------------------------------------------------------------------*/
    /* ERC721 Receiver Hooks */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Handle receipt of an NFT
     * @dev Required to receive ERC721 tokens (collateral from loans)
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /*------------------------------------------------------------------------*/
    /* Escrow Timelock Hooks */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IEscrowTimelockHooks
     */
    function onEscrowWithdrawn(
        address,
        bytes32 loanTermsHash,
        address,
        uint256,
        uint256 interestAmount
    ) external nonReentrant {
        /* Handle interest accrued */
        LoanRouterPositionManagerLogic.escrowWithdrawn(
            _getDepositsStorage(),
            address(_usdai),
            _escrowTimelock,
            _loanRouterAdminFeeRate,
            _adminFeeRecipient,
            interestAmount
        );

        /* Emit LoanEscrowTimelockWithdrawn */
        emit LoanEscrowTimelockWithdrawn(loanTermsHash, interestAmount);
    }

    /*------------------------------------------------------------------------*/
    /* Deposit Timelock Hooks */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IDepositTimelockHooks
     */
    function onDepositWithdrawn(
        address,
        bytes32,
        address,
        uint256,
        uint256,
        uint256 refundDepositAmount
    ) external nonReentrant {
        /* Handle deposit timelock withdrawn */
        LoanRouterPositionManagerLogic.depositWithdrawn(_getDepositsStorage(), _depositTimelock, refundDepositAmount);
    }

    /*------------------------------------------------------------------------*/
    /* Loan Router Hooks (V2) */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ILoanRouterV2Hooks
     */
    function onLoanOriginated(
        ILoanRouterV2.LoanTermsV2 calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex
    ) external nonReentrant {
        LoanRouterPositionManagerLogic.loanOriginated(
            _getDepositTimelockStorage(),
            _getLoansStorage(),
            loanTerms,
            loanTermsHash,
            trancheIndex,
            address(_usdai),
            _loanRouterV2
        );
    }

    /**
     * @inheritdoc ILoanRouterV2Hooks
     */
    function onLoanRepayment(
        ILoanRouterV2.LoanTermsV2 calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex,
        uint256 loanBalance,
        uint256 principal,
        uint256 interest,
        uint256 prepayment
    ) external nonReentrant {
        LoanRouterPositionManagerLogic.loanRepayment(
            _getDepositsStorage(),
            _getLoansStorage(),
            loanTerms,
            loanTermsHash,
            trancheIndex,
            loanBalance,
            principal + prepayment,
            interest,
            _loanRouterV2,
            _loanRouterAdminFeeRate,
            _adminFeeRecipient
        );
    }

    /**
     * @inheritdoc ILoanRouterV2Hooks
     */
    function onLoanFeePaid(
        ILoanRouterV2.LoanTermsV2 calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 feeSpecIndex,
        uint256 fee
    ) external nonReentrant {
        LoanRouterPositionManagerLogic.loanFeePaid(
            _getDepositsStorage(), loanTerms, loanTermsHash, feeSpecIndex, fee, address(_usdai), _loanRouterV2
        );
    }

    /**
     * @inheritdoc ILoanRouterV2Hooks
     */
    function onLoanLiquidated(
        ILoanRouterV2.LoanTermsV2 calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex
    ) external nonReentrant {
        LoanRouterPositionManagerLogic.loanLiquidated(
            _getLoansStorage(), loanTerms, loanTermsHash, trancheIndex, _loanRouterV2
        );
    }

    /**
     * @inheritdoc ILoanRouterV2Hooks
     */
    function onLoanCollateralLiquidated(
        ILoanRouterV2.LoanTermsV2 calldata loanTerms,
        bytes32 loanTermsHash,
        uint8 trancheIndex,
        uint256 principal,
        uint256 interest
    ) external nonReentrant {
        LoanRouterPositionManagerLogic.loanCollateralLiquidated(
            _getDepositsStorage(),
            _getLoansStorage(),
            loanTerms,
            loanTermsHash,
            trancheIndex,
            principal,
            interest,
            _loanRouterV2,
            _loanRouterAdminFeeRate,
            _adminFeeRecipient
        );
    }

    /**
     * @inheritdoc ILoanRouterV2Hooks
     */
    function onLoanRefinanced(
        ILoanRouterV2.LoanTermsV2 calldata oldLoanTerms,
        ILoanRouterV2.LoanTermsV2 calldata newLoanTerms,
        bytes32 oldLoanTermsHash,
        bytes32 newLoanTermsHash
    ) external nonReentrant {
        LoanRouterPositionManagerLogic.loanRefinanced(
            _getLoansStorage(), oldLoanTerms, newLoanTerms, oldLoanTermsHash, newLoanTermsHash, _loanRouterV2
        );
    }

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function depositLoanEscrowTimelock(
        bytes32 loanTermsHash,
        uint256 usdaiAmount,
        uint256 interestRate
    ) external onlyRole(STRATEGY_ADMIN_ROLE) nonReentrant {
        /* Handle deposit accounting and approval */
        LoanRouterPositionManagerLogic.depositFunds(
            _getDepositsStorage(),
            _getRedemptionStateStorage(),
            _getDepositTimelockStorage(),
            address(_usdai),
            usdaiAmount,
            loanTermsHash,
            _escrowTimelock
        );

        /* Deposit funds against the V2 router */
        IEscrowTimelock(_escrowTimelock).deposit(
            _loanRouterV2, loanTermsHash, address(_usdai), usdaiAmount, interestRate
        );

        /* Emit LoanEscrowTimelockDeposited */
        emit LoanEscrowTimelockDeposited(loanTermsHash, usdaiAmount, interestRate);
    }

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function depositLoanDepositTimelock(
        bytes32 loanTermsHash,
        uint256 usdaiAmount,
        uint64 expiration
    ) external onlyRole(STRATEGY_ADMIN_ROLE) nonReentrant {
        /* Handle deposit accounting and approval */
        LoanRouterPositionManagerLogic.depositFunds(
            _getDepositsStorage(),
            _getRedemptionStateStorage(),
            _getDepositTimelockStorage(),
            address(_usdai),
            usdaiAmount,
            loanTermsHash,
            _depositTimelock
        );

        /* Deposit funds against the V2 router */
        IDepositTimelock(_depositTimelock).deposit(
            _loanRouterV2, loanTermsHash, address(_usdai), usdaiAmount, expiration
        );

        /* Emit LoanDepositTimelockDeposited */
        emit LoanDepositTimelockDeposited(loanTermsHash, usdaiAmount, expiration);
    }

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function cancelLoanEscrowTimelock(
        bytes32 loanTermsHash
    ) external onlyRole(STRATEGY_ADMIN_ROLE) nonReentrant {
        uint256 usdaiAmount = LoanRouterPositionManagerLogic.withdrawFunds(
            _getDepositsStorage(), _getDepositTimelockStorage(), loanTermsHash
        );

        /* Cancel deposit */
        (uint256 depositAmount, uint256 interestAmount) =
            IEscrowTimelock(_escrowTimelock).cancel(_loanRouterV2, loanTermsHash);
        if (depositAmount != usdaiAmount) revert InvalidTimelockCancellation();

        /* Handle interest accrued */
        LoanRouterPositionManagerLogic.escrowCancelled(
            _getDepositsStorage(), address(_usdai), _loanRouterAdminFeeRate, _adminFeeRecipient, interestAmount
        );

        /* Emit LoanEscrowTimelockCancelled */
        emit LoanEscrowTimelockCancelled(loanTermsHash, usdaiAmount, interestAmount);
    }

    /**
     * @inheritdoc ILoanRouterPositionManager
     */
    function cancelLoanDepositTimelock(
        bytes32 loanTermsHash
    ) external onlyRole(STRATEGY_ADMIN_ROLE) nonReentrant {
        uint256 usdaiAmount = LoanRouterPositionManagerLogic.withdrawFunds(
            _getDepositsStorage(), _getDepositTimelockStorage(), loanTermsHash
        );

        /* Cancel deposit */
        if (IDepositTimelock(_depositTimelock).cancel(_loanRouterV2, loanTermsHash) != usdaiAmount) {
            revert InvalidTimelockCancellation();
        }

        /* Emit LoanDepositTimelockCancelled */
        emit LoanDepositTimelockCancelled(loanTermsHash, usdaiAmount);
    }
}
