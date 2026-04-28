// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {UniswapV3SwapAdapter} from "src/swapAdapters/UniswapV3SwapAdapter.sol";
import {ChainlinkPriceOracle} from "src/oracles/ChainlinkPriceOracle.sol";
import {USDai} from "src/USDai.sol";
import {StakedUSDai} from "src/StakedUSDai.sol";
import {Deployer} from "./utils/Deployer.s.sol";

contract DeployTestEnvironment is Deployer {
    function run(
        address baseToken,
        address swapRouter,
        address sequencerUptimeFeed,
        address baseTokenPriceFeed,
        address loanRouter,
        address[] calldata tokens,
        address[] calldata priceFeeds
    ) public broadcast useDeployment returns (address, address, address, address) {
        // Deploy UniswapV3SwapAdapter
        UniswapV3SwapAdapter swapAdapter = new UniswapV3SwapAdapter(baseToken, swapRouter, tokens);
        console.log("UniswapV3SwapAdapter", address(swapAdapter));

        // Deploy ChainlinkPriceOracle
        ChainlinkPriceOracle priceOracle =
            new ChainlinkPriceOracle(sequencerUptimeFeed, baseTokenPriceFeed, tokens, priceFeeds, msg.sender);
        console.log("ChainlinkPriceOracle", address(priceOracle));

        // Deploy USDai implemetation
        USDai USDaiImpl = new USDai(
            address(swapAdapter), _deployment.baseYieldEscrow, _deployment.stakedUSDai, _deployment.oAdapterUSDai
        );
        console.log("USDai implementation", address(USDaiImpl));

        // Deploy USDai proxy
        TransparentUpgradeableProxy USDai_ = new TransparentUpgradeableProxy(
            address(USDaiImpl), msg.sender, abi.encodeWithSignature("initialize(address)", msg.sender)
        );
        console.log("USDai proxy", address(USDai_));

        // Deploy StakedUSDai
        StakedUSDai stakedUSDaiImpl = new StakedUSDai(
            address(USDai_),
            address(priceOracle),
            loanRouter,
            msg.sender,
            uint64(block.timestamp),
            100,
            100,
            _deployment.oAdapterStakedUSDai
        );
        console.log("StakedUSDai implementation", address(stakedUSDaiImpl));

        // Deploy StakedUSDai proxy
        TransparentUpgradeableProxy stakedUSDai = new TransparentUpgradeableProxy(
            address(stakedUSDaiImpl), msg.sender, abi.encodeWithSignature("initialize(address)", msg.sender)
        );
        console.log("StakedUSDai proxy", address(stakedUSDai));

        // Grant roles
        IAccessControl(address(swapAdapter)).grantRole(keccak256("USDAI_ROLE"), address(USDai_));

        // Log deployment
        _deployment.swapAdapter = address(swapAdapter);
        _deployment.priceOracle = address(priceOracle);
        _deployment.USDai = address(USDai_);
        _deployment.stakedUSDai = address(stakedUSDai);

        return (address(swapAdapter), address(priceOracle), address(USDai_), address(stakedUSDai));
    }
}
