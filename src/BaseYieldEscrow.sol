// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "./interfaces/IBaseYieldEscrow.sol";
import "./interfaces/IUSDai.sol";

/**
 * @title Base Yield Escrow
 * @author USD.AI Foundation
 */
contract BaseYieldEscrow is IBaseYieldEscrow, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /*------------------------------------------------------------------------*/
    /* Constant */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Implementation version
     */
    string public constant IMPLEMENTATION_VERSION = "1.0";

    /**
     * @notice Escrow admin role
     */
    bytes32 internal constant ESCROW_ADMIN_ROLE = keccak256("ESCROW_ADMIN_ROLE");

    /**
     * @notice Harvest admin role
     */
    bytes32 internal constant HARVEST_ADMIN_ROLE = keccak256("HARVEST_ADMIN_ROLE");

    /**
     * @notice Rate admin role
     */
    bytes32 internal constant RATE_ADMIN_ROLE = keccak256("RATE_ADMIN_ROLE");

    /*------------------------------------------------------------------------*/
    /* Immutable state */
    /*------------------------------------------------------------------------*/

    /**
     * @notice USDai
     */
    IUSDai internal immutable _usdai;

    /**
     * @notice Base token
     */
    IERC20 internal immutable _baseToken;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Base Yield Escrow Constructor
     * @param usdai_ USDai
     * @param baseToken_ Base token
     */
    constructor(address usdai_, address baseToken_) {
        _disableInitializers();

        _usdai = IUSDai(usdai_);
        _baseToken = IERC20(baseToken_);
    }

    /*------------------------------------------------------------------------*/
    /* Initialization  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialize the contract
     * @param admin Default admin address
     */
    function initialize(
        address admin
    ) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        /* Grant roles */
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IBaseYieldEscrow
     */
    function baseToken() external view returns (address) {
        return address(_baseToken);
    }

    /**
     * @inheritdoc IBaseYieldEscrow
     */
    function balance() external view returns (uint256) {
        return _baseToken.balanceOf(address(this));
    }

    /*------------------------------------------------------------------------*/
    /* Base Token Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IBaseYieldEscrow
     */
    function deposit(
        uint256 amount
    ) external nonReentrant onlyRole(ESCROW_ADMIN_ROLE) {
        _baseToken.safeTransferFrom(msg.sender, address(this), amount);

        /* Emit deposited event */
        emit Deposited(msg.sender, amount);
    }

    /**
     * @inheritdoc IBaseYieldEscrow
     */
    function withdraw(
        uint256 amount
    ) external nonReentrant onlyRole(ESCROW_ADMIN_ROLE) {
        _baseToken.transfer(msg.sender, amount);

        /* Emit withdrawn event */
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @inheritdoc IBaseYieldEscrow
     */
    function harvest(
        uint256 amount
    ) external nonReentrant onlyRole(HARVEST_ADMIN_ROLE) {
        _baseToken.transfer(msg.sender, amount);

        /* Emit harvested event */
        emit Harvested(msg.sender, amount);
    }

    /**
     * @inheritdoc IBaseYieldEscrow
     */
    function setRateTiers(
        IUSDai.RateTier[] memory rateTiers
    ) external nonReentrant onlyRole(RATE_ADMIN_ROLE) {
        _usdai.setRateTiers(rateTiers);

        /* Emit rate tiers set event */
        emit BaseYieldRateTiersSet(rateTiers);
    }
}
