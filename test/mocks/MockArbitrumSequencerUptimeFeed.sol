// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

/**
 * @title Mock Arbitrum Sequencer Uptime Feed
 * @author USD.AI Foundation
 * @dev Implements the L2 sequencer uptime feed shape consumed by ChainlinkPriceOracle.
 *      Intended to be installed at the live feed address via `vm.etch` so the oracle's
 *      immutable feed pointer keeps resolving to a controllable test contract.
 */
contract MockArbitrumSequencerUptimeFeed {
    int256 internal _answer;
    uint256 internal _startedAt;
    uint256 internal _updatedAt;
    uint80 internal _roundId;

    function setRoundData(int256 answer_, uint256 startedAt_) external {
        _answer = answer_;
        _startedAt = startedAt_;
        _updatedAt = block.timestamp;
        _roundId = _roundId + 1;
    }

    function decimals() external pure returns (uint8) {
        return 0;
    }

    function description() external pure returns (string memory) {
        return "Mock Arbitrum Sequencer Uptime Feed";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(
        uint80
    ) external view returns (uint80, int256, uint256, uint256, uint80) {
        return (_roundId, _answer, _startedAt, _updatedAt, _roundId);
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (_roundId, _answer, _startedAt, _updatedAt, _roundId);
    }
}
