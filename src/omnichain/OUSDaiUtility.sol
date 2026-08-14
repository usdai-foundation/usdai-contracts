// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroComposer.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

import "../interfaces/IOUSDaiUtility.sol";
import "../interfaces/IUSDai.sol";
import "../interfaces/IStakedUSDai.sol";

/**
 * @title Omnichain USDai Utility
 * @author USD.AI Foundation
 */
contract OUSDaiUtility is ILayerZeroComposer, ReentrancyGuardUpgradeable, IOUSDaiUtility {
    using SafeERC20 for IERC20;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Implementation version
     */
    string public constant IMPLEMENTATION_VERSION = "2.0";

    /*------------------------------------------------------------------------*/
    /* Immutable state */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Admin address
     */
    address internal immutable _admin;

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
     * @notice USDai base token
     */
    IERC20 internal immutable _baseToken;

    /**
     * @notice USDai base token adapter
     */
    IOFT internal immutable _baseTokenOAdapter;

    /*------------------------------------------------------------------------*/
    /* Constructor */
    /*------------------------------------------------------------------------*/

    /**
     * @notice OUSDaiUtility Constructor
     * @param admin_ Admin address
     * @param endpoint_ LayerZero endpoint
     * @param usdai_ USDai contract
     * @param stakedUsdai_ StakedUSDai contract
     * @param usdaiOAdapter_ USDai omnichain adapter
     * @param stakedUsdaiOAdapter_ StakedUSDai omnichain adapter
     * @param baseTokenOAdapter_ Base token omnichain adapter
     */
    constructor(
        address admin_,
        address endpoint_,
        address usdai_,
        address stakedUsdai_,
        address usdaiOAdapter_,
        address stakedUsdaiOAdapter_,
        address baseTokenOAdapter_
    ) {
        _disableInitializers();

        _admin = admin_;
        _endpoint = endpoint_;
        _usdai = IUSDai(usdai_);
        _stakedUsdai = IStakedUSDai(stakedUsdai_);
        _baseToken = IERC20(_usdai.baseToken());
        _baseTokenOAdapter = IOFT(baseTokenOAdapter_);
        _usdaiOAdapter = IOFT(usdaiOAdapter_);
        _stakedUsdaiOAdapter = IOFT(stakedUsdaiOAdapter_);
    }

    /*------------------------------------------------------------------------*/
    /* Initialization */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Initializer
     */
    function initialize() external initializer {
        __ReentrancyGuard_init();
    }

    /*------------------------------------------------------------------------*/
    /* Modifiers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Validate the admin
     */
    modifier onlyAdmin() {
        if (msg.sender != _admin) revert InvalidAddress();
        _;
    }

    /*------------------------------------------------------------------------*/
    /* Internal helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Validate the OAdapter
     * @param oAdapter OAdapter to validate
     */
    function _validateOAdapter(
        address oAdapter
    ) internal view {
        if (oAdapter != address(_usdaiOAdapter) && oAdapter != address(_baseTokenOAdapter)) {
            revert InvalidAddress();
        }
    }

    /**
     * @notice Refund token and ETH for valid recipients
     * @param token Token
     * @param to Recipient address
     * @param amount Amount
     * @param action Action that failed
     * @param reason Reason for action failure
     */
    function _refund(IERC20 token, address to, uint256 amount, string memory action, bytes memory reason) internal {
        /* Check recipient is a non-zero address */
        if (to != address(0)) {
            /* Transfer token if recipient is not blacklisted (for USDai and sUSDai) */
            if (
                (address(token) != address(_usdai) && address(token) != address(_stakedUsdai))
                    || !_usdai.isBlacklisted(to)
            ) {
                token.transfer(to, amount);
            }

            /* Refund the msg.value */
            (bool success,) = payable(to).call{value: msg.value}("");
            success;
        }

        /* Emit the failed action event */
        emit ActionFailed(action, reason);
    }

    /**
     * @notice Deposit USDai
     * @dev refundTo must be able to receive token and ETH in case of action failure
     * @param depositToken Deposit token (must be USDai base token)
     * @param depositAmount Deposit token amount
     * @param data Additional compose data
     * @return success True if the deposit was successful, false otherwise
     */
    function _deposit(address depositToken, uint256 depositAmount, bytes memory data) internal returns (bool) {
        /* Decode the message */
        (SendParam memory sendParam, address refundTo, uint256 nativeFee) =
            abi.decode(data, (SendParam, address, uint256));

        /* Get the destination address */
        address to = address(uint160(uint256(sendParam.to)));

        /* Validate the deposit token is USDai's base token, recipient is not blacklisted, and sufficient native fee is
        provided */
        if (depositToken != address(_baseToken)) {
            _refund(IERC20(depositToken), refundTo, depositAmount, "Deposit", "Invalid deposit token");

            return false;
        } else if (_usdai.isBlacklisted(to)) {
            _refund(IERC20(depositToken), refundTo, depositAmount, "Deposit", "Blacklisted recipient");

            return false;
        } else if (msg.value < nativeFee) {
            revert InsufficientNativeFee();
        }

        /* Approve the USDai contract to spend the deposit token */
        IERC20(depositToken).forceApprove(address(_usdai), depositAmount);

        try _usdai.deposit(depositAmount, address(this)) returns (uint256 usdaiAmount) {
            /* Handle local vs cross-chain destination */
            if (sendParam.dstEid == 0) {
                /* Transfer the USDai to recipient */
                _usdai.transfer(to, usdaiAmount);

                /* Emit the deposit event */
                emit ComposerDeposit(sendParam.dstEid, depositToken, sendParam.to, depositAmount, usdaiAmount);
            } else {
                /* Update the sendParam with the USDai amount */
                sendParam.amountLD = usdaiAmount;

                /* Send the USDai to destination chain */
                try _usdaiOAdapter.send{value: nativeFee}(
                    sendParam, MessagingFee({nativeFee: nativeFee, lzTokenFee: 0}), payable(refundTo)
                ) {
                    /* Emit the deposit event */
                    emit ComposerDeposit(sendParam.dstEid, depositToken, sendParam.to, depositAmount, usdaiAmount);
                } catch (bytes memory reason) {
                    /* Transfer the USDai to the refund recipient */
                    _refund(_usdai, refundTo, usdaiAmount, "Send", reason);

                    return false;
                }
            }
        } catch (bytes memory reason) {
            _refund(IERC20(depositToken), refundTo, depositAmount, "Deposit", reason);

            return false;
        }

        return true;
    }

    /**
     * @notice Withdraw USDai
     * @dev refundTo must be able to receive token and ETH in case of action failure
     * @param receivedToken Received token (must be USDai)
     * @param receivedAmount Received amount
     * @param data Additional compose data
     * @return success True if the withdraw was successful, false otherwise
     */
    function _withdraw(address receivedToken, uint256 receivedAmount, bytes memory data) internal returns (bool) {
        /* Decode the message */
        (SendParam memory sendParam, address refundTo, uint256 nativeFee) =
            abi.decode(data, (SendParam, address, uint256));

        /* Get the destination address */
        address to = address(uint160(uint256(sendParam.to)));

        /* Validate the received token is USDai, recipient is not blacklisted, and sufficient native fee is provided */
        if (receivedToken != address(_usdai)) {
            _refund(IERC20(receivedToken), refundTo, receivedAmount, "Withdraw", "Invalid received token");

            return false;
        } else if (_usdai.isBlacklisted(to)) {
            _refund(IERC20(receivedToken), refundTo, receivedAmount, "Withdraw", "Blacklisted recipient");

            return false;
        } else if (msg.value < nativeFee) {
            revert InsufficientNativeFee();
        }

        try _usdai.withdraw(receivedAmount, address(this)) returns (uint256 withdrawAmount) {
            /* Handle local vs cross-chain destination */
            if (sendParam.dstEid == 0) {
                /* Transfer the base token to recipient */
                _baseToken.transfer(to, withdrawAmount);

                /* Emit the withdraw event */
                emit ComposerWithdraw(
                    sendParam.dstEid, address(_baseToken), sendParam.to, receivedAmount, withdrawAmount
                );
            } else {
                /* Update the sendParam with the withdraw amount */
                sendParam.amountLD = withdrawAmount;

                /* Approve if OAdapter is a lockbox adapter */
                if (_baseTokenOAdapter.approvalRequired()) {
                    _baseToken.forceApprove(address(_baseTokenOAdapter), withdrawAmount);
                }

                /* Send the base token to destination chain */
                try _baseTokenOAdapter.send{value: nativeFee}(
                    sendParam, MessagingFee({nativeFee: nativeFee, lzTokenFee: 0}), payable(refundTo)
                ) {
                    /* Emit the withdraw event */
                    emit ComposerWithdraw(
                        sendParam.dstEid, address(_baseToken), sendParam.to, receivedAmount, withdrawAmount
                    );
                } catch (bytes memory reason) {
                    /* Transfer the base token to the refund recipient */
                    _refund(_baseToken, refundTo, withdrawAmount, "Send", reason);

                    return false;
                }
            }
        } catch (bytes memory reason) {
            _refund(IERC20(receivedToken), refundTo, receivedAmount, "Withdraw", reason);

            return false;
        }

        return true;
    }

    /**
     * @notice Deposit and stake the USDai
     * @dev refundTo must be able to receive token and ETH in case of action failure
     * @param depositToken Deposit token (must be USDai base token)
     * @param depositAmount Deposit token amount
     * @param data Additional compose data
     * @return success True if the deposit and stake was successful, false otherwise
     */
    function _depositAndStake(address depositToken, uint256 depositAmount, bytes memory data) internal returns (bool) {
        /* Decode the message */
        (uint256 minShares, SendParam memory sendParam, address refundTo, uint256 nativeFee) =
            abi.decode(data, (uint256, SendParam, address, uint256));

        /* Get the destination address */
        address to = address(uint160(uint256(sendParam.to)));

        /* Validate the deposit token is USDai's base token, recipient is not blacklisted, and sufficient native fee is
        provided */
        if (depositToken != address(_baseToken)) {
            _refund(IERC20(depositToken), refundTo, depositAmount, "DepositAndStake", "Invalid deposit token");

            return false;
        } else if (_usdai.isBlacklisted(to)) {
            _refund(IERC20(depositToken), refundTo, depositAmount, "DepositAndStake", "Blacklisted recipient");

            return false;
        } else if (msg.value < nativeFee) {
            revert InsufficientNativeFee();
        }

        /* Approve the USDai contract to spend the deposit token */
        IERC20(depositToken).forceApprove(address(_usdai), depositAmount);

        try _usdai.deposit(depositAmount, address(this)) returns (uint256 usdaiAmount) {
            /* Approve the staked USDai contract to spend the USDai */
            _usdai.approve(address(_stakedUsdai), usdaiAmount);

            try _stakedUsdai.deposit(usdaiAmount, address(this), minShares) returns (uint256 susdaiAmount) {
                /* Handle local vs cross-chain destination */
                if (sendParam.dstEid == 0) {
                    /* Transfer the staked USDai to recipient */
                    IERC20(address(_stakedUsdai)).transfer(to, susdaiAmount);

                    /* Emit the deposit and stake event */
                    emit ComposerDepositAndStake(
                        sendParam.dstEid, depositToken, sendParam.to, depositAmount, usdaiAmount, susdaiAmount
                    );
                } else {
                    /* Update the sendParam with the staked USDai amount */
                    sendParam.amountLD = susdaiAmount;

                    /* Send the staked USDai to destination chain */
                    try _stakedUsdaiOAdapter.send{value: nativeFee}(
                        sendParam, MessagingFee({nativeFee: nativeFee, lzTokenFee: 0}), payable(refundTo)
                    ) {
                        /* Emit the deposit and stake event */
                        emit ComposerDepositAndStake(
                            sendParam.dstEid, depositToken, sendParam.to, depositAmount, usdaiAmount, susdaiAmount
                        );
                    } catch (bytes memory reason) {
                        /* Transfer the staked USDai to the refund recipient */
                        _refund(IERC20(address(_stakedUsdai)), refundTo, susdaiAmount, "Send", reason);

                        return false;
                    }
                }
            } catch (bytes memory reason) {
                _refund(_usdai, refundTo, usdaiAmount, "Stake", reason);

                return false;
            }
        } catch (bytes memory reason) {
            _refund(IERC20(depositToken), refundTo, depositAmount, "Deposit", reason);

            return false;
        }

        return true;
    }

    /**
     * @notice Stake USDai
     * @dev refundTo must be able to receive token and ETH in case of action failure
     * @param depositToken Deposit token (must be USDai)
     * @param depositAmount Deposit token amount
     * @param data Additional compose data
     * @return success True if the stake was successful, false otherwise
     */
    function _stake(address depositToken, uint256 depositAmount, bytes memory data) internal returns (bool) {
        /* Decode the message */
        (uint256 minShares, SendParam memory sendParam, address refundTo, uint256 nativeFee) =
            abi.decode(data, (uint256, SendParam, address, uint256));

        /* Get the destination address */
        address to = address(uint160(uint256(sendParam.to)));

        /* Validate the deposit token is USDai, recipient is not blacklisted, and sufficient native fee is provided */
        if (depositToken != address(_usdai)) {
            _refund(IERC20(depositToken), refundTo, depositAmount, "Stake", "Invalid deposit token");

            return false;
        } else if (_usdai.isBlacklisted(to)) {
            _refund(IERC20(depositToken), refundTo, depositAmount, "Stake", "Blacklisted recipient");

            return false;
        } else if (msg.value < nativeFee) {
            revert InsufficientNativeFee();
        }

        /* Approve the staked USDai contract to spend the USDai */
        _usdai.approve(address(_stakedUsdai), depositAmount);

        try _stakedUsdai.deposit(depositAmount, address(this), minShares) returns (uint256 susdaiAmount) {
            /* Handle local vs cross-chain destination */
            if (sendParam.dstEid == 0) {
                /* Transfer the staked USDai to recipient */
                IERC20(address(_stakedUsdai)).transfer(to, susdaiAmount);

                /* Emit the stake event */
                emit ComposerStake(sendParam.dstEid, sendParam.to, depositAmount, susdaiAmount);
            } else {
                /* Update the sendParam with the staked USDai amount */
                sendParam.amountLD = susdaiAmount;

                /* Send the staked USDai to destination chain */
                try _stakedUsdaiOAdapter.send{value: nativeFee}(
                    sendParam, MessagingFee({nativeFee: nativeFee, lzTokenFee: 0}), payable(refundTo)
                ) {
                    /* Emit the stake event */
                    emit ComposerStake(sendParam.dstEid, sendParam.to, depositAmount, susdaiAmount);
                } catch (bytes memory reason) {
                    /* Transfer the staked USDai to the refund recipient */
                    _refund(IERC20(address(_stakedUsdai)), refundTo, susdaiAmount, "Send", reason);

                    return false;
                }
            }
        } catch (bytes memory reason) {
            _refund(IERC20(depositToken), refundTo, depositAmount, "Stake", reason);

            return false;
        }

        return true;
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
        /* Validate endpoint */
        if (msg.sender != _endpoint) revert InvalidAddress();

        /* Validate the OAdapter */
        _validateOAdapter(from);

        /* Decode the message */
        uint256 amountLD = OFTComposeMsgCodec.amountLD(message);
        bytes memory composeMessage = OFTComposeMsgCodec.composeMsg(message);

        /* Decode the compose message */
        (ActionType actionType, bytes memory data) = abi.decode(composeMessage, (ActionType, bytes));

        /* Get the deposit token */
        address depositToken = IOFT(from).token();

        /* Decode the message based on the type */
        if (actionType == ActionType.Deposit) {
            _deposit(depositToken, amountLD, data);
        } else if (actionType == ActionType.DepositAndStake) {
            _depositAndStake(depositToken, amountLD, data);
        } else if (actionType == ActionType.Stake) {
            _stake(depositToken, amountLD, data);
        } else if (actionType == ActionType.Withdraw) {
            _withdraw(depositToken, amountLD, data);
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
        } else if (actionType == ActionType.Stake) {
            if (!_stake(depositToken, depositAmount, data)) revert StakeFailed();
        } else if (actionType == ActionType.Withdraw) {
            if (!_withdraw(depositToken, depositAmount, data)) revert WithdrawFailed();
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
    function rescueERC20(address token, address to, uint256 amount) external onlyAdmin {
        IERC20(token).transfer(to, amount);
    }

    /**
     * @inheritdoc IOUSDaiUtility
     */
    function rescueETH(address to, uint256 amount) external onlyAdmin {
        (bool success,) = payable(to).call{value: amount}("");
        require(success);
    }
}
