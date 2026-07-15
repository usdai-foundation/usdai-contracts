// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IBasePositionManager.sol";

/**
 * @title Staked USDai Interface
 * @author USD.AI Foundation
 */
interface IStakedUSDai is IBasePositionManager {
    /*------------------------------------------------------------------------*/
    /* Errors */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Invalid address
     */
    error InvalidAddress();

    /**
     * @notice Invalid caller
     */
    error InvalidCaller();

    /**
     * @notice Invalid redemption state
     */
    error InvalidRedemptionState();

    /**
     * @notice Invalid amount
     */
    error InvalidAmount();

    /**
     * @notice Disabled implementation
     */
    error DisabledImplementation();

    /**
     * @notice Blacklisted address
     * @param value Address
     */
    error BlacklistedAddress(address value);

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Redemption
     * @param prev Previous redemption index in queue
     * @param next Next redemption index in queue
     * @param pendingShares Pending shares
     * @param redeemableShares Shares that can be redeemed
     * @param withdrawableAmount Amount that can be withdrawn
     * @param controller Controller address
     * @param redemptionTimestamp Redemption timestamp
     */
    struct Redemption {
        uint256 prev;
        uint256 next;
        uint256 pendingShares;
        uint256 redeemableShares;
        uint256 withdrawableAmount;
        address controller;
        uint64 redemptionTimestamp;
    }

    /*------------------------------------------------------------------------*/
    /* Events */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Redemption Processed
     * @param redemptionId Redemption ID
     * @param controller Controller
     * @param fulfilledShares Fulfilled shares
     * @param amount Fulfilled amount
     * @param pendingShares Pending shares
     */
    event RedemptionProcessed(
        uint256 indexed redemptionId,
        address indexed controller,
        uint256 fulfilledShares,
        uint256 amount,
        uint256 pendingShares
    );

    /**
     * @notice Redemptions Serviced
     * @param shares Shares processed
     * @param amount Amount processed
     * @param allRedemptionsServiced True if all redemptions are serviced
     */
    event RedemptionsServiced(uint256 shares, uint256 amount, bool allRedemptionsServiced);

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get total shares
     * @return Total shares
     */
    function totalShares() external view returns (uint256);

    /**
     * @notice Get redemption queue info
     * @return index Redemption index
     * @return head Redemption head
     * @return tail Redemption tail
     * @return pending Redemption shares pending
     * @return balance Redemption balance
     */
    function redemptionQueueInfo()
        external
        view
        returns (uint256 index, uint256 head, uint256 tail, uint256 pending, uint256 balance);

    /**
     * @notice Get redemption timestamp
     * @return Redemption timestamp
     */
    function redemptionTimestamp() external view returns (uint64);

    /**
     * @notice Get redemption
     * @param redemptionId Redemption ID
     * @return Redemption
     * @return Shares ahead
     */
    function redemption(
        uint256 redemptionId
    ) external view returns (Redemption memory, uint256);

    /**
     * @notice Get redemption IDs
     * @param controller Controller
     * @return Redemption IDs
     */
    function redemptionIds(
        address controller
    ) external view returns (uint256[] memory);

    /**
     * @notice Get net asset value
     * @return Net asset value
     */
    function nav() external view returns (uint256);

    /**
     * @notice Get deposit and redemption balances
     * @return Deposit balance
     * @return Redemption balance
     */
    function balances() external view returns (uint256, uint256);

    /**
     * @notice Get admin fee recipient
     * @return Admin fee recipient
     */
    function adminFeeRecipient() external view returns (address);

    /**
     * @notice Get deposit share price
     * @return Deposit share price
     */
    function depositSharePrice() external view returns (uint256);

    /**
     * @notice Get redemption share price
     * @return Redemption share price
     */
    function redemptionSharePrice() external view returns (uint256);

    /**
     * @notice Get bridged supply
     * @return Bridged supply
     */
    function bridgedSupply() external view returns (uint256);

    /*------------------------------------------------------------------------*/
    /* API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Overload of IERC4626 deposit
     * @param amount Amount to deposit
     * @param receiver Receiver address
     * @param minShares Minimum shares
     * @return Shares minted
     */
    function deposit(uint256 amount, address receiver, uint256 minShares) external returns (uint256);

    /**
     * @notice Overload of IERC4626 mint
     * @param shares Shares to mint
     * @param receiver Receiver address
     * @param maxAmount Maximum amount
     * @return Amount minted
     */
    function mint(uint256 shares, address receiver, uint256 maxAmount) external returns (uint256);

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
    /* Strategy Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Service pending redemption requests
     * @param shares Shares to process
     * @return Amount processed
     */
    function serviceRedemptions(
        uint256 shares
    ) external returns (uint256);
}
