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

    /**
     * @notice Insufficient native fee
     */
    error InsufficientNativeFee();

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
        uint32 indexed dstEid,
        address indexed depositToken,
        bytes32 indexed recipient,
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
        uint32 indexed dstEid,
        address indexed withdrawToken,
        bytes32 indexed recipient,
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
        uint32 indexed dstEid,
        address indexed depositToken,
        bytes32 indexed recipient,
        uint256 depositAmount,
        uint256 usdaiAmount,
        uint256 susdaiAmount
    );

    /**
     * @notice Composer stake event
     * @param dstEid Destination chain EID
     * @param recipient Recipient address
     * @param usdaiAmount Amount of USDai staked
     * @param susdaiAmount Amount of Staked USDai received
     */
    event ComposerStake(uint32 indexed dstEid, bytes32 indexed recipient, uint256 usdaiAmount, uint256 susdaiAmount);

    /**
     * @notice Action failed event
     * @param action Action that failed
     * @param reason Reason for action failure
     */
    event ActionFailed(string action, bytes reason);

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
     * @notice Rescue tokens
     * @param token Token to rescue
     * @param to Recipient address
     * @param amount Amount of tokens to rescue
     */
    function rescueERC20(address token, address to, uint256 amount) external;

    /**
     * @notice Rescue ETH
     * @param to Recipient address
     * @param amount Amount of ETH to rescue
     */
    function rescueETH(address to, uint256 amount) external;
}
