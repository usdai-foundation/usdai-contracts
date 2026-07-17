// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {StakedUSDaiStorage} from "src/StakedUSDaiStorage.sol";
import {RedemptionLogic} from "src/RedemptionLogic.sol";

import {BasePositionManager} from "src/positionManagers/BasePositionManager.sol";
import {LoanRouterPositionManager} from "src/positionManagers/LoanRouterPositionManager.sol";

import {IStakedUSDai} from "src/interfaces/IStakedUSDai.sol";
import {IERC7540Redeem, IERC7540Operator} from "src/interfaces/IERC7540.sol";
import {IMintableBurnable} from "src/interfaces/IMintableBurnable.sol";

/**
 * @title Mock Staked USDai ERC20
 * @author USD.AI Foundation
 */
contract MockStakedUSDai is
    ERC165Upgradeable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    MulticallUpgradeable,
    PausableUpgradeable,
    StakedUSDaiStorage,
    BasePositionManager,
    LoanRouterPositionManager,
    IStakedUSDai,
    IMintableBurnable,
    IERC4626,
    IERC7540Redeem,
    IERC7540Operator
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Fixed point scale
     */
    uint256 internal constant FIXED_POINT_SCALE = 1e18;

    /**
     * @notice Amount of shares to lock for initial deposit
     */
    uint128 private constant LOCKED_SHARES = 1e6;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice MockStakedUSDai Constructor
     */
    constructor(
        address usdai_,
        address loanRouter_,
        address bridgeAdapter_
    )
        StakedUSDaiStorage(usdai_, address(0), uint64(block.timestamp), bridgeAdapter_)
        BasePositionManager(0)
        LoanRouterPositionManager(loanRouter_, 0)
    {
        _disableInitializers();
    }

    /*------------------------------------------------------------------------*/
    /* Initialization  */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initialize the contract
     */
    function initialize() external initializer {
        __ERC165_init();
        __ERC20_init("Staked USDai", "sUSDai");
        __ERC20Permit_init("Staked USDai");
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
        if (_usdai.isBlacklisted(value)) {
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
     * @return The implementation name
     */
    function implementationName() external pure returns (string memory) {
        return "Staked USDai";
    }

    /**
     * @notice Get implementation version
     * @return The implementation version
     */
    function implementationVersion() external pure returns (string memory) {
        return "1.0";
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function redemptionQueueInfo()
        external
        view
        returns (uint256 index, uint256 head, uint256 tail, uint256 pending, uint256 balance)
    {
        return (
            _getRedemptionStateStorage().index,
            _getRedemptionStateStorage().head,
            _getRedemptionStateStorage().tail,
            _getRedemptionStateStorage().pending,
            _getRedemptionStateStorage().balance
        );
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function redemptionTimestamp() external view returns (uint64) {
        return RedemptionLogic._nextRedemptionTimestamp(_genesisTimestamp);
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function redemption(
        uint256 redemptionId
    ) external view returns (Redemption memory, uint256) {
        return RedemptionLogic._redemption(_getRedemptionStateStorage(), redemptionId);
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function redemptionIds(
        address controller
    ) external view nonZeroAddress(controller) returns (uint256[] memory) {
        return _getRedemptionStateStorage().redemptionIds[controller].values();
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function nav() external view returns (uint256) {
        return _assets(ValuationType.OPTIMISTIC);
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function depositSharePrice() public view returns (uint256) {
        return _sharePrice(ValuationType.OPTIMISTIC);
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function redemptionSharePrice() public view returns (uint256) {
        return _sharePrice(ValuationType.CONSERVATIVE);
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function totalShares() public view returns (uint256) {
        return totalSupply() + _getBridgedSupplyStorage().bridgedSupply + _getRedemptionStateStorage().pending;
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function bridgedSupply() public view returns (uint256) {
        return _getBridgedSupplyStorage().bridgedSupply;
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function balances() external view returns (uint256, uint256) {
        return (_usdai.balanceOf(address(this)), _getRedemptionStateStorage().balance);
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers  */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc BasePositionManager
     */
    function _assets(
        ValuationType
    ) internal view override(BasePositionManager, LoanRouterPositionManager) returns (uint256) {
        return _depositBalance();
    }

    /**
     * @notice USDai deposit balance in this contract less serviced redemption
     * @return USDai deposit balance less serviced redemption
     */
    function _depositBalance() internal view returns (uint256) {
        return _usdai.balanceOf(address(this)) - _getRedemptionStateStorage().balance;
    }

    /**
     * @notice Compute share price
     * @param valuationType Valuation type
     * @return Share price
     */
    function _sharePrice(
        ValuationType valuationType
    ) internal view returns (uint256) {
        return totalShares() == 0 ? FIXED_POINT_SCALE : (_assets(valuationType) * FIXED_POINT_SCALE) / totalShares();
    }

    /**
     * @notice Deposit assets
     * @param amount Amount to deposit
     * @param receiver Receiver address
     * @param minShares Minimum shares
     * @return Shares minted
     */
    function _deposit(
        uint256 amount,
        address receiver,
        uint256 minShares
    )
        internal
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(receiver)
        nonReentrant
        nonZeroUint(amount)
        nonZeroAddress(receiver)
        returns (uint256)
    {
        /* Compute shares */
        uint256 shares = convertToShares(amount);

        /* If shares is 0 or less than min shares, revert */
        if (shares == 0 || shares < minShares) revert InvalidAmount();

        /* Mint shares */
        _mint(receiver, shares);

        /* Deposit assets */
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        /* Emit Deposit */
        emit Deposit(msg.sender, receiver, amount, shares);

        return shares;
    }

    function _mint(
        uint256 shares,
        address receiver,
        uint256 maxAmount
    )
        internal
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(receiver)
        nonReentrant
        nonZeroUint(shares)
        nonZeroAddress(receiver)
        returns (uint256 assets)
    {
        /* Compute amount */
        uint256 amount = convertToAssets(shares);

        /* If amount is 0 or more than max amount, revert */
        if (amount == 0 || amount > maxAmount) revert InvalidAmount();

        /* Mint shares */
        _mint(receiver, shares);

        /* Deposit assets */
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        /* Emit Deposit */
        emit Deposit(msg.sender, receiver, amount, shares);

        return amount;
    }

    /*------------------------------------------------------------------------*/
    /* ERC4626  */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IERC4626
     */
    function asset() public view returns (address) {
        return address(_usdai);
    }

    /**
     * @inheritdoc IERC4626
     */
    function totalAssets() external view returns (uint256) {
        return _assets(ValuationType.OPTIMISTIC);
    }

    /**
     * @inheritdoc IERC4626
     */
    function previewWithdraw(
        uint256
    ) external pure returns (uint256) {
        revert DisabledImplementation();
    }

    /**
     * @inheritdoc IERC4626
     */
    function previewRedeem(
        uint256
    ) external pure returns (uint256) {
        revert DisabledImplementation();
    }

    /**
     * @inheritdoc IERC4626
     */
    function maxWithdraw(
        address controller
    ) external view returns (uint256) {
        (uint256 amount,) = RedemptionLogic._redemptionAvailable(_getRedemptionStateStorage(), controller);

        /* Return amount */
        return amount;
    }

    /**
     * @inheritdoc IERC4626
     */
    function maxRedeem(
        address controller
    ) external view returns (uint256) {
        (, uint256 shares) = RedemptionLogic._redemptionAvailable(_getRedemptionStateStorage(), controller);

        /* Return shares */
        return shares;
    }

    /**
     * @inheritdoc IERC4626
     */
    function maxDeposit(
        address
    ) external pure returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @inheritdoc IERC4626
     */
    function maxMint(
        address
    ) external pure returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @inheritdoc IERC4626
     */
    function convertToShares(
        uint256 assets
    ) public view nonZeroUint(assets) returns (uint256) {
        /* Check if initial deposit */
        bool initialDeposit = totalShares() < LOCKED_SHARES;

        /* Compute shares */
        uint256 shares = ((assets * FIXED_POINT_SCALE) / depositSharePrice());

        /* Check if initial deposit and shares is less than locked shares */
        if (initialDeposit && shares <= LOCKED_SHARES) revert InvalidAmount();

        /* Compute shares. If initial deposit, lock subset of shares */
        return shares - (initialDeposit ? LOCKED_SHARES : 0);
    }

    /**
     * @inheritdoc IERC4626
     */
    function convertToAssets(
        uint256 shares
    ) public view nonZeroUint(shares) returns (uint256) {
        /* Check if initial deposit */
        bool initialDeposit = totalShares() < LOCKED_SHARES;

        /* Check if initial deposit and shares is less than locked shares */
        if (initialDeposit && shares <= LOCKED_SHARES) revert InvalidAmount();

        /* Compute assets. If initial deposit, add locked shares to shares */
        return ((initialDeposit ? shares + LOCKED_SHARES : shares) * depositSharePrice()) / FIXED_POINT_SCALE;
    }

    /**
     * @inheritdoc IERC4626
     */
    function previewDeposit(
        uint256 assets
    ) external view returns (uint256) {
        return convertToShares(assets);
    }

    /**
     * @inheritdoc IERC4626
     */
    function previewMint(
        uint256 shares
    ) external view returns (uint256) {
        return convertToAssets(shares);
    }

    /**
     * @inheritdoc IERC4626
     */
    function deposit(uint256 amount, address receiver) external returns (uint256) {
        return _deposit(amount, receiver, 0);
    }

    /**
     * @inheritdoc IERC4626
     */
    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        return _mint(shares, receiver, type(uint256).max);
    }

    /**
     * @inheritdoc IERC4626
     */
    function withdraw(
        uint256 amount,
        address receiver,
        address controller
    )
        external
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(controller)
        notBlacklisted(receiver)
        nonReentrant
        nonZeroUint(amount)
        nonZeroAddress(receiver)
        nonZeroAddress(controller)
        returns (uint256)
    {
        /* Validate caller */
        if (controller != msg.sender && !_getIsOperatorStorage().isOperator[controller][msg.sender]) {
            revert InvalidCaller();
        }

        /* Withdraw amount */
        uint256 shares = RedemptionLogic._withdraw(_getRedemptionStateStorage(), amount, controller);

        /* Transfer assets */
        IERC20(asset()).safeTransfer(receiver, amount);

        /* Emit Withdraw */
        emit Withdraw(msg.sender, controller, receiver, amount, shares);

        return shares;
    }

    /**
     * @inheritdoc IERC4626
     */
    function redeem(
        uint256 shares,
        address receiver,
        address controller
    )
        external
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(controller)
        notBlacklisted(receiver)
        nonReentrant
        nonZeroUint(shares)
        nonZeroAddress(receiver)
        nonZeroAddress(controller)
        returns (uint256)
    {
        /* Validate caller */
        if (controller != msg.sender && !_getIsOperatorStorage().isOperator[controller][msg.sender]) {
            revert InvalidCaller();
        }

        /* Redeem shares */
        uint256 amount = RedemptionLogic._redeem(_getRedemptionStateStorage(), shares, controller);

        /* Transfer assets */
        if (amount > 0) IERC20(asset()).safeTransfer(receiver, amount);

        /* Emit Withdraw */
        emit Withdraw(msg.sender, controller, receiver, amount, shares);

        return amount;
    }

    /*------------------------------------------------------------------------*/
    /* ERC4626 Overload */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IStakedUSDai
     */
    function deposit(uint256 amount, address receiver, uint256 minShares) external returns (uint256) {
        return _deposit(amount, receiver, minShares);
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function mint(uint256 shares, address receiver, uint256 maxAmount) external returns (uint256) {
        return _mint(shares, receiver, maxAmount);
    }

    /*------------------------------------------------------------------------*/
    /* ERC7540Operator */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IERC7540Operator
     */
    function isOperator(address controller, address operator) external view returns (bool status) {
        return _getIsOperatorStorage().isOperator[controller][operator];
    }

    /**
     * @inheritdoc IERC7540Operator
     */
    function setOperator(
        address operator,
        bool approved
    )
        external
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(operator)
        nonReentrant
        nonZeroAddress(operator)
        returns (bool)
    {
        /* Validate caller */
        if (msg.sender == operator) revert InvalidAddress();

        /* Set operator */
        _getIsOperatorStorage().isOperator[msg.sender][operator] = approved;

        /* Emit OperatorSet */
        emit OperatorSet(msg.sender, operator, approved);

        return true;
    }

    /*------------------------------------------------------------------------*/
    /* ERC7540Redeem */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IERC7540Redeem
     */
    function pendingRedeemRequest(uint256 redemptionId, address controller) external view returns (uint256) {
        /* Get redemption */
        Redemption storage redemption_ = _getRedemptionStateStorage().redemptions[redemptionId];

        /* If controller is not the same, return 0 */
        if (redemption_.controller != controller) return 0;

        return redemption_.pendingShares;
    }

    /**
     * @inheritdoc IERC7540Redeem
     */
    function claimableRedeemRequest(uint256 redemptionId, address controller) external view returns (uint256) {
        /* Get redemption */
        Redemption storage redemption_ = _getRedemptionStateStorage().redemptions[redemptionId];

        /* If controller is not the same or redemption is not past redemption timestamp, return 0 */
        if (redemption_.controller != controller || redemption_.redemptionTimestamp >= block.timestamp) return 0;

        return redemption_.redeemableShares;
    }

    /**
     * @inheritdoc IERC7540Redeem
     */
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    )
        external
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(controller)
        notBlacklisted(owner)
        nonReentrant
        nonZeroUint(shares)
        nonZeroAddress(controller)
        nonZeroAddress(owner)
        returns (uint256)
    {
        /* Validate caller */
        if (owner != msg.sender && !_getIsOperatorStorage().isOperator[owner][msg.sender]) revert InvalidCaller();

        /* Validate balance */
        if (balanceOf(owner) < shares) revert InsufficientBalance();

        /* Burn sUSDai shares */
        _burn(owner, shares);

        /* Request redeem */
        uint256 redemptionId =
            RedemptionLogic._requestRedeem(_getRedemptionStateStorage(), _genesisTimestamp, shares, controller);

        /* Emit redeem request */
        emit RedeemRequest(controller, owner, redemptionId, msg.sender, shares);

        return redemptionId;
    }

    /*------------------------------------------------------------------------*/
    /* Pause admin API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IStakedUSDai
     */
    function pause() external onlyRole(PAUSE_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @inheritdoc IStakedUSDai
     */
    function unpause() external onlyRole(PAUSE_ADMIN_ROLE) {
        _unpause();
    }

    /*------------------------------------------------------------------------*/
    /* Manager API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IStakedUSDai
     */
    function serviceRedemptions(
        uint256 shares
    ) external onlyRole(STRATEGY_ADMIN_ROLE) nonZeroUint(shares) returns (uint256) {
        /* Process redemptions */
        (uint256 amountProcessed, bool allRedemptionsServiced) =
            RedemptionLogic._processRedemptions(_getRedemptionStateStorage(), shares, redemptionSharePrice());

        /* Validate amount is available to be serviced */
        if (amountProcessed > _depositBalance()) revert InsufficientBalance();

        /* Update redemption balance */
        _getRedemptionStateStorage().balance += amountProcessed;

        /* Emit RedemptionsServiced */
        emit RedemptionsServiced(shares, amountProcessed, allRedemptionsServiced);

        return amountProcessed;
    }

    /*------------------------------------------------------------------------*/
    /* Minter API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IMintableBurnable
     */
    function mint(address to, uint256 amount) external onlyBridgeAdapter {
        /* Mint supply */
        _mint(to, amount);

        /* Update bridged supply */
        _getBridgedSupplyStorage().bridgedSupply -= amount;
    }

    /**
     * @inheritdoc IMintableBurnable
     */
    function burn(address from, uint256 amount) external onlyBridgeAdapter {
        /* Burn supply */
        _burn(from, amount);

        /* Update bridged supply */
        _getBridgedSupplyStorage().bridgedSupply += amount;
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
        return interfaceId == type(IERC20).interfaceId || interfaceId == type(IERC4626).interfaceId
            || interfaceId == type(IERC7540Redeem).interfaceId || interfaceId == type(IERC7540Operator).interfaceId
            || interfaceId == type(IStakedUSDai).interfaceId || interfaceId == type(IMintableBurnable).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
