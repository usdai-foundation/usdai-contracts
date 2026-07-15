// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {OUSDaiUtility} from "src/omnichain/OUSDaiUtility.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract DeployOUSDaiUtility is Deployer {
    function run(
        address deployer,
        address lzEndpoint,
        address[] memory oAdapters,
        address multisig
    ) public broadcast useDeployment returns (address) {
        // Deploy OUSDaiUtility implementation
        OUSDaiUtility oUSDaiUtilityImpl = new OUSDaiUtility(
            lzEndpoint,
            _deployment.USDai,
            _deployment.stakedUSDai,
            _deployment.oAdapterUSDai,
            _deployment.oAdapterStakedUSDai
        );
        console.log("OUSDaiUtility implementation", address(oUSDaiUtilityImpl));

        // Deploy OUSDaiUtility proxy
        TransparentUpgradeableProxy oUSDaiUtility = new TransparentUpgradeableProxy(
            address(oUSDaiUtilityImpl),
            deployer,
            abi.encodeWithSelector(OUSDaiUtility.initialize.selector, multisig, oAdapters)
        );
        console.log("OUSDaiUtility proxy", address(oUSDaiUtility));

        _deployment.oUSDaiUtility = address(oUSDaiUtility);

        return (address(oUSDaiUtility));
    }
}
