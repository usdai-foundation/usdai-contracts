// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {OUSDaiUtility} from "src/omnichain/OUSDaiUtility.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract UpgradeOUSDaiUtility is Deployer {
    function run(
        address lzEndpoint
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

        /* Lookup proxy admin */
        address proxyAdmin = address(uint160(uint256(vm.load(_deployment.oUSDaiUtility, ERC1967Utils.ADMIN_SLOT))));

        if (Ownable(proxyAdmin).owner() == msg.sender) {
            /* Upgrade Proxy */
            ProxyAdmin(proxyAdmin).upgradeAndCall(
                ITransparentUpgradeableProxy(_deployment.oUSDaiUtility), address(oUSDaiUtilityImpl), ""
            );
            console.log(
                "Upgraded proxy %s implementation to: %s\n", _deployment.oUSDaiUtility, address(oUSDaiUtilityImpl)
            );
        } else {
            console.log("\nUpgrade calldata");
            console.log("Target:   %s", proxyAdmin);
            console.log("Calldata:");
            console.logBytes(
                abi.encodeWithSelector(
                    ProxyAdmin.upgradeAndCall.selector,
                    ITransparentUpgradeableProxy(_deployment.oUSDaiUtility),
                    address(oUSDaiUtilityImpl),
                    ""
                )
            );
        }

        return address(oUSDaiUtilityImpl);
    }
}
