// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

/**
 * @title Mock Loan Router
 * @author USD.AI Foundation
 * @notice Stands in for the loan router and its timelocks so StakedUSDai can value its
 *         positions in memory. It reports itself as both timelocks and accrues no interest,
 *         which keeps the loan and escrow legs of the vault valuation at zero.
 */
contract MockLoanRouter {
    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get deposit timelock
     * @return Deposit timelock address
     */
    function depositTimelock() external view returns (address) {
        return address(this);
    }

    /**
     * @notice Get escrow timelock
     * @return Escrow timelock address
     */
    function escrowTimelock() external view returns (address) {
        return address(this);
    }

    /**
     * @notice Get accrued escrow interest
     * @return Accrued escrow interest
     */
    function accrued() external view returns (uint256) {
        return 0;
    }
}
