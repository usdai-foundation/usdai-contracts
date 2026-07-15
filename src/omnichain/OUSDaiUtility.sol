// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroComposer.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";

import "../interfaces/IOUSDaiUtility.sol";
import "../interfaces/IUSDai.sol";
import "../interfaces/IStakedUSDai.sol";
import "../interfaces/IUSDaiQueuedDepositor.sol";

/**
 * @title Omnichain USDai Utility
 * @author USD.AI Foundation
 */
contract OUSDaiUtility is ILayerZeroComposer, ReentrancyGuardUpgradeable, AccessControlUpgradeable, IOUSDaiUtility {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Implementation version
     */
    string public constant IMPLEMENTATION_VERSION = "1.7";

    /*------------------------------------------------------------------------*/
    /* Immutable state */
    /*------------------------------------------------------------------------*/

    /**
     * @notice LayerZero endpoint for this contract to interact with
     */
    address internal immutable _endpoint;

    /**
     * @notice USDai contract
     */
    IUSDai internal immutable _usdai;

    /**
     * @notice USDai adapter
     */
    IOFT internal immutable _usdaiOAdapter;

    /**
     * @notice StakedUSDai contract
     */
    IStakedUSDai internal immutable _stakedUsdai;

    /**
     * @notice StakedUSDai adapter
     */
    IOFT internal immutable _stakedUsdaiOAdapter;

    /**
     * @notice USDai queued depositor on the destination chain
     */
    IUSDaiQueuedDepositor internal immutable _usdaiQueuedDepositor;

    /*------------------------------------------------------------------------*/
    /* State */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Whitelisted OAdapters
     */
    EnumerableSet.AddressSet internal _whitelistedOAdapters;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice OUSDaiUtility Constructor
     * @param endpoint_ LayerZero endpoint
     * @param usdai_ USDai contract
     * @param stakedUsdai_ StakedUSDai contract
     * @param usdaiOAdapter_ USDai omnichain adapter
     * @param stakedUsdaiOAdapter_ StakedUSDai omnichain adapter
     * @param usdaiQueuedDepositor_ USDai queued depositor
     */
    constructor(
        address endpoint_,
        address usdai_,
        address stakedUsdai_,
        address usdaiOAdapter_,
        address stakedUsdaiOAdapter_,
        address usdaiQueuedDepositor_
    ) {
        _disableInitializers();

        _endpoint = endpoint_;
        _usdai = IUSDai(usdai_);
        _stakedUsdai = IStakedUSDai(stakedUsdai_);
        _usdaiOAdapter = IOFT(usdaiOAdapter_);
        _stakedUsdaiOAdapter = IOFT(stakedUsdaiOAdapter_);
        _usdaiQueuedDepositor = IUSDaiQueuedDepositor(usdaiQueuedDepositor_);
    }

    /*------------------------------------------------------------------------*/
    /* Initialization */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initializer
     * @param admin Default admin address
     * @param oAdapters OAdapters to whitelist
     */
    function initialize(address admin, address[] memory oAdapters) external initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();

        for (uint256 i = 0; i < oAdapters.length; i++) {
            _whitelistedOAdapters.add(oAdapters[i]);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Refund
     * @param token Token
     * @param to Recipient address
     * @param amount Amount
     * @param action Action
     * @param reason Reason
     */
    function _refund(IERC20 token, address to, uint256 amount, string memory action, bytes memory reason) internal {
        /* Transfer the token to the recipient */
        token.transfer(to, amount);

        /* Refund the msg.value */
        (bool success,) = payable(to).call{value: msg.value}("");
        success;

        /* Emit the failed action event */
        emit ActionFailed(action, reason);
    }

    /**
     * @notice Deposit USDai
     * @dev sendParam.to must be an accessible account to receive tokens in the case of action failure
     * @param depositToken Deposit token
     * @param depositAmount Deposit token amount
     * @param data Additional compose data
     * @return success True if the deposit was successful, false otherwise
     */
    function _deposit(address depositToken, uint256 depositAmount, bytes memory data) internal returns (bool) {
        (uint256 usdaiAmountMinimum, bytes memory path, SendParam memory sendParam, uint256 nativeFee) =
            abi.decode(data, (uint256, bytes, SendParam, uint256));

        /* Get the destination address */
        address to = address(uint160(uint256(sendParam.to)));

        /* Validate the recipient is not blacklisted */
        if (_usdai.isBlacklisted(to)) {
            _refund(IERC20(depositToken), to, depositAmount, "Deposit", "Blacklisted recipient");

            return false;
        }

        /* Approve the USDai contract to spend the deposit token */
        IERC20(depositToken).forceApprove(address(_usdai), depositAmount);

        try _usdai.deposit(depositToken, depositAmount, usdaiAmountMinimum, address(this), path) returns (
            uint256 usdaiAmount
        ) {
            /* Transfer the USDai to local destination */
            if (sendParam.dstEid == 0) {
                /* Transfer the USDai to recipient */
                _usdai.transfer(to, usdaiAmount);

                /* Emit the deposit event */
                emit ComposerDeposit(sendParam.dstEid, depositToken, to, depositAmount, usdaiAmount);
            } else {
                /* Update the sendParam with the USDai amount */
                sendParam.amountLD = usdaiAmount;

                /* Send the USDai to destination chain */
                try _usdaiOAdapter.send{value: nativeFee}(
                    sendParam, MessagingFee({nativeFee: nativeFee, lzTokenFee: 0}), payable(to)
                ) {
                    /* Emit the deposit event */
                    emit ComposerDeposit(sendParam.dstEid, depositToken, to, depositAmount, usdaiAmount);
                } catch (bytes memory reason) {
                    /* Transfer the USDai to recipient */
                    _usdai.transfer(to, usdaiAmount);

                    /* Emit the failed action event */
                    emit ActionFailed("Send", reason);

                    return false;
                }
            }
        } catch (bytes memory reason) {
            _refund(IERC20(depositToken), to, depositAmount, "Deposit", reason);

            return false;
        }

        return true;
    }

    /**
     * @notice Deposit and stake the USDai
     * @dev sendParam.to must be an accessible account to receive tokens in the case of action failure
     * @param depositToken Deposit token
     * @param depositAmount Deposit token amount
     * @param data Additional compose data
     * @return success True if the deposit and stake was successful, false otherwise
     */
    function _depositAndStake(address depositToken, uint256 depositAmount, bytes memory data) internal returns (bool) {
        /* Decode the message */
        (
            uint256 usdaiAmountMinimum,
            bytes memory path,
            uint256 minShares,
            SendParam memory sendParam,
            uint256 nativeFee
        ) = abi.decode(data, (uint256, bytes, uint256, SendParam, uint256));

        /* Get the destination address */
        address to = address(uint160(uint256(sendParam.to)));

        /* Validate the recipient is not blacklisted */
        if (_usdai.isBlacklisted(to)) {
            _refund(IERC20(depositToken), to, depositAmount, "DepositAndStake", "Blacklisted recipient");

            return false;
        }

        /* Approve the USDai contract to spend the deposit token */
        IERC20(depositToken).forceApprove(address(_usdai), depositAmount);

        try _usdai.deposit(depositToken, depositAmount, usdaiAmountMinimum, address(this), path) returns (
            uint256 usdaiAmount
        ) {
            /* Approve the staked USDai contract to spend the USDai */
            _usdai.approve(address(_stakedUsdai), usdaiAmount);

            try _stakedUsdai.deposit(usdaiAmount, address(this), minShares) returns (uint256 susdaiAmount) {
                /* Transfer the staked USDai to local destination */
                if (sendParam.dstEid == 0) {
                    /* Transfer the staked USDai to recipient */
                    IERC20(address(_stakedUsdai)).transfer(to, susdaiAmount);

                    /* Emit the deposit and stake event */
                    emit ComposerDepositAndStake(
                        sendParam.dstEid, depositToken, to, depositAmount, usdaiAmount, susdaiAmount
                    );
                } else {
                    /* Update the sendParam with the staked USDai amount */
                    sendParam.amountLD = susdaiAmount;

                    /* Send the staked USDai to destination chain */
                    try _stakedUsdaiOAdapter.send{value: nativeFee}(
                        sendParam, MessagingFee({nativeFee: nativeFee, lzTokenFee: 0}), payable(to)
                    ) {
                        /* Emit the deposit and stake event */
                        emit ComposerDepositAndStake(
                            sendParam.dstEid, depositToken, to, depositAmount, usdaiAmount, susdaiAmount
                        );
                    } catch (bytes memory reason) {
                        /* Transfer the staked USDai to recipient */
                        IERC20(address(_stakedUsdai)).transfer(to, susdaiAmount);

                        /* Emit the failed action event */
                        emit ActionFailed("Send", reason);

                        return false;
                    }
                }
            } catch (bytes memory reason) {
                _refund(_usdai, to, usdaiAmount, "Stake", reason);

                return false;
            }
        } catch (bytes memory reason) {
            _refund(IERC20(depositToken), to, depositAmount, "Deposit", reason);

            return false;
        }

        return true;
    }

    /**
     * @notice Deposit the deposit token with the queued depositor
     * @param depositToken Deposit token
     * @param depositAmount Deposit token amount
     * @param data Additional compose data
     * @param srcEid Source EID
     * @return success True if the queued deposit was successful, false otherwise
     */
    function _queuedDeposit(
        address depositToken,
        uint256 depositAmount,
        bytes memory data,
        uint32 srcEid
    ) internal returns (bool) {
        /* Decode the message */
        (IUSDaiQueuedDepositor.QueueType queueType, address recipient, uint32 dstEid) =
            abi.decode(data, (IUSDaiQueuedDepositor.QueueType, address, uint32));

        /* Validate the recipient is not blacklisted */
        if (_usdai.isBlacklisted(recipient)) {
            _refund(IERC20(depositToken), recipient, depositAmount, "QueuedDeposit", "Blacklisted recipient");

            return false;
        }

        /* Approve the queued depositor contract to spend the deposit token */
        IERC20(depositToken).forceApprove(address(_usdaiQueuedDepositor), depositAmount);

        /* Deposit the deposit token into queued depositor */
        try _usdaiQueuedDepositor.deposit(queueType, depositToken, depositAmount, recipient, srcEid, dstEid) {
            /* Emit the queued deposit event */
            emit ComposerQueuedDeposit(queueType, depositToken, recipient, depositAmount);
        } catch (bytes memory reason) {
            _refund(IERC20(depositToken), recipient, depositAmount, "QueuedDeposit", reason);

            return false;
        }

        return true;
    }

    /**
     * @notice Stake USDai
     * @param depositToken Deposit token (must be USDai)
     * @param depositAmount USDai amount
     * @param data Additional compose data
     * @return success True if the stake was successful, false otherwise
     */
    function _stake(address depositToken, uint256 depositAmount, bytes memory data) internal returns (bool) {
        /* Decode the message */
        (uint256 minShares, SendParam memory sendParam, uint256 nativeFee) =
            abi.decode(data, (uint256, SendParam, uint256));

        /* Get the destination address */
        address to = address(uint160(uint256(sendParam.to)));

        /* Validate the deposit token is USDai and recipient is not blacklisted */
        if (depositToken != address(_usdai)) {
            _refund(IERC20(depositToken), to, depositAmount, "Stake", "Invalid deposit token");

            return false;
        } else if (_usdai.isBlacklisted(to)) {
            _refund(IERC20(depositToken), to, depositAmount, "Stake", "Blacklisted recipient");

            return false;
        }

        /* Approve the staked USDai contract to spend the USDai */
        _usdai.approve(address(_stakedUsdai), depositAmount);

        try _stakedUsdai.deposit(depositAmount, address(this), minShares) returns (uint256 susdaiAmount) {
            /* Transfer the staked USDai to local destination */
            if (sendParam.dstEid == 0) {
                /* Transfer the staked USDai to recipient */
                IERC20(address(_stakedUsdai)).transfer(to, susdaiAmount);

                /* Emit the stake event */
                emit ComposerStake(sendParam.dstEid, to, depositAmount, susdaiAmount);
            } else {
                /* Update the sendParam with the staked USDai amount */
                sendParam.amountLD = susdaiAmount;

                /* Send the staked USDai to destination chain */
                try _stakedUsdaiOAdapter.send{value: nativeFee}(
                    sendParam, MessagingFee({nativeFee: nativeFee, lzTokenFee: 0}), payable(to)
                ) {
                    /* Emit the stake event */
                    emit ComposerStake(sendParam.dstEid, to, depositAmount, susdaiAmount);
                } catch (bytes memory reason) {
                    /* Transfer the staked USDai to recipient */
                    IERC20(address(_stakedUsdai)).transfer(to, susdaiAmount);

                    /* Emit the failed action event */
                    emit ActionFailed("Send", reason);

                    return false;
                }
            }
        } catch (bytes memory reason) {
            _refund(IERC20(depositToken), to, depositAmount, "Stake", reason);

            return false;
        }

        return true;
    }

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IOUSDaiUtility
     */
    function whitelistedOAdapters(uint256 offset, uint256 count) external view returns (address[] memory) {
        /* Clamp on count */
        count = Math.min(count, _whitelistedOAdapters.length() - offset);

        /* Create arrays */
        address[] memory oAdapters_ = new address[](count);

        /* Fill array */
        for (uint256 i = offset; i < offset + count; i++) {
            oAdapters_[i - offset] = _whitelistedOAdapters.at(i);
        }

        return oAdapters_;
    }

    /*------------------------------------------------------------------------*/
    /* External API */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Incoming composed message handler
     * @param from Address of the sender
     * @param message Message
     */
    function lzCompose(
        address from,
        bytes32,
        bytes calldata message,
        address,
        bytes calldata
    ) external payable nonReentrant {
        /* Validate from address and endpoint */
        if (!_whitelistedOAdapters.contains(from) || msg.sender != _endpoint) revert InvalidAddress();

        /* Decode the message */
        uint256 amountLD = OFTComposeMsgCodec.amountLD(message);
        bytes memory composeMessage = OFTComposeMsgCodec.composeMsg(message);

        /* Decode the message */
        (ActionType actionType, bytes memory data) = abi.decode(composeMessage, (ActionType, bytes));

        /* Get the deposit token */
        address depositToken = IOFT(from).token();

        /* Decode the message based on the type */
        if (actionType == ActionType.Deposit) {
            _deposit(depositToken, amountLD, data);
        } else if (actionType == ActionType.DepositAndStake) {
            _depositAndStake(depositToken, amountLD, data);
        } else if (actionType == ActionType.QueuedDeposit) {
            _queuedDeposit(depositToken, amountLD, data, OFTComposeMsgCodec.srcEid(message));
        } else if (actionType == ActionType.Stake) {
            _stake(depositToken, amountLD, data);
        } else {
            revert UnknownAction();
        }
    }

    /**
     * @inheritdoc IOUSDaiUtility
     */
    function localCompose(
        ActionType actionType,
        address depositToken,
        uint256 depositAmount,
        bytes memory data
    ) external payable nonReentrant {
        /* Transfer the deposit token to the utility */
        IERC20(depositToken).transferFrom(msg.sender, address(this), depositAmount);

        if (actionType == ActionType.Deposit) {
            if (!_deposit(depositToken, depositAmount, data)) revert DepositFailed();
        } else if (actionType == ActionType.DepositAndStake) {
            if (!_depositAndStake(depositToken, depositAmount, data)) revert DepositAndStakeFailed();
        } else if (actionType == ActionType.QueuedDeposit) {
            if (!_queuedDeposit(depositToken, depositAmount, data, 0)) revert QueuedDepositFailed();
        } else if (actionType == ActionType.Stake) {
            if (!_stake(depositToken, depositAmount, data)) revert StakeFailed();
        } else {
            revert UnknownAction();
        }
    }

    /**
     * @notice Receive ETH
     */
    receive() external payable {}

    /*------------------------------------------------------------------------*/
    /* Permissioned API */
    /*------------------------------------------------------------------------*/

    /**
     * @inheritdoc IOUSDaiUtility
     */
    function addWhitelistedOAdapters(
        address[] memory oAdapters
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < oAdapters.length; i++) {
            _whitelistedOAdapters.add(oAdapters[i]);
        }

        /* Emit whitelisted OAdapters added event */
        emit WhitelistedOAdaptersAdded(oAdapters);
    }

    /**
     * @inheritdoc IOUSDaiUtility
     */
    function removeWhitelistedOAdapters(
        address[] memory oAdapters
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < oAdapters.length; i++) {
            _whitelistedOAdapters.remove(oAdapters[i]);
        }

        /* Emit whitelisted OAdapters removed event */
        emit WhitelistedOAdaptersRemoved(oAdapters);
    }

    /**
     * @inheritdoc IOUSDaiUtility
     */
    function rescue(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).transfer(to, amount);
    }
}
