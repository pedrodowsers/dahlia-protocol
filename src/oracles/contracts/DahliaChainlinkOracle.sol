// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { AggregatorV3Interface } from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { AggregatorV3InterfaceLib } from "src/oracles/abstracts/AggregatorV3InterfaceLib.sol";
import { Errors } from "src/oracles/helpers/Errors.sol";
import { IDahliaOracle } from "src/oracles/interfaces/IDahliaOracle.sol";

/// @title DahliaChainlinkOracle
/// @notice A contract for fetching price from Chainlink Oracle
contract DahliaChainlinkOracle is IDahliaOracle, Ownable2Step {
    using FixedPointMathLib for uint256;
    using AggregatorV3InterfaceLib for AggregatorV3Interface;

    struct Params {
        address baseToken; // Collateral token (e.g., WBTC)
        AggregatorV3Interface baseFeedPrimary;
        AggregatorV3Interface baseFeedSecondary;
        address quoteToken; // Loan token (e.g., USDC)
        AggregatorV3Interface quoteFeedPrimary;
        AggregatorV3Interface quoteFeedSecondary;
    }

    /// @notice Struct to hold max delay settings for primary and secondary data sources
    struct Delays {
        uint256 baseMaxDelayPrimary; // Maximum delay for primary base data
        uint256 baseMaxDelaySecondary; // Maximum delay for secondary base data
        uint256 quoteMaxDelayPrimary; // Maximum delay for primary quote data
        uint256 quoteMaxDelaySecondary; // Maximum delay for secondary quote data
    }

    /// @notice Emitted when the max oracle delay is updated
    /// @param newMaxDelays The new max oracle delay settings
    event MaximumOracleDelayUpdated(Delays newMaxDelays);

    /// @notice Emitted when the contract is deployed
    /// @param params Initial parameters
    event ParamsUpdated(Params params);

    uint256 public immutable ORACLE_PRECISION;

    address public immutable BASE_TOKEN; // Collateral token (e.g., WBTC)
    AggregatorV3Interface public immutable BASE_FEED_PRIMARY;
    AggregatorV3Interface public immutable BASE_FEED_SECONDARY;
    address public immutable QUOTE_TOKEN; // Loan token (e.g., USDC)
    AggregatorV3Interface public immutable QUOTE_FEED_PRIMARY;
    AggregatorV3Interface public immutable QUOTE_FEED_SECONDARY;

    uint256 internal baseMaxDelayPrimary;
    uint256 internal baseMaxDelaySecondary;
    uint256 internal quoteMaxDelayPrimary;
    uint256 internal quoteMaxDelaySecondary;

    constructor(address owner, Params memory params, Delays memory delays) Ownable(owner) {
        require(address(params.baseToken) != address(0), Errors.ZeroAddress());
        require(address(params.quoteToken) != address(0), Errors.ZeroAddress());

        BASE_TOKEN = params.baseToken;
        BASE_FEED_PRIMARY = params.baseFeedPrimary;
        BASE_FEED_SECONDARY = params.baseFeedSecondary;
        QUOTE_TOKEN = params.quoteToken;
        QUOTE_FEED_PRIMARY = params.quoteFeedPrimary;
        QUOTE_FEED_SECONDARY = params.quoteFeedSecondary;

        emit ParamsUpdated(params);
        _setMaximumOracleDelays(delays);

        uint256 baseTokenDecimals = IERC20Metadata(BASE_TOKEN).decimals();
        uint256 quoteTokenDecimals = IERC20Metadata(QUOTE_TOKEN).decimals();

        ORACLE_PRECISION = 10
            ** (
                36 + quoteTokenDecimals + QUOTE_FEED_PRIMARY.getDecimals() + QUOTE_FEED_SECONDARY.getDecimals() - baseTokenDecimals
                    - BASE_FEED_PRIMARY.getDecimals() - BASE_FEED_SECONDARY.getDecimals()
            );
    }

    /// @dev Internal function to update max oracle delays
    /// @param delays The new max delay settings
    function _setMaximumOracleDelays(Delays memory delays) private {
        emit MaximumOracleDelayUpdated({ newMaxDelays: delays });
        baseMaxDelayPrimary = delays.baseMaxDelayPrimary;
        baseMaxDelaySecondary = delays.baseMaxDelaySecondary;
        quoteMaxDelayPrimary = delays.quoteMaxDelayPrimary;
        quoteMaxDelaySecondary = delays.quoteMaxDelaySecondary;
    }

    /// @notice Set new maximum delays for oracle data to determine if it's stale
    /// @dev Only callable by the timelock address
    /// @param delays New maximum delay settings
    function setMaximumOracleDelays(Delays memory delays) external onlyOwner {
        _setMaximumOracleDelays(delays);
    }

    /// @dev Internal function to get the Chainlink price and check data validity
    /// @return price The calculated price
    /// @return isBadData True if any of the data is stale or invalid
    function _getChainlinkPrice() private view returns (uint256 price, bool isBadData) {
        (uint256 _basePrimaryPrice, bool _basePrimaryIsBadData) = BASE_FEED_PRIMARY.getFeedPrice(baseMaxDelayPrimary);
        (uint256 _baseSecondaryPrice, bool _baseSecondaryIsBadData) = BASE_FEED_SECONDARY.getFeedPrice(baseMaxDelaySecondary);
        (uint256 _quotePrimaryPrice, bool _quotePrimaryIsBadData) = QUOTE_FEED_PRIMARY.getFeedPrice(quoteMaxDelayPrimary);
        (uint256 _quoteSecondaryPrice, bool _quoteSecondaryIsBadData) = QUOTE_FEED_SECONDARY.getFeedPrice(quoteMaxDelaySecondary);

        isBadData = _basePrimaryIsBadData || _baseSecondaryIsBadData || _quotePrimaryIsBadData || _quoteSecondaryIsBadData;

        price = ORACLE_PRECISION.mulDiv(_basePrimaryPrice * _baseSecondaryPrice, _quotePrimaryPrice * _quoteSecondaryPrice);
    }

    /// @notice Returns the current max delay settings
    function maxDelays() external view returns (Delays memory) {
        return Delays({
            baseMaxDelayPrimary: baseMaxDelayPrimary,
            baseMaxDelaySecondary: baseMaxDelaySecondary,
            quoteMaxDelayPrimary: quoteMaxDelayPrimary,
            quoteMaxDelaySecondary: quoteMaxDelaySecondary
        });
    }

    /// @inheritdoc IDahliaOracle
    function getPrice() external view returns (uint256, bool) {
        return _getChainlinkPrice();
    }
}
