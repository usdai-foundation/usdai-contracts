// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

/**
 * @title Mock Loan Router
 * @author USD.AI Foundation
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
        return address(0);
    }

    /**
     * @notice Get escrow timelock
     * @return Escrow timelock address
     */
    function escrowTimelock() external view returns (address) {
        return address(0);
    }
}
