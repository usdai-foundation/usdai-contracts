// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IEscrowTimelockHooks} from "@usdai-loan-router-contracts/interfaces/IEscrowTimelockHooks.sol";

/**
 * @title Mock Escrow Timelock
 * @author USD.AI Foundation
 * @dev Minimum surface for LRPM tests: pull funds on deposit, refund on cancel, fire
 *      onEscrowWithdrawn via direct ERC-165-gated call. `accrued()` is a test knob.
 */
contract MockEscrowTimelock {
    using SafeERC20 for IERC20;

    struct Deposit {
        address depositor;
        uint256 amount;
        uint256 interestRate;
    }

    IERC20 internal _depositToken;

    uint256 internal _accrued;
    uint256 internal _interestOnCancel;

    mapping(address => mapping(bytes32 => Deposit)) internal _deposits;

    function setDepositToken(
        address depositToken_
    ) external {
        _depositToken = IERC20(depositToken_);
    }

    function accrued() external view returns (uint256) {
        return _accrued;
    }

    function setAccrued(
        uint256 value
    ) external {
        _accrued = value;
    }

    function setInterestOnCancel(
        uint256 value
    ) external {
        _interestOnCancel = value;
    }

    function deposit(address target, bytes32 context, address, uint256 depositAmount, uint256 interestRate) external {
        _depositToken.safeTransferFrom(msg.sender, address(this), depositAmount);
        _deposits[target][context] = Deposit({depositor: msg.sender, amount: depositAmount, interestRate: interestRate});
    }

    function cancel(address target, bytes32 context) external returns (uint256, uint256) {
        Deposit memory depositEntry = _deposits[target][context];
        delete _deposits[target][context];
        if (depositEntry.amount > 0) _depositToken.safeTransfer(depositEntry.depositor, depositEntry.amount);
        return (depositEntry.amount, _interestOnCancel);
    }

    /**
     * @notice Test helper — invoke the target's onEscrowWithdrawn hook directly.
     * @dev Direct ERC-165-gated call (mirrors real EscrowTimelock).
     */
    function triggerWithdrawn(
        address target,
        bytes32 context,
        address token,
        uint256 amount,
        uint256 interest
    ) external {
        if (target.code.length != 0 && IERC165(target).supportsInterface(type(IEscrowTimelockHooks).interfaceId)) {
            IEscrowTimelockHooks(target).onEscrowWithdrawn(msg.sender, context, token, amount, interest);
        }
    }
}
