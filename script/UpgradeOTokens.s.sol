// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {OToken} from "src/omnichain/OToken.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract UpgradeOTokens is Deployer {
    function run() public broadcast useDeployment returns (address, address) {
        if (_deployment.oTokenUSDai == address(0)) revert MissingDependency();
        if (_deployment.oAdapterUSDai == address(0)) revert MissingDependency();
        if (_deployment.oTokenStakedUSDai == address(0)) revert MissingDependency();
        if (_deployment.oAdapterStakedUSDai == address(0)) revert MissingDependency();

        // Deploy OToken implementations
        OToken oTokenUSDaiImpl = new OToken(_deployment.oAdapterUSDai);
        console.log("USDai OToken implementation", address(oTokenUSDaiImpl));

        OToken oTokenStakedUSDaiImpl = new OToken(_deployment.oAdapterStakedUSDai);
        console.log("Staked USDai OToken implementation", address(oTokenStakedUSDaiImpl));

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(_deployment.oTokenUSDai, ERC1967Utils.ADMIN_SLOT))));

        if (Ownable(proxyAdmin).owner() == msg.sender) {
            /* Upgrade Proxy */
            ProxyAdmin(proxyAdmin).upgradeAndCall(
                ITransparentUpgradeableProxy(_deployment.oTokenUSDai), address(oTokenUSDaiImpl), ""
            );
            console.log("Upgraded proxy %s implementation to: %s\n", _deployment.oTokenUSDai, address(oTokenUSDaiImpl));
        } else {
            console.log("\nUpgrade calldata");
            console.log("Target:   %s", proxyAdmin);
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(
                    ProxyAdmin.upgradeAndCall.selector,
                    ITransparentUpgradeableProxy(_deployment.oTokenUSDai),
                    address(oTokenUSDaiImpl),
                    ""
                )
            );
        }

        /* Lookup proxy admin */
        proxyAdmin = address(uint160(uint256(vm.load(_deployment.oTokenStakedUSDai, ERC1967Utils.ADMIN_SLOT))));

        if (Ownable(proxyAdmin).owner() == msg.sender) {
            /* Upgrade Proxy */
            ProxyAdmin(proxyAdmin).upgradeAndCall(
                ITransparentUpgradeableProxy(_deployment.oTokenStakedUSDai), address(oTokenStakedUSDaiImpl), ""
            );
            console.log(
                "Upgraded proxy %s implementation to: %s\n",
                _deployment.oTokenStakedUSDai,
                address(oTokenStakedUSDaiImpl)
            );
        } else {
            console.log("\nUpgrade calldata");
            console.log("Target:   %s", proxyAdmin);
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(
                    ProxyAdmin.upgradeAndCall.selector,
                    ITransparentUpgradeableProxy(_deployment.oTokenStakedUSDai),
                    address(oTokenStakedUSDaiImpl),
                    ""
                )
            );
        }

        return (address(oTokenUSDaiImpl), address(oTokenStakedUSDaiImpl));
    }
}
