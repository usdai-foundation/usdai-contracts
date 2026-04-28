// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {BaseTest} from "../Base.t.sol";
import {ChainlinkPriceOracle} from "../../src/oracles/ChainlinkPriceOracle.sol";
import {AggregatorV3Interface} from "../../src/interfaces/external/IAggregatorV3Interface.sol";
import {IPriceOracle} from "../../src/interfaces/IPriceOracle.sol";

contract ChainlinkPriceOracleTest is BaseTest {
    // Mainnet addresses
    address constant WETH_ARBITRUM = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant WETH_ARBITRUM_PRICE_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612; // WETH_ARBITRUM/USD
    address constant USDC_ARBITRUM = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDC_ARBITRUM_PRICE_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3; // USDC_ARBITRUM/USD
    address constant DAI_ARBITRUM = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address constant DAI_ARBITRUM_PRICE_FEED = 0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB; // DAI_ARBITRUM/USD
    address constant ARBITRUM_SEQUENCER_UPTIME_FEED = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;

    ChainlinkPriceOracle public oracle;

    function setUp() public override {
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));
        vm.rollFork(424398311);

        // Create arrays for constructor
        address[] memory tokens = new address[](3);
        tokens[0] = USDC_ARBITRUM;
        tokens[1] = DAI_ARBITRUM;
        tokens[2] = WETH_ARBITRUM;

        address[] memory priceFeeds = new address[](3);
        priceFeeds[0] = USDC_ARBITRUM_PRICE_FEED;
        priceFeeds[1] = DAI_ARBITRUM_PRICE_FEED;
        priceFeeds[2] = WETH_ARBITRUM_PRICE_FEED;

        // Deploy oracle
        oracle =
            new ChainlinkPriceOracle(ARBITRUM_SEQUENCER_UPTIME_FEED, PYUSD_PRICE_FEED, tokens, priceFeeds, users.admin);
    }

    function test__Price_WETH_ARBITRUM() public view {
        // Get WETH_ARBITRUM price in terms of USDai
        uint256 price = oracle.price(WETH_ARBITRUM);

        (, int256 answer,,,) = AggregatorV3Interface(WETH_ARBITRUM_PRICE_FEED).latestRoundData();

        assertApproxEqAbs(price, uint256(answer) * 10 ** 10, 6e18, "Price mismatch");
    }

    function test__Price_USDC_ARBITRUM() public view {
        // Get USDC_ARBITRUM price in terms of USDai
        uint256 price = oracle.price(USDC_ARBITRUM);

        (, int256 answer,,,) = AggregatorV3Interface(USDC_ARBITRUM_PRICE_FEED).latestRoundData();

        // PYUSD is trading at a higher price than USDC
        assertApproxEqAbs(price, uint256(answer) * 10 ** 10, 8e13, "Price mismatch");
    }

    function test__Price_DAI_ARBITRUM() public view {
        // Get DAI_ARBITRUM price in terms of USDai
        uint256 price = oracle.price(DAI_ARBITRUM);

        (, int256 answer,,,) = AggregatorV3Interface(DAI_ARBITRUM_PRICE_FEED).latestRoundData();

        // PYUSD is trading at a higher price than DAI
        assertApproxEqAbs(price, uint256(answer) * 10 ** 10, 8e13, "Price mismatch");
    }

    function test__Price_RevertWhen_UnsupportedToken() public {
        // Create a random token address
        address randomToken = address(0x123);

        // Should revert when trying to get price for unsupported token
        vm.expectRevert(abi.encodeWithSelector(IPriceOracle.UnsupportedToken.selector, randomToken));
        oracle.price(randomToken);
    }

    function test__RemoveTokenPriceFeeds() public {
        address[] memory tokens = new address[](1);
        tokens[0] = USDC_ARBITRUM;

        // Remove USDC_ARBITRUM price feed
        vm.prank(users.admin);
        oracle.removeTokenPriceFeeds(tokens);

        // Should revert when trying to get price for unsupported token
        vm.expectRevert(abi.encodeWithSelector(IPriceOracle.UnsupportedToken.selector, USDC_ARBITRUM));
        oracle.price(USDC_ARBITRUM);
    }
}
