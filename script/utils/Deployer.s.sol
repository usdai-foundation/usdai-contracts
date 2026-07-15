// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {stdJson} from "forge-std/StdJson.sol";
import {console2 as console} from "forge-std/console2.sol";

import {BaseScript} from "./Base.s.sol";

contract Deployer is BaseScript {
    /*--------------------------------------------------------------------------*/
    /* Errors                                                                   */
    /*--------------------------------------------------------------------------*/

    error MissingDependency();

    error AlreadyDeployed();

    error InvalidParameter();

    /*--------------------------------------------------------------------------*/
    /* Structures                                                               */
    /*--------------------------------------------------------------------------*/

    struct Deployment {
        uint64 genesisTimestamp;
        address USDai;
        address stakedUSDai;
        address baseYieldEscrow;
        address oAdapterUSDai;
        address oAdapterStakedUSDai;
        address oTokenUSDai;
        address oTokenStakedUSDai;
        address oUSDaiUtility;
    }

    /*--------------------------------------------------------------------------*/
    /* State Variables                                                          */
    /*--------------------------------------------------------------------------*/

    Deployment internal _deployment;

    /*--------------------------------------------------------------------------*/
    /* Modifier                                                                 */
    /*--------------------------------------------------------------------------*/

    /**
     * @dev Add useDeployment modifier to deployment script run() function to
     *      deserialize deployments json and make properties available to read,
     *      write and modify. Changes are re-serialized at end of script.
     */
    modifier useDeployment() {
        console.log("Using deployment\n");
        console.log("Network: %s\n", _chainIdToNetwork[block.chainid]);

        _deserialize();

        _;

        _serialize();

        console.log("Using deployment completed\n");
    }

    /*--------------------------------------------------------------------------*/
    /* Internal Helpers                                                         */
    /*--------------------------------------------------------------------------*/

    /**
     * @notice Internal helper to get deployment file path for current network
     *
     * @return Path
     */
    function _getJsonFilePath() internal view returns (string memory) {
        return string(abi.encodePacked(vm.projectRoot(), "/deployments/", _chainIdToNetwork[block.chainid], ".json"));
    }

    /**
     * @notice Internal helper to read and return json string
     *
     * @return Json string
     */
    function _getJson() internal view returns (string memory) {
        string memory path = _getJsonFilePath();

        string memory json = "{}";

        try vm.readFile(path) returns (string memory _json) {
            json = _json;
        } catch {
            console.log("No json file found at: %s\n", path);
        }

        return json;
    }

    /*--------------------------------------------------------------------------*/
    /* API                                                                      */
    /*--------------------------------------------------------------------------*/

    /**
     * @notice Serialize the _deployment storage struct
     */
    function _serialize() internal {
        /* Initialize json string */
        string memory json = "";

        json = stdJson.serialize("", "GenesisTimestamp", _deployment.genesisTimestamp);
        json = stdJson.serialize("", "USDai", _deployment.USDai);
        json = stdJson.serialize("", "StakedUSDai", _deployment.stakedUSDai);
        json = stdJson.serialize("", "BaseYieldEscrow", _deployment.baseYieldEscrow);
        json = stdJson.serialize("", "OAdapterUSDai", _deployment.oAdapterUSDai);
        json = stdJson.serialize("", "OAdapterStakedUSDai", _deployment.oAdapterStakedUSDai);
        json = stdJson.serialize("", "OTokenUSDai", _deployment.oTokenUSDai);
        json = stdJson.serialize("", "OTokenStakedUSDai", _deployment.oTokenStakedUSDai);
        json = stdJson.serialize("", "OUSDaiUtility", _deployment.oUSDaiUtility);

        console.log("Writing json to file: %s\n", json);
        vm.writeJson(json, _getJsonFilePath());
    }

    /**
     * @notice Deserialize the deployment json
     *
     * @dev Deserialization loads the json into the _deployment struct
     */
    function _deserialize() internal {
        string memory json = _getJson();

        /* Deserialize GenesisTimestamp */
        try vm.parseJsonUint(json, ".GenesisTimestamp") returns (uint256 instance) {
            _deployment.genesisTimestamp = uint64(instance);
        } catch {
            console.log("Could not parse GenesisTimestamp");
        }

        /* Deserialize USDai */
        try vm.parseJsonAddress(json, ".USDai") returns (address instance) {
            _deployment.USDai = instance;
        } catch {
            console.log("Could not parse USDai");
        }

        /* Deserialize StakedUSDai */
        try vm.parseJsonAddress(json, ".StakedUSDai") returns (address instance) {
            _deployment.stakedUSDai = instance;
        } catch {
            console.log("Could not parse StakedUSDai");
        }

        /* Deserialize BaseYieldEscrow */
        try vm.parseJsonAddress(json, ".BaseYieldEscrow") returns (address instance) {
            _deployment.baseYieldEscrow = instance;
        } catch {
            console.log("Could not parse BaseYieldEscrow");
        }

        /* Deserialize OAdapterUSDai */
        try vm.parseJsonAddress(json, ".OAdapterUSDai") returns (address instance) {
            _deployment.oAdapterUSDai = instance;
        } catch {
            console.log("Could not parse OAdapterUSDai");
        }

        /* Deserialize OAdapterStakedUSDai */
        try vm.parseJsonAddress(json, ".OAdapterStakedUSDai") returns (address instance) {
            _deployment.oAdapterStakedUSDai = instance;
        } catch {
            console.log("Could not parse OAdapterStakedUSDai");
        }

        /* Deserialize OTokenUSDai */
        try vm.parseJsonAddress(json, ".OTokenUSDai") returns (address instance) {
            _deployment.oTokenUSDai = instance;
        } catch {
            console.log("Could not parse OTokenUSDai");
        }

        /* Deserialize OTokenStakedUSDai */
        try vm.parseJsonAddress(json, ".OTokenStakedUSDai") returns (address instance) {
            _deployment.oTokenStakedUSDai = instance;
        } catch {
            console.log("Could not parse OTokenStakedUSDai");
        }

        /* Deserialize OUSDaiUtility */
        try vm.parseJsonAddress(json, ".OUSDaiUtility") returns (address instance) {
            _deployment.oUSDaiUtility = instance;
        } catch {
            console.log("Could not parse OUSDaiUtiltiy");
        }
    }
}
