// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {USDai} from "src/USDai.sol";
import {Deployer} from "./utils/Deployer.s.sol";

contract UpgradeUSDai is Deployer {
    function run() public broadcast useDeployment returns (address) {
        // Deploy USDai implemetation
        USDai USDaiImpl = new USDai(
            USDai(_deployment.USDai).baseToken(),
            _deployment.baseYieldEscrow,
            _deployment.stakedUSDai,
            _deployment.oAdapterUSDai
        );
        console.log("USDai implementation", address(USDaiImpl));

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(_deployment.USDai, ERC1967Utils.ADMIN_SLOT))));

        if (Ownable(proxyAdmin).owner() == msg.sender) {
            /* Upgrade Proxy */
            ProxyAdmin(proxyAdmin).upgradeAndCall(
                ITransparentUpgradeableProxy(_deployment.USDai), address(USDaiImpl), ""
            );
            console.log("Upgraded proxy %s implementation to: %s\n", _deployment.USDai, address(USDaiImpl));
        } else {
            console.log("\nUpgrade calldata");
            console.log("Target:   %s", proxyAdmin);
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(
                    ProxyAdmin.upgradeAndCall.selector,
                    ITransparentUpgradeableProxy(_deployment.USDai),
                    address(USDaiImpl),
                    ""
                )
            );
        }

        return address(USDaiImpl);
    }
}
