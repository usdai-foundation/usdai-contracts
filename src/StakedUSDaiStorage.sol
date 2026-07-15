// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./interfaces/IStakedUSDai.sol";
import "./interfaces/IUSDai.sol";

/**
 * @title Staked USDai Storage
 * @author USD.AI Foundation
 */
abstract contract StakedUSDaiStorage {
    using EnumerableSet for EnumerableSet.UintSet;

    /*------------------------------------------------------------------------*/
    /* Roles */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Pause role
     */
    bytes32 internal constant PAUSE_ADMIN_ROLE = keccak256("PAUSE_ADMIN_ROLE");

    /**
     * @notice Strategy admin role
     */
    bytes32 internal constant STRATEGY_ADMIN_ROLE = keccak256("STRATEGY_ADMIN_ROLE");

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Is operator storage location
     * @dev keccak256(abi.encode(uint256(keccak256("stakedUSDai.isOperator")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant IS_OPERATOR_STORAGE_LOCATION =
        0x407fc66dcc0b10c2a8ec69f9095c4cd702e9ed0fb1a7e0f6b6f65bd03e776100;

    /**
     * @notice Redemption status storage location
     * @dev keccak256(abi.encode(uint256(keccak256("stakedUSDai.redemptionState_")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant REDEMPTION_STATE_STORAGE_LOCATION =
        0xc6ad599b80e437d86c31abd9e2cd5c6ce030f11e9dbae11bc05446f7af4d4900;

    /**
     * @notice Bridged supply storage location
     * @dev keccak256(abi.encode(uint256(keccak256("stakedUSDai.bridgedSupply")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant BRIDGED_SUPPLY_STORAGE_LOCATION =
        0x3625978433c3d3388ec2dddfdf4dd931786e9db5f2382a6ed08621dc9fb95f00;

    /**
     * @notice Deposits storage location
     * @dev keccak256(abi.encode(uint256(keccak256("stakedUSDai.deposits")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant DEPOSITS_STORAGE_LOCATION =
        0x2c5de62bb029e52f8f5651820547ac44294b098c752111b71e5fee4f80a66900;

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @custom:storage-location erc7201:stakedUSDai.isOperator
     */
    struct IsOperator {
        mapping(address => mapping(address => bool)) isOperator;
    }

    /**
     * @custom:storage-location erc7201:stakedUSDai.redemptionState
     * @param index Current redemption index
     * @param head Head of the redemption queue
     * @param tail Tail of the redemption queue
     * @param pending Pending redemption shares
     * @param balance Redemption balance
     * @param redemptions Mapping of redemption index to redemption
     * @param redemptionIds Mapping of controller to redemption indices
     */
    struct RedemptionState {
        uint256 index;
        uint256 head;
        uint256 tail;
        uint256 pending;
        uint256 balance;
        mapping(uint256 => IStakedUSDai.Redemption) redemptions;
        mapping(address => EnumerableSet.UintSet) redemptionIds;
    }

    /**
     * @custom:storage-location erc7201:stakedUSDai.bridgedSupply
     */
    struct BridgedSupply {
        uint256 bridgedSupply;
    }

    /**
     * @custom:storage-location erc7201:stakedUSDai.deposits
     */
    struct Deposits {
        uint256 balance;
    }

    /*------------------------------------------------------------------------*/
    /* Immutable */
    /*------------------------------------------------------------------------*/

    /**
     * @notice USDai
     */
    IUSDai internal immutable _usdai;

    /**
     * @notice Admin fee recipient
     */
    address internal immutable _adminFeeRecipient;

    /**
     * @notice Genesis timestamp
     */
    uint64 internal immutable _genesisTimestamp;

    /**
     * @notice Bridge adapter contract
     */
    address internal immutable _bridgeAdapter;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Constructor
     * @param usdai USDai
     * @param adminFeeRecipient Admin fee recipient
     * @param genesisTimestamp Genesis timestamp
     * @param bridgeAdapter Bridge adapter contract
     */
    constructor(address usdai, address adminFeeRecipient, uint64 genesisTimestamp, address bridgeAdapter) {
        _usdai = IUSDai(usdai);
        _adminFeeRecipient = adminFeeRecipient;
        _genesisTimestamp = genesisTimestamp;
        _bridgeAdapter = bridgeAdapter;
    }

    /*------------------------------------------------------------------------*/
    /* Storage getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get reference to ERC-7201 is operator storage
     *
     * @return $ Reference to is operator storage
     */
    function _getIsOperatorStorage() internal pure returns (IsOperator storage $) {
        assembly {
            $.slot := IS_OPERATOR_STORAGE_LOCATION
        }
    }
    /**
     * @notice Get reference to ERC-7201 redemption state storage
     *
     * @return $ Reference to redemption state storage
     */

    function _getRedemptionStateStorage() internal pure returns (RedemptionState storage $) {
        assembly {
            $.slot := REDEMPTION_STATE_STORAGE_LOCATION
        }
    }

    /**
     * @notice Get reference to ERC-7201 bridged supply storage
     *
     * @return $ Reference to bridged supply storage
     */
    function _getBridgedSupplyStorage() internal pure returns (BridgedSupply storage $) {
        assembly {
            $.slot := BRIDGED_SUPPLY_STORAGE_LOCATION
        }
    }

    /**
     * @notice Get reference to ERC-7201 deposits storage
     *
     * @return $ Reference to deposits storage
     */
    function _getDepositsStorage() internal pure returns (Deposits storage $) {
        assembly {
            $.slot := DEPOSITS_STORAGE_LOCATION
        }
    }
}
