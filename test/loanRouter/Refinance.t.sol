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
 * @title Cash-out refinance
 * @author USD.AI Foundation
 *
 * @notice Originates a large USDai loan on the local stack and lets interest accrue, then
 *         refinances it into a larger loan at a higher rate. The cash-out top-up is funded
 *         from the deposit timelock, the accrued interest is reset by the refinance and
 *         offset by a donation paid back to the strategy as a refinance fee, and the new
 *         loan starts on a fresh schedule.
 */
contract RefinanceTest is BaseLoanRouterTest {
    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /* StakedUSDai loans storage location (erc7201:stakedUSDai.loans) */
    bytes32 internal constant LOANS_STORAGE_LOCATION =
        0xeedf9bea8709bd441d5da250df505e80fc82bec74f9f1df28edf19fa1ed4bd00;

    /* Old loan principal */
    uint256 internal constant OLD_PRINCIPAL = 50_000_000 ether;

    /* New total principal after the cash-out top-up */
    uint256 internal constant NEW_PRINCIPAL = 65_000_000 ether;

    /* Old rate (8% APR per second, 1e18 scaled) */
    uint256 internal constant OLD_RATE = RATE_10_PCT * 8 / 10;

    /* New rate (12% APR per second, 1e18 scaled) */
    uint256 internal constant NEW_RATE = RATE_10_PCT * 12 / 10;

    /* Window over which interest accrues before the refinance */
    uint256 internal constant ELAPSED = 30 days;

    /* Loan router admin fee rate on accrued interest (1%) */
    uint256 internal constant ADMIN_FEE_RATE = 100;

    /* Fee and interest rate models */
    address internal feeModel;
    address internal rateModel;

    /*------------------------------------------------------------------------*/
    /* Snapshot */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Snapshot of pre-refinance state and derived amounts
     */
    struct Snap {
        bytes32 newHash;
        uint256 cashOut;
        uint256 donation;
        uint256 pending;
        uint256 timelock;
        uint256 borrower;
        uint256 nav;
        uint256 poolRate;
        uint256 loanRate;
    }

    /*------------------------------------------------------------------------*/
    /* Setup */
    /*------------------------------------------------------------------------*/

    function setUp() public override {
        /* Deploy the full local stack and seed StakedUSDai */
        super.setUp();

        /* Deploy the fee and interest rate models */
        feeModel = _deployAbsoluteFeeModel();
        rateModel = _deploySimpleInterestRateModel();

        /* Grant the originator role to this test so it can refinance */
        vm.prank(users.admin);
        IAccessControl(address(loanRouter)).grantRole(keccak256("ORIGINATOR_ROLE"), address(this));
    }

    /*------------------------------------------------------------------------*/
    /* Test */
    /*------------------------------------------------------------------------*/

    /**
     * @notice A loan refinances into a larger cash-out loan with a donation
     */
    function test__RefinanceCashOut() public {
        /* Originate the loan and let interest accrue */
        (ILoanRouterV2.LoanTermsV2 memory oldTerms, bytes32 oldHash) = _originateLoan(OLD_PRINCIPAL, OLD_RATE);
        vm.warp(block.timestamp + ELAPSED);

        /* Read the router balance for the expected balance argument */
        (,,, uint256 oldRouterBalance) = ILoanRouterV2(address(loanRouter)).loanState(oldHash);

        /* Collect pre-refinance state and derived amounts */
        Snap memory snap;
        snap.loanRate = _loanAccrualRate(oldHash);
        snap.poolRate = stakedUsdai.accrualRate();
        snap.cashOut = NEW_PRINCIPAL - OLD_PRINCIPAL;

        /* Reversed accrued interest is the loan's accrual over its window, net of the admin fee */
        snap.donation = (snap.loanRate * (block.timestamp - _loanLastRepayment(oldHash)) / FIXED_POINT_SCALE)
            * (BASIS_POINTS_SCALE - ADMIN_FEE_RATE) / BASIS_POINTS_SCALE;

        /* Build new terms with the grown notional, higher rate, and donation fee */
        ILoanRouterV2.LoanTermsV2 memory newTerms = _newTerms(oldTerms, snap.donation);
        snap.newHash = _loanHash(newTerms);

        /* Seed idle USDai and pre-fund the cash-out into the deposit timelock */
        _fundStrategyIdle(snap.cashOut);
        vm.prank(users.manager);
        stakedUsdai.depositLoanDepositTimelock(snap.newHash, snap.cashOut, newTerms.expiration);

        /* Snapshot balances right before the refinance */
        (snap.pending,) = stakedUsdai.loanRouterBalances();
        snap.timelock = stakedUsdai.depositTimelockBalance();
        snap.borrower = IERC20(address(usdai)).balanceOf(oldTerms.borrower);
        snap.nav = IStakedUSDai(address(stakedUsdai)).nav();

        /* Refinance the loan */
        ILoanRouterV2(address(loanRouter)).refinance(oldTerms, newTerms, oldRouterBalance);

        /* Assert the post-refinance state */
        _assertAfter(oldHash, oldTerms.borrower, snap);
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Assert the router and StakedUSDai state after the refinance
     * @param oldHash Old loan terms hash
     * @param borrower Loan borrower
     * @param snap Pre-refinance snapshot
     */
    function _assertAfter(bytes32 oldHash, address borrower, Snap memory snap) internal view {
        /* Router closed the old loan and opened the new loan at the grown balance */
        (ILoanRouterV2.LoanStatus oldStatus,,,) = ILoanRouterV2(address(loanRouter)).loanState(oldHash);
        assertEq(uint8(oldStatus), uint8(ILoanRouterV2.LoanStatus.Repaid), "old loan not repaid");
        (ILoanRouterV2.LoanStatus newStatus,, uint64 newOrigination, uint256 newRouterBalance) =
            ILoanRouterV2(address(loanRouter)).loanState(snap.newHash);
        assertEq(uint8(newStatus), uint8(ILoanRouterV2.LoanStatus.Active), "new loan not active");
        assertEq(newRouterBalance, NEW_PRINCIPAL, "new router balance wrong");
        assertEq(newOrigination, uint64(block.timestamp), "origination not reset");

        /* Aggregate pending grew by the cash-out */
        (uint256 pendingAfter,) = stakedUsdai.loanRouterBalances();
        assertEq(pendingAfter, snap.pending + snap.cashOut, "aggregate not grown by cash-out");

        /* Deposit timelock drawn by the cash-out */
        assertEq(stakedUsdai.depositTimelockBalance(), snap.timelock - snap.cashOut, "timelock not drawn");

        /* New loan tracked on a fresh schedule with the grown balance */
        assertEq(_loanPendingBalance(snap.newHash), NEW_PRINCIPAL, "new pending balance wrong");
        assertEq(_loanLastRepayment(snap.newHash), uint64(block.timestamp), "repayment timestamp not reset");
        assertEq(_loanAccrualRate(snap.newHash), NEW_RATE * NEW_PRINCIPAL, "new accrual rate wrong");

        /* Old loan entry cleared */
        assertEq(_loanLastRepayment(oldHash), 0, "old loan entry not cleared");

        /* Pool accrual rate reversed the old rate and added the new rate */
        assertEq(
            stakedUsdai.accrualRate(), snap.poolRate - snap.loanRate + NEW_RATE * NEW_PRINCIPAL, "pool rate delta wrong"
        );

        /* Borrower received the cash-out top-up minus the donation fee */
        assertEq(
            IERC20(address(usdai)).balanceOf(borrower),
            snap.borrower + snap.cashOut - snap.donation,
            "borrower cash-out wrong"
        );

        /* NAV is conserved, the donation offsets the reversed accrued interest */
        assertApproxEqAbs(IStakedUSDai(address(stakedUsdai)).nav(), snap.nav, 1e15, "NAV not conserved");
    }

    /**
     * @notice Build new loan terms with the grown notional, higher rate, and donation fee
     * @param oldTerms Old loan terms
     * @param donation Refinance donation fee
     * @return terms New loan terms
     */
    function _newTerms(
        ILoanRouterV2.LoanTermsV2 memory oldTerms,
        uint256 donation
    ) internal view returns (ILoanRouterV2.LoanTermsV2 memory terms) {
        /* Deep copy the old terms so mutations do not alias the original */
        terms = abi.decode(abi.encode(oldTerms), (ILoanRouterV2.LoanTermsV2));

        /* Grow the tranche notional and raise the rate */
        terms.trancheSpecs[0].amount = NEW_PRINCIPAL;
        terms.trancheSpecs[0].rate = NEW_RATE;

        /* Set a fresh expiration */
        terms.expiration = uint64(block.timestamp + 30 days);

        /* Add the donation as a refinance fee paid back to the strategy */
        ILoanRouterV2.FeeSpec[] memory feeSpecs = new ILoanRouterV2.FeeSpec[](1);
        feeSpecs[0] = ILoanRouterV2.FeeSpec({
            kind: ILoanRouterV2.FeeKind.Refinance,
            recipient: address(stakedUsdai),
            model: feeModel,
            options: abi.encode(donation)
        });
        terms.feeSpecs = feeSpecs;
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
        /* Build standard terms with the origination rate */
        terms = createLoanTerms(principal, collateralTokenIds, address(usdai));
        terms.trancheSpecs[0].rate = rate;

        /* Point the fee and rate specs at real models */
        terms.feeSpecs[0].model = feeModel;
        terms.interestRateSpec.model = rateModel;
        terms.interestRateSpec.options = abi.encode(false, uint64(GRACE_PERIOD_DURATION), uint256(GRACE_PERIOD_RATE));

        /* Hash the loan terms */
        loanTermsHash = _loanHash(terms);

        /* Borrower escrows the collateral into the collateral timelock */
        vm.prank(users.borrower);
        ICollateralTimelock(address(collateralTimelock)).deposit(
            address(loanRouter), loanTermsHash, address(testNFT), terms.collateralTokenIds, terms.expiration
        );

        /* Fund StakedUSDai with the principal and deposit it into the deposit timelock */
        deal(address(usdai), address(stakedUsdai), IERC20(address(usdai)).balanceOf(address(stakedUsdai)) + principal);
        vm.startPrank(address(stakedUsdai));
        IERC20(address(usdai)).approve(address(depositTimelock), principal);
        IDepositTimelock(address(depositTimelock)).deposit(
            address(loanRouter), loanTermsHash, address(usdai), principal, terms.expiration
        );
        vm.stopPrank();

        /* Build the deposit info for the deposit timelock */
        ILoanRouterV2.LenderDepositInfo[] memory depositInfos = new ILoanRouterV2.LenderDepositInfo[](1);
        depositInfos[0] =
            ILoanRouterV2.LenderDepositInfo({depositType: ILoanRouterV2.DepositType.DepositTimelock, data: ""});

        /* Originate the loan on-chain */
        vm.prank(users.admin);
        IAccessControl(address(loanRouter)).grantRole(keccak256("ORIGINATOR_ROLE"), users.admin);
        vm.prank(users.admin);
        loanRouter.originate(terms, depositInfos, new bytes[](0));
    }

    /**
     * @notice Give StakedUSDai idle USDai and register it in the deposit balance
     * @param amount USDai amount
     */
    function _fundStrategyIdle(
        uint256 amount
    ) internal {
        /* Deal USDai to the strategy on top of any existing balance */
        deal(address(usdai), address(stakedUsdai), IERC20(address(usdai)).balanceOf(address(stakedUsdai)) + amount);

        /* Bump the deposits storage balance so depositLoanDepositTimelock sees idle funds */
        bytes32 depositsSlot = 0x2c5de62bb029e52f8f5651820547ac44294b098c752111b71e5fee4f80a66900;
        uint256 current = uint256(vm.load(address(stakedUsdai), depositsSlot));
        vm.store(address(stakedUsdai), depositsSlot, bytes32(current + amount));
    }

    /**
     * @notice Hash loan terms the way the router does
     * @param terms Loan terms
     * @return Loan terms hash
     */
    function _loanHash(
        ILoanRouterV2.LoanTermsV2 memory terms
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, terms));
    }

    /**
     * @notice Deploy the real AbsoluteFeeModel from the loan-router artifacts
     * @return Fee model address
     */
    function _deployAbsoluteFeeModel() internal returns (address) {
        string memory json = vm.readFile("externalOut/AbsoluteFeeModel.sol/AbsoluteFeeModel.json");
        return _deployFromHex(vm.parseJsonString(json, ".bytecode.object"), "");
    }

    /**
     * @notice Deploy the real SimpleInterestRateModel, linking ScheduleLogic
     * @return Interest rate model address
     */
    function _deploySimpleInterestRateModel() internal returns (address) {
        /* Deploy ScheduleLogic which the model links against */
        address scheduleLogicLib = _deployFromHex(
            vm.parseJsonString(vm.readFile("externalOut/ScheduleLogic.sol/ScheduleLogic.json"), ".bytecode.object"), ""
        );

        /* Read, link, and deploy the model */
        string memory json = vm.readFile("externalOut/SimpleInterestRateModel.sol/SimpleInterestRateModel.json");
        bytes memory modelHex = bytes(vm.parseJsonString(json, ".bytecode.object"));
        _linkLibrary(modelHex, json, "src/ScheduleLogic.sol", "ScheduleLogic", scheduleLogicLib);
        return _deployFromHex(string(modelHex), "");
    }

    function _loanSlot(
        bytes32 loanHash
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(loanHash, uint256(LOANS_STORAGE_LOCATION) + 5)));
    }

    function _loanAccrualRate(
        bytes32 loanHash
    ) internal view returns (uint256) {
        return uint256(vm.load(address(stakedUsdai), bytes32(_loanSlot(loanHash))));
    }

    function _loanPendingBalance(
        bytes32 loanHash
    ) internal view returns (uint256) {
        return uint256(vm.load(address(stakedUsdai), bytes32(_loanSlot(loanHash) + 1)));
    }

    function _loanLastRepayment(
        bytes32 loanHash
    ) internal view returns (uint64) {
        return uint64(uint256(vm.load(address(stakedUsdai), bytes32(_loanSlot(loanHash) + 2))));
    }
}
