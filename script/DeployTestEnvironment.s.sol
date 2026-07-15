// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {USDai} from "src/USDai.sol";
import {StakedUSDai} from "src/StakedUSDai.sol";
import {Deployer} from "./utils/Deployer.s.sol";

contract DeployTestEnvironment is Deployer {
    function run(address baseToken, address loanRouterV2) public broadcast useDeployment returns (address, address) {
        // Deploy USDai implemetation
        USDai USDaiImpl =
            new USDai(baseToken, _deployment.baseYieldEscrow, _deployment.stakedUSDai, _deployment.oAdapterUSDai);
        console.log("USDai implementation", address(USDaiImpl));

        // Deploy USDai proxy
        TransparentUpgradeableProxy USDai_ = new TransparentUpgradeableProxy(
            address(USDaiImpl), msg.sender, abi.encodeWithSignature("initialize(address)", msg.sender)
        );
        console.log("USDai proxy", address(USDai_));

        // Deploy StakedUSDai
        StakedUSDai stakedUSDaiImpl = new StakedUSDai(
            address(USDai_),
            loanRouterV2,
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

        // Log deployment

        _deployment.USDai = address(USDai_);
        _deployment.stakedUSDai = address(stakedUSDai);

        return (address(USDai_), address(stakedUSDai));
    }
}
