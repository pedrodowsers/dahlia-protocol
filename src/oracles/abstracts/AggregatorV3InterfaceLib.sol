// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { AggregatorV3Interface } from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { Errors } from "src/oracles/helpers/Errors.sol";

library AggregatorV3InterfaceLib {
    /// @notice Get the latest price from the feed and check if the data is stale or negative
    /// @param feed The Chainlink price feed
    /// @param maxDelay The maximum allowed delay for the data in seconds
    /// @return price The latest price from the feed
    /// @return isBadData True if the data is stale or negative
    function getFeedPrice(AggregatorV3Interface feed, uint256 maxDelay) internal view returns (uint256 price, bool isBadData) {
        if (address(feed) == address(0)) {
            return (1, false); // Return default price if feed address is zero
        }

        (, int256 _answer,, uint256 _chainlinkUpdatedAt,) = feed.latestRoundData();
        require(_answer >= 0, Errors.NegativeAnswer(_answer)); // Ensure the answer is non-negative

        // Determine if the data is stale or negative
        isBadData = maxDelay != 0 && (_answer <= 0 || ((block.timestamp - _chainlinkUpdatedAt) > maxDelay));
        price = uint256(_answer);
    }

    /// @notice Get the number of decimals used by the feed
    /// @param feed The Chainlink price feed
    /// @return The number of decimals
    function getDecimals(AggregatorV3Interface feed) internal view returns (uint256) {
        if (address(feed) == address(0)) {
            return 0; // Return 0 if feed address is zero
        }
        return feed.decimals();
    }
}
