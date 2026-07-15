// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title USDai Interface
 * @author USD.AI Foundation
 */
interface IUSDai is IERC20 {
    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid address
     */
    error InvalidAddress();

    /**
     * @notice Invalid amount
     */
    error InvalidAmount();

    /**
     * @notice Blacklisted address
     * @param value Blacklisted address
     */
    error BlacklistedAddress(address value);

    /**
     * @notice Invalid parameters
     */
    error InvalidParameters();

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Rate tier
     * @param rate Rate
     * @param threshold Threshold
     */
    struct RateTier {
        uint256 rate;
        uint256 threshold;
    }

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposited event
     * @param caller Caller
     * @param recipient Recipient
     * @param depositToken Deposit token
     * @param depositAmount Deposit amount
     * @param mintAmount Mint amount
     */
    event Deposited(
        address indexed caller,
        address indexed recipient,
        address depositToken,
        uint256 depositAmount,
        uint256 mintAmount
    );

    /**
     * @notice Withdrawn event
     * @param caller Caller
     * @param recipient Recipient
     * @param withdrawToken Withdraw token
     * @param usdaiAmount USDai amount
     * @param withdrawAmount Withdraw amount
     */
    event Withdrawn(
        address indexed caller,
        address indexed recipient,
        address withdrawToken,
        uint256 usdaiAmount,
        uint256 withdrawAmount
    );

    /**
     * @notice Harvested event
     * @param usdaiAmount USDai amount
     */
    event Harvested(uint256 usdaiAmount);

    /**
     * @notice Blacklist updated event
     * @param account Account
     * @param isBlacklisted Is blacklisted
     */
    event BlacklistUpdated(address indexed account, bool isBlacklisted);

    /**
     * @notice Base yield rate tiers set
     * @param rateTiers Rate tiers
     */
    event BaseYieldRateTiersSet(RateTier[] rateTiers);

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get swap adapter
     * @return Swap adapter
     */
    function swapAdapter() external view returns (address);

    /**
     * @notice Get base token
     * @return Base token
     */
    function baseToken() external view returns (address);

    /**
     * @notice Get bridged supply
     * @return Bridged supply
     */
    function bridgedSupply() external view returns (uint256);

    /**
     * @notice Get base yield accrued
     * @return Base yield accrued
     */
    function baseYieldAccrued() external view returns (uint256);

    /**
     * @notice Check if an address is blacklisted
     * @param account Account
     * @return Is blacklisted
     */
    function isBlacklisted(
        address account
    ) external view returns (bool);

    /*------------------------------------------------------------------------*/
    /* Public API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Deposit
     * @param depositToken Deposit token
     * @param depositAmount Deposit amount
     * @param usdaiAmountMinimum Minimum USDai amount
     * @param recipient Recipient
     * @return USDai amount
     */
    function deposit(
        address depositToken,
        uint256 depositAmount,
        uint256 usdaiAmountMinimum,
        address recipient
    ) external returns (uint256);

    /**
     * @notice Deposit
     * @param depositToken Deposit token
     * @param depositAmount Deposit amount
     * @param usdaiAmountMinimum Minimum USDai amount
     * @param recipient Recipient
     * @param data Data (for swap adapter)
     * @return USDai amount
     */
    function deposit(
        address depositToken,
        uint256 depositAmount,
        uint256 usdaiAmountMinimum,
        address recipient,
        bytes calldata data
    ) external returns (uint256);

    /**
     * @notice Withdraw
     * @param withdrawToken Withdraw token
     * @param usdaiAmount USDai amount
     * @param withdrawAmountMinimum Minimum withdraw amount
     * @param recipient Recipient
     * @return Withdraw amount
     */
    function withdraw(
        address withdrawToken,
        uint256 usdaiAmount,
        uint256 withdrawAmountMinimum,
        address recipient
    ) external returns (uint256);

    /**
     * @notice Withdraw
     * @param withdrawToken Withdraw token
     * @param usdaiAmount USDai amount
     * @param withdrawAmountMinimum Minimum withdraw amount
     * @param recipient Recipient
     * @param data Data (for swap adapter)
     * @return Withdraw amount
     */
    function withdraw(
        address withdrawToken,
        uint256 usdaiAmount,
        uint256 withdrawAmountMinimum,
        address recipient,
        bytes calldata data
    ) external returns (uint256);

    /*------------------------------------------------------------------------*/
    /* Base Yield Recipient API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Harvest base yield
     * @return USDai amount
     */
    function harvest() external returns (uint256);

    /*------------------------------------------------------------------------*/
    /* Blacklist Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Set blacklist
     * @param account Account
     * @param blacklisted Blacklisted
     */
    function setBlacklist(address account, bool blacklisted) external;

    /*------------------------------------------------------------------------*/
    /* Pause Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Pause the contract
     */
    function pause() external;

    /**
     * @notice Unpause the contract
     */
    function unpause() external;

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Set rate tiers
     * @param rateTiers Rate tiers
     */
    function setRateTiers(
        RateTier[] memory rateTiers
    ) external;
}
