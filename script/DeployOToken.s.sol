// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import {OToken} from "src/omnichain/OToken.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract DeployOToken is Deployer {
    function run(
        address oAdapter,
        string memory name,
        string memory symbol
    ) public broadcast useDeployment returns (address) {
        // Deploy OToken implementation
        OToken otokenImpl = new OToken(oAdapter);
        console.log("OToken implementation", address(otokenImpl));

        // Deploy OToken proxy
        TransparentUpgradeableProxy otoken = new TransparentUpgradeableProxy(
            address(otokenImpl), msg.sender, abi.encodeWithSignature("initialize(string,string)", name, symbol)
        );
        console.log("OToken proxy", address(otoken));

        if (Strings.equal(symbol, "USDai")) {
            _deployment.oTokenUSDai = address(otoken);
        } else if (Strings.equal(symbol, "StakedUSDai")) {
            _deployment.oTokenStakedUSDai = address(otoken);
        }

        return (address(otoken));
    }
}
