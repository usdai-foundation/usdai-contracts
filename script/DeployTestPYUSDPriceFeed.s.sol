// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import "forge-std/Script.sol";

import {AggregatorV3Interface} from "src/interfaces/external/IAggregatorV3Interface.sol";

import {Deployer} from "./utils/Deployer.s.sol";

contract TestPYUSDPriceFeed is AggregatorV3Interface {
    function decimals() external pure returns (uint8) {
        return 18;
    }

    function description() external pure returns (string memory) {
        return "Test PYUSD";
    }

    function version() external pure returns (uint256) {
        return 6;
    }

    function getRoundData(
        uint80
    ) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert("Not Implemented");
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 36893488147419103788;
        answer = 99997961 * 1e10;
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        answeredInRound = 36893488147419103788;
    }
}

contract DeployTestPYUSDPriceFeed is Deployer {
    function run() public broadcast useDeployment returns (address) {
        // Deploy TestPYUSDPriceFeed
        TestPYUSDPriceFeed pyusdPriceFeed = new TestPYUSDPriceFeed();
        console.log("TestPYUSDPriceFeed", address(pyusdPriceFeed));

        return (address(pyusdPriceFeed));
    }
}
