// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IEscrowTimelock} from "@usdai-loan-router-contracts/interfaces/IEscrowTimelock.sol";

import {ILoanRouterPositionManager} from "src/interfaces/ILoanRouterPositionManager.sol";
import {LoanRouterPositionManagerLogic} from "src/positionManagers/LoanRouterPositionManagerLogic.sol";
import {PositionManager} from "src/positionManagers/PositionManager.sol";

import {BaseLoanRouterTest} from "./Base.t.sol";

contract EscrowTimelockTest is BaseLoanRouterTest {
    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    bytes32 internal constant LOAN_HASH = keccak256("escrow-test-loan");
    uint256 internal constant DEPOSIT_AMOUNT = 100_000 ether;

    /*------------------------------------------------------------------------*/
    /* Helpers */
    /*------------------------------------------------------------------------*/

    function _depositEscrow() internal {
        vm.prank(users.manager);
        stakedUsdai.depositLoanEscrowTimelock(LOAN_HASH, DEPOSIT_AMOUNT, RATE_10_PCT);
    }

    function _expectedInterest(
        uint256 duration
    ) internal pure returns (uint256) {
        return DEPOSIT_AMOUNT * RATE_10_PCT * duration / FIXED_POINT_SCALE;
    }

    function _expectedNetInterest(
        uint256 duration
    ) internal pure returns (uint256) {
        uint256 interest = _expectedInterest(duration);
        return interest - interest * LOAN_ROUTER_ADMIN_FEE_RATE / BASIS_POINTS_SCALE;
    }

    /*------------------------------------------------------------------------*/
    /* Wiring */
    /*------------------------------------------------------------------------*/

    function test__EscrowTimelockWired() public view {
        assertTrue(address(escrowTimelock) != address(0), "escrowTimelock not deployed");
        assertEq(escrowTimelock.accrued(), 0, "initial accrued not 0");
    }

    /*------------------------------------------------------------------------*/
    /* depositLoanEscrowTimelock */
    /*------------------------------------------------------------------------*/

    function test__DepositEscrowLoanTimelock_IncreasesDepositTimelockBalance() public {
        _depositEscrow();
        assertEq(stakedUsdai.depositTimelockBalance(), DEPOSIT_AMOUNT);
    }

    function test__DepositEscrowLoanTimelock_TransfersUsdaiToEscrowAdmin() public {
        uint256 adminBalanceBefore = IERC20(address(usdai)).balanceOf(users.admin);
        _depositEscrow();
        assertEq(IERC20(address(usdai)).balanceOf(users.admin), adminBalanceBefore + DEPOSIT_AMOUNT);
    }

    function test__DepositEscrowLoanTimelock_AccruedInterestGrowsOverTime() public {
        _depositEscrow();
        assertEq(escrowTimelock.accrued(), 0, "accrued non-zero immediately after deposit");
        warp(30 days);
        assertEq(escrowTimelock.accrued(), _expectedInterest(30 days));
    }

    function test__DepositEscrowLoanTimelock_EmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(stakedUsdai));
        emit ILoanRouterPositionManager.LoanEscrowTimelockDeposited(LOAN_HASH, DEPOSIT_AMOUNT, RATE_10_PCT);
        vm.prank(users.manager);
        stakedUsdai.depositLoanEscrowTimelock(LOAN_HASH, DEPOSIT_AMOUNT, RATE_10_PCT);
    }

    function test__DepositEscrowLoanTimelock_RevertWhen_InsufficientBalance() public {
        vm.expectRevert(PositionManager.InsufficientBalance.selector);
        vm.prank(users.manager);
        stakedUsdai.depositLoanEscrowTimelock(LOAN_HASH, 100_000_000 ether, RATE_10_PCT);
    }

    function test__DepositEscrowLoanTimelock_RevertWhen_NotStrategyAdmin() public {
        vm.expectRevert();
        vm.prank(users.normalUser1);
        stakedUsdai.depositLoanEscrowTimelock(LOAN_HASH, DEPOSIT_AMOUNT, RATE_10_PCT);
    }

    function test__DepositEscrowLoanTimelock_RevertWhen_DuplicateDeposit() public {
        _depositEscrow();
        vm.expectRevert(LoanRouterPositionManagerLogic.DuplicateDeposit.selector);
        vm.prank(users.manager);
        stakedUsdai.depositLoanEscrowTimelock(LOAN_HASH, DEPOSIT_AMOUNT, RATE_10_PCT);
    }

    /*------------------------------------------------------------------------*/
    /* cancelLoanEscrowTimelock */
    /*------------------------------------------------------------------------*/

    function test__CancelEscrowLoanTimelock_ZeroesDepositTimelockBalance() public {
        _depositEscrow();
        warp(30 days);
        vm.prank(users.manager);
        stakedUsdai.cancelLoanEscrowTimelock(LOAN_HASH);
        assertEq(stakedUsdai.depositTimelockBalance(), 0);
    }

    function test__CancelEscrowLoanTimelock_ReturnsPrincipalToStakedUsdai() public {
        uint256 stakedUsdaiBalanceBefore = IERC20(address(usdai)).balanceOf(address(stakedUsdai));
        _depositEscrow();
        /* stakedUsdai lost DEPOSIT_AMOUNT on deposit (sent to escrow admin) */
        assertEq(IERC20(address(usdai)).balanceOf(address(stakedUsdai)), stakedUsdaiBalanceBefore - DEPOSIT_AMOUNT);

        vm.prank(users.manager);
        stakedUsdai.cancelLoanEscrowTimelock(LOAN_HASH);
        /* principal returned; no interest yet since zero time elapsed */
        assertEq(IERC20(address(usdai)).balanceOf(address(stakedUsdai)), stakedUsdaiBalanceBefore);
    }

    function test__CancelEscrowLoanTimelock_ReturnsPrincipalAndInterestFromEscrowAdmin() public {
        _depositEscrow();
        uint256 adminBalanceAfterDeposit = IERC20(address(usdai)).balanceOf(users.admin);

        warp(30 days);
        uint256 expectedInterest = _expectedInterest(30 days);

        vm.prank(users.manager);
        stakedUsdai.cancelLoanEscrowTimelock(LOAN_HASH);

        /* Admin received DEPOSIT_AMOUNT on deposit and must return deposit + interest on cancel. */
        assertEq(
            IERC20(address(usdai)).balanceOf(users.admin), adminBalanceAfterDeposit - DEPOSIT_AMOUNT - expectedInterest
        );
    }

    function test__CancelEscrowLoanTimelock_InterestRoutedToDepositBalance() public {
        (uint256 depositBalanceBefore,) = stakedUsdai.balances();

        _depositEscrow();
        warp(30 days);
        uint256 expectedInterest = _expectedInterest(30 days);
        uint256 expectedAdminFee = expectedInterest * LOAN_ROUTER_ADMIN_FEE_RATE / BASIS_POINTS_SCALE;
        uint256 expectedRepayment = expectedInterest - expectedAdminFee;

        /* Capture the admin fee recipient balance before the cancel */
        uint256 adminFeeBalanceBefore = IERC20(address(usdai)).balanceOf(users.adminFeeRecipient);

        vm.prank(users.manager);
        stakedUsdai.cancelLoanEscrowTimelock(LOAN_HASH);

        /* Principal round-trips, so the deposit balance grows by the net interest */
        (uint256 depositBalanceAfter,) = stakedUsdai.balances();
        assertApproxEqAbs(depositBalanceAfter - depositBalanceBefore, expectedRepayment, 1);

        /* The admin fee is transferred straight to the recipient */
        uint256 adminFeeBalanceAfter = IERC20(address(usdai)).balanceOf(users.adminFeeRecipient);
        assertApproxEqAbs(adminFeeBalanceAfter - adminFeeBalanceBefore, expectedAdminFee, 1);
    }

    function test__CancelEscrowLoanTimelock_ZeroInterest_WhenCancelledImmediately() public {
        (uint256 depositBalanceBefore,) = stakedUsdai.balances();

        /* Capture the admin fee recipient balance before the cancel */
        uint256 adminFeeBalanceBefore = IERC20(address(usdai)).balanceOf(users.admin);

        _depositEscrow();
        vm.prank(users.manager);
        stakedUsdai.cancelLoanEscrowTimelock(LOAN_HASH);

        /* Deposit balance returns to its starting value with zero elapsed time */
        (uint256 depositBalanceAfter,) = stakedUsdai.balances();
        assertEq(depositBalanceAfter, depositBalanceBefore, "no interest should accrue with zero elapsed time");

        /* No admin fee is transferred without interest */
        uint256 adminFeeBalanceAfter = IERC20(address(usdai)).balanceOf(users.admin);
        assertEq(adminFeeBalanceAfter, adminFeeBalanceBefore, "no admin fee without interest");
    }

    function test__CancelEscrowLoanTimelock_EmitsEvent() public {
        _depositEscrow();
        warp(30 days);
        uint256 expectedInterest = _expectedInterest(30 days);

        vm.expectEmit(true, false, false, true, address(stakedUsdai));
        emit ILoanRouterPositionManager.LoanEscrowTimelockCancelled(LOAN_HASH, DEPOSIT_AMOUNT, expectedInterest);

        vm.prank(users.manager);
        stakedUsdai.cancelLoanEscrowTimelock(LOAN_HASH);
    }

    function test__CancelEscrowLoanTimelock_RevertWhen_NotStrategyAdmin() public {
        _depositEscrow();
        vm.expectRevert();
        vm.prank(users.normalUser1);
        stakedUsdai.cancelLoanEscrowTimelock(LOAN_HASH);
    }

    /*------------------------------------------------------------------------*/
    /* onEscrowWithdrawn (via real EscrowTimelock.withdraw) */
    /*------------------------------------------------------------------------*/

    function test__OnEscrowWithdrawn_InterestRoutedToDepositBalance() public {
        _depositEscrow();
        warp(30 days);
        uint256 expectedInterest = _expectedInterest(30 days);
        uint256 expectedAdminFee = expectedInterest * LOAN_ROUTER_ADMIN_FEE_RATE / BASIS_POINTS_SCALE;
        uint256 expectedRepayment = expectedInterest - expectedAdminFee;

        (uint256 depositBalanceBefore,) = stakedUsdai.balances();

        /* Capture the admin fee recipient balance before the withdraw */
        uint256 adminFeeBalanceBefore = IERC20(address(usdai)).balanceOf(users.adminFeeRecipient);

        vm.prank(address(loanRouter));
        escrowTimelock.withdraw(LOAN_HASH, address(usdai), DEPOSIT_AMOUNT);

        (uint256 depositBalanceAfter,) = stakedUsdai.balances();
        assertApproxEqAbs(depositBalanceAfter - depositBalanceBefore, expectedRepayment, 1);

        /* The admin fee is transferred straight to the recipient */
        uint256 adminFeeBalanceAfter = IERC20(address(usdai)).balanceOf(users.adminFeeRecipient);
        assertApproxEqAbs(adminFeeBalanceAfter - adminFeeBalanceBefore, expectedAdminFee, 1);
    }

    function test__OnEscrowWithdrawn_ZeroInterest_WhenWithdrawnImmediately() public {
        _depositEscrow();
        (uint256 depositBalanceBefore,) = stakedUsdai.balances();

        /* Capture the admin fee recipient balance before the withdraw */
        uint256 adminFeeBalanceBefore = IERC20(address(usdai)).balanceOf(users.admin);

        vm.prank(address(loanRouter));
        escrowTimelock.withdraw(LOAN_HASH, address(usdai), DEPOSIT_AMOUNT);

        (uint256 depositBalanceAfter,) = stakedUsdai.balances();
        assertEq(depositBalanceAfter, depositBalanceBefore, "no interest with zero elapsed time");

        /* No admin fee is transferred without interest */
        uint256 adminFeeBalanceAfter = IERC20(address(usdai)).balanceOf(users.admin);
        assertEq(adminFeeBalanceAfter, adminFeeBalanceBefore, "no admin fee without interest");
    }

    function test__OnEscrowWithdrawn_TransfersInterestFromEscrowAdmin() public {
        _depositEscrow();
        warp(30 days);
        uint256 adminBalanceBefore = IERC20(address(usdai)).balanceOf(users.admin);
        uint256 expectedInterest = _expectedInterest(30 days);

        vm.prank(address(loanRouter));
        escrowTimelock.withdraw(LOAN_HASH, address(usdai), DEPOSIT_AMOUNT);

        assertEq(IERC20(address(usdai)).balanceOf(users.admin), adminBalanceBefore - expectedInterest);
    }

    function test__OnEscrowWithdrawn_RevertWhen_CallerNotEscrowTimelock() public {
        _depositEscrow();
        vm.expectRevert(LoanRouterPositionManagerLogic.InvalidCaller.selector);
        vm.prank(users.normalUser1);
        stakedUsdai.onEscrowWithdrawn(address(loanRouter), LOAN_HASH, address(usdai), DEPOSIT_AMOUNT, 0);
    }

    /*------------------------------------------------------------------------*/
    /* Accrued escrow interest in valuation */
    /*------------------------------------------------------------------------*/

    function test__AccruedEscrowInterest_IncreasesOptimisticNav() public {
        _depositEscrow();

        /* Escrow principal stays tracked as deposit timelock balance, so nav only moves with accrued interest */
        uint256 navBefore = stakedUsdai.nav();

        warp(30 days);

        /* Optimistic nav grows by the accrued escrow interest net of the admin fee */
        assertApproxEqAbs(stakedUsdai.nav(), navBefore + _expectedNetInterest(30 days), 1);
    }
}
