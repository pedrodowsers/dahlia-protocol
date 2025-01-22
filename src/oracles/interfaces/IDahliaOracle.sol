// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title Dahlia Oracle Interface
/// @notice Interface for fetching price data and its validity
interface IDahliaOracle {
    /// @notice Get the current price and check if the data is valid
    /// @return price The current price
    /// @return isBadData True if the data is stale or negative
    function getPrice() external view returns (uint256 price, bool isBadData);
}
