// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Base Position Manager Interface
 * @author USD.AI Foundation
 */
interface IBasePositionManager {
    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Base yield deposited
     * @param depositedAmount Deposited USDai amount
     * @param adminFee Admin fee
     */
    event BaseYieldDeposited(uint256 depositedAmount, uint256 adminFee);

    /*------------------------------------------------------------------------*/
    /* Getter */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Claimable base yield in USDai
     * @return Claimable base yield in USDai
     */
    function claimableBaseYield() external view returns (uint256);

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Harvest base yield
     * @return Deposited USDai amount
     * @return Admin fee
     */
    function harvestBaseYield() external returns (uint256, uint256);
}
