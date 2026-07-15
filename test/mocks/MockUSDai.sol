// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IUSDai} from "src/interfaces/IUSDai.sol";
import {IMintableBurnable} from "src/interfaces/IMintableBurnable.sol";

/**
 * @title Mock USDai ERC20
 * @author USD.AI Foundation
 */
contract MockUSDai is
    IUSDai,
    IMintableBurnable,
    ERC165Upgradeable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    MulticallUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable
{
    /*------------------------------------------------------------------------*/
    /* Constant */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Base yield recipient role
     */
    bytes32 internal constant BASE_YIELD_RECIPIENT_ROLE = keccak256("BASE_YIELD_RECIPIENT_ROLE");

    /**
     * @notice Blacklist admin role
     */
    bytes32 internal constant BLACKLIST_ADMIN_ROLE = keccak256("BLACKLIST_ADMIN_ROLE");

    /**
     * @notice Base yield accrual storage location
     * @dev keccak256(abi.encode(uint256(keccak256("USDai.baseYieldAccrual")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant BASE_YIELD_ACCRUAL_STORAGE_LOCATION =
        0xad76c5b481cb106971e0ae4c23a09cb5b1dc9dba5fad96d9694630df5e853900;

    /**
     * @notice Supply cap
     * @dev keccak256(abi.encode(uint256(keccak256("USDai.supply")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant SUPPLY_STORAGE_LOCATION =
        0x5fc387bd350b82c09f22bee4c04d61669980ce519c352560e36bc6144f9cf800;

    /**
     * @notice Blacklist storage location
     * @dev keccak256(abi.encode(uint256(keccak256("USDai.blacklist")) - 1)) & ~bytes32(uint256(0xff));
     */
    bytes32 private constant BLACKLIST_STORAGE_LOCATION =
        0xd21f45001ca28b8905ef527bd860800b2646ce7faf578b00aa2e89af23551500;

    /*------------------------------------------------------------------------*/
    /* Immutable State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Bridge adapter contract
     */
    address internal immutable _bridgeAdapter;

    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Base token
     */
    address internal _baseToken;

    /*------------------------------------------------------------------------*/
    /* Structures */
    /*------------------------------------------------------------------------*/

    /**
     * @custom:storage-location erc7201:USDai.supply
     */
    struct Supply {
        uint256 bridged;
    }

    /**
     * @custom:storage-location erc7201:USDai.baseYieldAccrual
     */
    struct BaseYieldAccrual {
        RateTier[] rateTiers;
        uint256 accrued;
        uint64 timestamp;
    }

    /**
     * @custom:storage-location erc7201:USDai.blacklist
     */
    struct Blacklist {
        mapping(address => bool) blacklist;
    }

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice MockUSDai Constructor
     * @param bridgeAdapter_ Bridge adapter contract
     */
    constructor(
        address bridgeAdapter_
    ) {
        _bridgeAdapter = bridgeAdapter_;

        _disableInitializers();
    }

    /*------------------------------------------------------------------------*/
    /* Initialization  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialize the contract
     */
    function initialize() public initializer {
        __ERC20_init("USDai", "USDai");
        __ERC20Permit_init("USDai");
        __Multicall_init();
        __ReentrancyGuard_init();
        __AccessControl_init();

        /* Grant roles */
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /*------------------------------------------------------------------------*/
    /* Modifiers  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Non-zero value modifier
     * @param value Value to check
     */
    modifier nonZeroUint(
        uint256 value
    ) {
        if (value == 0) revert InvalidAmount();
        _;
    }

    /**
     * @notice Non-zero address modifier
     * @param value Value to check
     */
    modifier nonZeroAddress(
        address value
    ) {
        if (value == address(0)) revert InvalidAddress();
        _;
    }

    /**
     * @notice Not blacklisted modifier
     * @param value Value to check
     */
    modifier notBlacklisted(
        address value
    ) {
        if (_getBlacklistStorage().blacklist[value]) {
            revert BlacklistedAddress(value);
        }
        _;
    }

    /**
     * @notice Only bridge adapter modifier
     */
    modifier onlyBridgeAdapter() {
        if (msg.sender != _bridgeAdapter) revert InvalidAddress();
        _;
    }

    /*------------------------------------------------------------------------*/
    /* Getters  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get implementation name
     * @return Implementation name
     */
    function implementationName() external pure returns (string memory) {
        return "Mock USDai";
    }

    /**
     * @notice Get implementation version
     * @return Implementation version
     */
    function implementationVersion() external pure returns (string memory) {
        return "1.0";
    }

    /**
     * @inheritdoc IUSDai
     */
    function baseToken() external view returns (address) {
        return _baseToken;
    }

    /**
     * @notice Set base token
     * @param baseToken_ Base token
     */
    function setBaseToken(
        address baseToken_
    ) external {
        _baseToken = baseToken_;
    }

    /**
     * @inheritdoc IUSDai
     */
    function bridgedSupply() public view returns (uint256) {
        return _getSupplyStorage().bridged;
    }

    /**
     * @inheritdoc IUSDai
     */
    function baseYieldAccrued() public view returns (uint256) {
        return _getBaseYieldAccrualStorage().accrued;
    }

    /**
     * @inheritdoc IUSDai
     */
    function isBlacklisted(
        address account
    ) external view returns (bool) {
        return _getBlacklistStorage().blacklist[account];
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get reference to USDai supply storage
     *
     * @return $ Reference to supply storage
     */
    function _getSupplyStorage() internal pure returns (Supply storage $) {
        assembly {
            $.slot := SUPPLY_STORAGE_LOCATION
        }
    }

    /**
     * @notice Get reference to USDai base yield accrual storage
     *
     * @return $ Reference to base yield accrual storage
     */
    function _getBaseYieldAccrualStorage() internal pure returns (BaseYieldAccrual storage $) {
        assembly {
            $.slot := BASE_YIELD_ACCRUAL_STORAGE_LOCATION
        }
    }

    /**
     * @notice Get reference to USDai blacklist storage
     *
     * @return $ Reference to blacklist storage
     */
    function _getBlacklistStorage() internal pure returns (Blacklist storage $) {
        assembly {
            $.slot := BLACKLIST_STORAGE_LOCATION
        }
    }

    /**
     * @notice Deposit base token
     * @param depositAmount Deposit amount
     * @param recipient Recipient address
     * @return USDai amount
     */
    function _deposit(
        uint256 depositAmount,
        address recipient
    ) internal virtual nonZeroUint(depositAmount) nonZeroAddress(recipient) returns (uint256) {
        /* Transfer base token in from sender to this contract */
        IERC20(_baseToken).transferFrom(msg.sender, address(this), depositAmount);

        /* Scale deposit amount based on base token decimals */
        uint256 usdaiAmount = IERC20Metadata(_baseToken).decimals() == 6 ? depositAmount * 1e12 : depositAmount;

        /* Mint to the recipient */
        _mint(recipient, usdaiAmount);

        /* Emit deposited event */
        emit Deposited(msg.sender, recipient, _baseToken, depositAmount, usdaiAmount);

        return usdaiAmount;
    }

    /**
     * @notice Withdraw base token
     * @param usdaiAmount USD.ai amount
     * @param recipient Recipient address
     * @return Withdraw amount
     */
    function _withdraw(
        uint256 usdaiAmount,
        address recipient
    ) internal nonZeroUint(usdaiAmount) nonZeroAddress(recipient) returns (uint256) {
        /* Burn USD.ai tokens */
        _burn(msg.sender, usdaiAmount);

        /* Scale USDai amount down based on base token decimals */
        uint256 withdrawAmount = IERC20Metadata(_baseToken).decimals() == 6 ? usdaiAmount / 1e12 : usdaiAmount;

        /* Transfer base token to the recipient address */
        IERC20(_baseToken).transfer(recipient, withdrawAmount);

        /* Emit withdrawn event */
        emit Withdrawn(msg.sender, recipient, _baseToken, usdaiAmount, withdrawAmount);

        return withdrawAmount;
    }

    /*------------------------------------------------------------------------*/
    /* ERC20Upgradeable overrides */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ERC20Upgradeable
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override notBlacklisted(msg.sender) notBlacklisted(from) notBlacklisted(to) {
        super._update(from, to, value);
    }

    /*------------------------------------------------------------------------*/
    /* Public API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IUSDai
     */
    function deposit(uint256 baseTokenAmount, address recipient) external nonReentrant returns (uint256) {
        return _deposit(baseTokenAmount, recipient);
    }

    /**
     * @inheritdoc IUSDai
     */
    function deposit(
        address,
        uint256 depositAmount,
        uint256,
        address recipient
    ) external nonReentrant returns (uint256) {
        return _deposit(depositAmount, recipient);
    }

    /**
     * @inheritdoc IUSDai
     */
    function deposit(
        address,
        uint256 depositAmount,
        uint256,
        address recipient,
        bytes calldata
    ) external nonReentrant returns (uint256) {
        return _deposit(depositAmount, recipient);
    }

    /**
     * @inheritdoc IUSDai
     */
    function withdraw(uint256 usdaiAmount, address recipient) external nonReentrant returns (uint256) {
        return _withdraw(usdaiAmount, recipient);
    }

    /**
     * @inheritdoc IUSDai
     */
    function withdraw(
        address,
        uint256 usdaiAmount,
        uint256,
        address recipient
    ) external nonReentrant returns (uint256) {
        return _withdraw(usdaiAmount, recipient);
    }

    /**
     * @inheritdoc IUSDai
     */
    function withdraw(
        address,
        uint256 usdaiAmount,
        uint256,
        address recipient,
        bytes calldata
    ) external nonReentrant returns (uint256) {
        return _withdraw(usdaiAmount, recipient);
    }

    /*------------------------------------------------------------------------*/
    /* Minter API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IMintableBurnable
     */
    function mint(address to, uint256 amount) external onlyBridgeAdapter {
        _mint(to, amount);

        /* Update bridged supply */
        _getSupplyStorage().bridged -= amount;
    }

    /**
     * @inheritdoc IMintableBurnable
     */
    function burn(address from, uint256 amount) external onlyBridgeAdapter {
        _burn(from, amount);

        /* Update bridged supply */
        _getSupplyStorage().bridged += amount;
    }

    /*------------------------------------------------------------------------*/
    /* Base Yield Recipient API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IUSDai
     */
    function harvest() external onlyRole(BASE_YIELD_RECIPIENT_ROLE) returns (uint256) {
        _getBaseYieldAccrualStorage().accrued = 0;

        /* Emit harvested event */
        emit Harvested(0);

        return 0;
    }

    /*------------------------------------------------------------------------*/
    /* Blacklist Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IUSDai
     */
    function setBlacklist(address account, bool isBlacklisted) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getBlacklistStorage().blacklist[account] = isBlacklisted;

        emit BlacklistUpdated(account, isBlacklisted);
    }

    /*------------------------------------------------------------------------*/
    /* Pause Admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IUSDai
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @inheritdoc IUSDai
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /*------------------------------------------------------------------------*/
    /* Base Escrow API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IUSDai
     */
    function setRateTiers(
        RateTier[] memory rateTiers
    ) external {
        /* Set rate tiers */
        _getBaseYieldAccrualStorage().rateTiers = rateTiers;

        /* Emit rate tiers set event */
        emit BaseYieldRateTiersSet(rateTiers);
    }

    /*------------------------------------------------------------------------*/
    /* ERC165 */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc ERC165Upgradeable
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControlUpgradeable, ERC165Upgradeable) returns (bool) {
        return interfaceId == type(IERC20).interfaceId || interfaceId == type(IUSDai).interfaceId
            || interfaceId == type(IMintableBurnable).interfaceId || super.supportsInterface(interfaceId);
    }
}
