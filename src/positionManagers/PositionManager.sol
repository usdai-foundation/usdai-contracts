// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

/**
 * @title Position Manager
 * @author USD.AI Foundation
 */
abstract contract PositionManager {
    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Basis points scale
     */
    uint256 internal constant BASIS_POINTS_SCALE = 10_000;

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Asset valuation type
     */
    enum ValuationType {
        CONSERVATIVE,
        OPTIMISTIC
    }

    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Insufficient balance
     */
    error InsufficientBalance();

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Assets value
     * @return Assets value
     */
    function _assets(
        ValuationType valuationType
    ) internal view virtual returns (uint256);
}
