// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {OmnichainBaseTest} from "./Base.t.sol";

import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {
    SendParam,
    MessagingFee,
    OFTReceipt,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";

import {IOUSDaiUtility} from "src/interfaces/IOUSDaiUtility.sol";
import {OUSDaiUtility} from "src/omnichain/OUSDaiUtility.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Stake Test Suite
 * @notice Test suite for OUSDaiUtility staking functionality
 * @dev This test suite covers local staking operations where users:
 *      1. Have USDai tokens (obtained through deposit)
 *      2. Stake USDai to receive staked USDai tokens
 *      3. Handle various failure scenarios
 *
 *      The tests focus on the ActionType.Stake functionality in OUSDaiUtility._stake()
 *      Cross-chain staking tests are omitted due to complexity of proper USDai token setup
 *      across multiple chains, but the core staking logic is thoroughly tested locally.
 */
contract OUSDaiUtilityStakeTest is OmnichainBaseTest {
    using OptionsBuilder for bytes;

    // Test stake USDai - user starts with USDai on home and wants staked tokens sent to away chain
    function test__OUSDaiUtilityStake() public {
        vm.startPrank(user);

        // First, user needs USDai on home chain (simulate they got it from previous deposit)
        // Deposit USD to get USDai on home chain
        usdtHomeToken.approve(address(usdai), initialBalance);
        uint256 usdaiAmount = usdai.deposit(address(usdtHomeToken), initialBalance, initialBalance - 1e6, user);

        // LZ receive option for sending staked USDai to away chain
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Send param for Staked USDai from home to away
        SendParam memory stakedUsdaiSendParam = SendParam(
            stakedUsdaiAwayEid,
            addressToBytes32(user),
            usdaiAmount, // will be updated with actual staked amount
            /// forge-lint: disable-next-line
            ((usdaiAmount - 1e6) / 10 ** 12) * 10 ** 12,
            receiveOptions,
            "",
            ""
        );

        // Quote the fee for sending Staked USDai from home to away
        MessagingFee memory fee = stakedUsdaiHomeOAdapter.quoteSend(stakedUsdaiSendParam, false);

        // Data for local staking
        bytes memory data = abi.encode(usdaiAmount - 1e6, stakedUsdaiSendParam, fee.nativeFee);

        // Approve the USDai utility to spend the USDai
        usdai.approve(address(oUsdaiUtility), usdaiAmount);

        // Stake the USDai locally and send staked tokens to away chain
        oUsdaiUtility.localCompose{value: fee.nativeFee}(
            IOUSDaiUtility.ActionType.Stake, address(usdai), usdaiAmount, data
        );

        // Verify that the staked USDai was sent to away chain
        verifyPackets(stakedUsdaiAwayEid, addressToBytes32(address(stakedUsdaiAwayOAdapter)));

        // Assert that the Staked USDai away token was minted to the user
        /// forge-lint: disable-next-line
        assertEq(stakedUsdaiAwayToken.balanceOf(user), ((usdaiAmount - 1e6) / 10 ** 12) * 10 ** 12);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityStake_LocalDestination() public {
        vm.startPrank(user);

        // First, user needs USDai on home chain (simulate they got it from previous deposit)
        // Deposit USD to get USDai on home chain
        usdtHomeToken.approve(address(usdai), initialBalance);
        uint256 usdaiAmount = usdai.deposit(address(usdtHomeToken), initialBalance, initialBalance - 1e6, user);

        // Send param for Staked USDai - local destination (stays on home chain)
        SendParam memory stakedUsdaiSendParam = SendParam(0, addressToBytes32(user), 0, 0, "", "", "");

        // Data for local staking with local destination
        bytes memory data = abi.encode(usdaiAmount - 1e6, stakedUsdaiSendParam, 0);

        // Approve the USDai utility to spend the USDai
        usdai.approve(address(oUsdaiUtility), usdaiAmount);

        // Stake the USDai locally (no cross-chain send)
        oUsdaiUtility.localCompose(IOUSDaiUtility.ActionType.Stake, address(usdai), usdaiAmount, data);

        // Assert that the staked USDai home token was minted to the user
        assertEq(IERC20(address(stakedUsdai)).balanceOf(user), usdaiAmount - 1e6);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityStake_LocalSource_LocalDestination() public {
        vm.startPrank(user);

        // First deposit USD to get USDai
        usdtHomeToken.approve(address(usdai), initialBalance);
        uint256 usdaiAmount = usdai.deposit(address(usdtHomeToken), initialBalance, initialBalance - 1e6, user);

        // Send param
        SendParam memory stakedUsdaiSendParam = SendParam(0, addressToBytes32(user), 0, 0, "", "", "");

        // Data
        bytes memory data = abi.encode(usdaiAmount - 1e6, stakedUsdaiSendParam, 0);

        // Approve the USDAI utility to spend the USDai
        usdai.approve(address(oUsdaiUtility), usdaiAmount);

        // Stake the USDai
        oUsdaiUtility.localCompose(IOUSDaiUtility.ActionType.Stake, address(usdai), usdaiAmount, data);

        // Assert that the staked USDai home token was minted to the user
        assertEq(IERC20(address(stakedUsdai)).balanceOf(user), usdaiAmount - 1e6);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityStake_InvalidStake_LocalSource() public {
        vm.startPrank(user);

        // First deposit USD to get USDai
        usdtHomeToken.approve(address(usdai), initialBalance);
        uint256 usdaiAmount = usdai.deposit(address(usdtHomeToken), initialBalance, initialBalance - 1e6, user);

        // Send param
        SendParam memory stakedUsdaiSendParam = SendParam(0, addressToBytes32(user), 0, 0, "", "", "");

        // Data - invalid minShares (too high)
        bytes memory data = abi.encode(usdaiAmount, stakedUsdaiSendParam, 0);

        // Approve the USDAI utility to spend the USDai
        usdai.approve(address(oUsdaiUtility), usdaiAmount);

        // Stake the USDai - should revert
        vm.expectRevert(IOUSDaiUtility.StakeFailed.selector);
        oUsdaiUtility.localCompose(IOUSDaiUtility.ActionType.Stake, address(usdai), usdaiAmount, data);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityStake_InvalidDepositToken() public {
        vm.startPrank(user);

        // Send param for Staked USDai - cross-chain destination
        SendParam memory stakedUsdaiSendParam = SendParam(
            stakedUsdaiAwayEid,
            addressToBytes32(user),
            initialBalance,
            /// forge-lint: disable-next-line
            ((initialBalance - 1e6) / 10 ** 12) * 10 ** 12,
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0),
            "",
            ""
        );

        // Quote the fee for sending Staked USDai from home to away
        MessagingFee memory fee = stakedUsdaiHomeOAdapter.quoteSend(stakedUsdaiSendParam, false);

        // Data for staking with invalid token (should be USDai, but using USD instead)
        bytes memory data = abi.encode(initialBalance - 1e6, stakedUsdaiSendParam, fee.nativeFee);

        // Approve the USDai utility to spend USD (wrong token!)
        usdtHomeToken.approve(address(oUsdaiUtility), initialBalance);

        // Try to stake USD instead of USDai - should revert with StakeFailed
        vm.expectRevert(IOUSDaiUtility.StakeFailed.selector);
        oUsdaiUtility.localCompose{value: fee.nativeFee}(
            IOUSDaiUtility.ActionType.Stake, address(usdtHomeToken), initialBalance, data
        );

        vm.stopPrank();
    }

    function test__OUSDaiUtilityStake_InvalidStake() public {
        vm.startPrank(user);

        // First, user needs USDai on home chain
        usdtHomeToken.approve(address(usdai), initialBalance);
        uint256 usdaiAmount = usdai.deposit(address(usdtHomeToken), initialBalance, initialBalance - 1e6, user);

        // Send param for Staked USDai
        SendParam memory stakedUsdaiSendParam = SendParam(
            stakedUsdaiAwayEid,
            addressToBytes32(user),
            usdaiAmount,
            /// forge-lint: disable-next-line
            ((usdaiAmount - 1e6) / 10 ** 12) * 10 ** 12,
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0),
            "",
            ""
        );

        MessagingFee memory fee = stakedUsdaiHomeOAdapter.quoteSend(stakedUsdaiSendParam, false);

        // Data for staking with invalid minShares (too high - will cause staking to fail)
        bytes memory data = abi.encode(usdaiAmount, stakedUsdaiSendParam, fee.nativeFee); // minShares too high

        // Approve the USDai utility to spend the USDai
        usdai.approve(address(oUsdaiUtility), usdaiAmount);

        // Try to stake with too high minShares - should revert with StakeFailed
        vm.expectRevert(IOUSDaiUtility.StakeFailed.selector);
        oUsdaiUtility.localCompose{value: fee.nativeFee}(
            IOUSDaiUtility.ActionType.Stake, address(usdai), usdaiAmount, data
        );

        vm.stopPrank();
    }

    function test__OUSDaiUtilityStake_InvalidSend() public {
        vm.startPrank(user);

        // First, user needs USDai on home chain
        usdtHomeToken.approve(address(usdai), initialBalance);
        uint256 usdaiAmount = usdai.deposit(address(usdtHomeToken), initialBalance, initialBalance - 1e6, user);

        // Send param for Staked USDai
        SendParam memory stakedUsdaiSendParam = SendParam(
            stakedUsdaiAwayEid,
            addressToBytes32(user),
            usdaiAmount,
            /// forge-lint: disable-next-line
            ((usdaiAmount - 1e6) / 10 ** 12) * 10 ** 12,
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0),
            "",
            ""
        );

        // Data for staking with insufficient native fee (will cause send to fail)
        bytes memory data = abi.encode(usdaiAmount - 1e6, stakedUsdaiSendParam, 0); // nativeFee = 0, insufficient

        // Approve the USDai utility to spend the USDai
        usdai.approve(address(oUsdaiUtility), usdaiAmount);

        // Stake but with insufficient fee for sending - should revert with StakeFailed
        vm.expectRevert(IOUSDaiUtility.StakeFailed.selector);
        oUsdaiUtility.localCompose(IOUSDaiUtility.ActionType.Stake, address(usdai), usdaiAmount, data);

        vm.stopPrank();
    }

    function test__OUSDaiUtilityStake_FromAwayChain() public {
        vm.startPrank(user);

        // LZ receive option
        bytes memory receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Send param for USDAI home to USDAI away
        SendParam memory usdaiSendParam = SendParam(
            usdaiAwayEid,
            addressToBytes32(user),
            initialBalance, // will be set later
            /// forge-lint: disable-next-line
            (initialBalance / 10 ** 12) * 10 ** 12,
            receiveOptions,
            "",
            ""
        );

        // Quote the fee for sending USDAI from home to away
        MessagingFee memory fee = usdaiHomeOAdapter.quoteSend(usdaiSendParam, false);

        // Data
        bytes memory data = abi.encode(initialBalance, "", usdaiSendParam, fee.nativeFee);

        // Approve the USDAI utility to spend the USD
        usdtHomeToken.approve(address(oUsdaiUtility), initialBalance);

        // Deposit the USD
        oUsdaiUtility.localCompose{value: fee.nativeFee}(
            IOUSDaiUtility.ActionType.Deposit, address(usdtHomeToken), initialBalance, data
        );

        // Verify that the packets were correctly sent to the destination chain
        verifyPackets(usdaiAwayEid, addressToBytes32(address(usdaiAwayOAdapter)));

        // LZ receive option for sending USDai to home chain first
        receiveOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

        // Send param for Staked USDai from home back to away
        SendParam memory stakedUsdaiSendParam = SendParam(
            stakedUsdaiAwayEid,
            addressToBytes32(user),
            initialBalance, // will be updated with actual staked amount
            /// forge-lint: disable-next-line
            ((initialBalance - 1e6) / 10 ** 12) * 10 ** 12,
            receiveOptions,
            "",
            ""
        );

        // Quote the fee for sending Staked USDai from home to away
        MessagingFee memory stakedFee = stakedUsdaiHomeOAdapter.quoteSend(stakedUsdaiSendParam, false);

        // Compose message for USDai away to home, then stake and send staked tokens back
        bytes memory suffix = abi.encode(initialBalance - 1e6, stakedUsdaiSendParam, stakedFee.nativeFee);
        bytes memory composeMsg = abi.encode(IOUSDaiUtility.ActionType.Stake, suffix);

        // LZ composer option including fee for sending staked tokens back
        bytes memory composerOptions =
            receiveOptions.addExecutorLzComposeOption(0, 1_000_000, uint128(stakedFee.nativeFee));

        // Send param for USDai away to home
        usdaiSendParam = SendParam({
            dstEid: usdaiHomeEid,
            to: addressToBytes32(address(oUsdaiUtility)),
            amountLD: initialBalance,
            minAmountLD: initialBalance,
            extraOptions: composerOptions,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        // Quote the fee for sending USDai from away to home
        (,, OFTReceipt memory receipt) = usdaiAwayOAdapter.quoteOFT(usdaiSendParam);
        usdaiSendParam.minAmountLD = receipt.amountReceivedLD;

        MessagingFee memory usdaiFee = usdaiAwayOAdapter.quoteSend(usdaiSendParam, false);

        // Send USDai from away to home with compose message
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) =
            usdaiAwayOAdapter.send{value: usdaiFee.nativeFee}(usdaiSendParam, usdaiFee, payable(address(this)));

        // Verify that USDai was sent to home chain
        verifyPackets(usdaiHomeEid, addressToBytes32(address(usdaiHomeOAdapter)));

        // Recreate the compose message for the composer receiver
        bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
            msgReceipt.nonce,
            usdaiAwayEid,
            oftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(user), composeMsg)
        );

        vm.stopPrank();

        // Redeploy OUSDaiUtility bound to the USDai home endpoint
        OUSDaiUtility newImpl = new OUSDaiUtility(
            address(this),
            address(endpoints[usdaiHomeEid]),
            address(usdai),
            address(stakedUsdai),
            address(usdaiHomeOAdapter),
            address(stakedUsdaiHomeOAdapter),
            address(usdtHomeOAdapter)
        );
        address proxyAdmin = address(uint160(uint256(vm.load(address(oUsdaiUtility), ERC1967Utils.ADMIN_SLOT))));
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(oUsdaiUtility)),
            address(newImpl),
            "" // No additional initialization data
        );

        vm.startPrank(user);

        // Execute the compose message (this will stake and send back to away chain)
        this.lzCompose(
            usdaiHomeEid,
            address(usdaiHomeOAdapter),
            composerOptions,
            msgReceipt.guid,
            address(oUsdaiUtility),
            composerMsg_
        );

        // Verify that the staked USDai was sent back to away chain
        verifyPackets(stakedUsdaiAwayEid, addressToBytes32(address(stakedUsdaiAwayOAdapter)));

        // Assert that the Staked USDai away token was minted to the user
        /// forge-lint: disable-next-line
        assertEq(stakedUsdaiAwayToken.balanceOf(user), ((initialBalance - 1e6) / 10 ** 12) * 10 ** 12);

        vm.stopPrank();
    }
}
