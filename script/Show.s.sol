// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract Show is Deployer {
    function run() public {
        console.log("Printing deployments\n");
        console.log("Network: %s\n", _chainIdToNetwork[block.chainid]);

        /* Deserialize */
        _deserialize();

        console.log("GenesisTimestamp:      %d", _deployment.genesisTimestamp);
        console.log("");
        console.log("USDai:                 %s", _deployment.USDai);
        console.log("StakedUSDai:           %s", _deployment.stakedUSDai);
        console.log("BaseYieldEscrow:       %s", _deployment.baseYieldEscrow);
        console.log("");
        console.log("OAdapterUSDai:         %s", _deployment.oAdapterUSDai);
        console.log("OAdapterStakedUSDai:   %s", _deployment.oAdapterStakedUSDai);
        console.log("");
        console.log("OTokenUSDai:           %s", _deployment.oTokenUSDai);
        console.log("OTokenStakedUSDai:     %s", _deployment.oTokenStakedUSDai);
        console.log("");
        console.log("OUSDaiUtility:         %s", _deployment.oUSDaiUtility);

        console.log("Printing deployments completed");
    }
}
