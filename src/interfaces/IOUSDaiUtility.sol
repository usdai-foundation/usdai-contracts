// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title OUSDai Utility Interface
 * @author USD.AI Foundation
 */
interface IOUSDaiUtility {
    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Action type
     */
    enum ActionType {
        Deposit,
        DepositAndStake,
        QueuedDeposit, /* deprecated no-op, kept for enum ordinal stability */
        Stake,
        Withdraw
    }

    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid address
     */
    error InvalidAddress();

    /**
     * @notice Unknown Action
     */
    error UnknownAction();

    /**
     * @notice Deposit failed
     */
    error DepositFailed();

    /**
     * @notice Withdraw failed
     */
    error WithdrawFailed();

    /**
     * @notice Deposit and stake failed
     */
    error DepositAndStakeFailed();

    /**
     * @notice Stake failed
     */
    error StakeFailed();

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Composer deposit event
     * @param dstEid Destination chain EID
     * @param depositToken Deposit token
     * @param recipient Recipient address
     * @param depositAmount Amount of deposit token
     * @param usdaiAmount Amount of USDai received
     */
    event ComposerDeposit(
        uint256 indexed dstEid,
        address indexed depositToken,
        address indexed recipient,
        uint256 depositAmount,
        uint256 usdaiAmount
    );

    /**
     * @notice Composer withdraw event
     * @param dstEid Destination chain EID
     * @param withdrawToken Withdraw token
     * @param recipient Recipient address
     * @param usdaiAmount Amount of USDai
     * @param withdrawAmount Amount of withdraw token received
     */
    event ComposerWithdraw(
        uint256 indexed dstEid,
        address indexed withdrawToken,
        address indexed recipient,
        uint256 usdaiAmount,
        uint256 withdrawAmount
    );

    /**
     * @notice Composer deposit and stake event
     * @param dstEid Destination chain EID
     * @param depositToken Deposit token
     * @param recipient Recipient address
     * @param depositAmount Amount of deposit token
     * @param usdaiAmount Amount of USDai received
     * @param susdaiAmount Amount of Staked USDai received
     */
    event ComposerDepositAndStake(
        uint256 indexed dstEid,
        address indexed depositToken,
        address indexed recipient,
        uint256 depositAmount,
        uint256 usdaiAmount,
        uint256 susdaiAmount
    );

    /**
     * @notice Composer stake event
     * @param dstEid Destination chain EID
     * @param recipient Recipient
     * @param usdaiAmount Amount of USDai staked
     * @param susdaiAmount Amount of Staked USDai received
     */
    event ComposerStake(uint256 indexed dstEid, address indexed recipient, uint256 usdaiAmount, uint256 susdaiAmount);

    /**
     * @notice Action failed event
     * @param action Action that failed
     * @param reason Reason for action failure
     */
    event ActionFailed(string indexed action, bytes reason);

    /**
     * @notice Whitelisted OAdapters added event
     * @param oAdapters OAdapters added
     */
    event WhitelistedOAdaptersAdded(address[] oAdapters);

    /**
     * @notice Whitelisted OAdapters removed event
     * @param oAdapters OAdapters removed
     */
    event WhitelistedOAdaptersRemoved(address[] oAdapters);

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get whitelisted OAdapters
     * @param offset Offset into list
     * @param count Count to return
     * @return OAdapters
     */
    function whitelistedOAdapters(uint256 offset, uint256 count) external view returns (address[] memory);

    /*------------------------------------------------------------------------*/
    /* Public API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Entry point for actions originating on local chain
     * @param actionType Action type
     * @param depositToken Deposit token
     * @param depositAmount Deposit token amount
     * @param data Additional compose data
     */
    function localCompose(
        ActionType actionType,
        address depositToken,
        uint256 depositAmount,
        bytes memory data
    ) external payable;

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Add whitelisted OAdapters
     * @param oAdapters OAdapters to whitelist
     */
    function addWhitelistedOAdapters(
        address[] memory oAdapters
    ) external;

    /**
     * @notice Remove whitelisted OAdapters
     * @param oAdapters OAdapters to remove
     */
    function removeWhitelistedOAdapters(
        address[] memory oAdapters
    ) external;

    /**
     * @notice Rescue tokens
     * @param token Token to rescue
     * @param to Recipient address
     * @param amount Amount of tokens to rescue
     */
    function rescue(address token, address to, uint256 amount) external;
}
