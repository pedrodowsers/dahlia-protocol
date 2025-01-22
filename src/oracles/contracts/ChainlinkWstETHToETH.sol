// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Errors } from "../helpers/Errors.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @dev Interface for wstETH, taken from https://github.com/lidofinance/core/blob/master/contracts/0.6.12/WstETH.sol
interface IWstETH is IERC20Metadata {
    /**
     * @notice Get amount of stETH for a one wstETH
     * @return Amount of stETH for 1 wstETH
     */
    function stEthPerToken() external view returns (uint256);
}

/// @title ChainlinkWstETHToETH
/// @notice Oracle to convert wstETH-ETH using a stETH-ETH Chainlink feed.
/// @dev Adapted from https://github.com/lidofinance/wsteth-eth-price-feed/blob/main/contracts/AAVECompatWstETHToETHPriceFeed.sol
contract ChainlinkWstETHToETH is AggregatorV3Interface {
    error UnsupportedMethod();
    error BadWstETHToStETH();

    struct Params {
        address wstEth;
        address stEthToEthFeed;
    }

    event ParamsUpdated(Params params);

    uint8 internal immutable _DECIMAL;
    int256 internal immutable _WST_ETH_PRECISION;
    int256 internal immutable _STETH_ETH_PRECISION;
    IWstETH public immutable WST_ETH;
    AggregatorV3Interface public immutable STETH_TO_ETH_FEED;

    constructor(Params memory params) {
        require(params.wstEth != address(0) && params.stEthToEthFeed != address(0), Errors.ZeroAddress());

        WST_ETH = IWstETH(params.wstEth);
        STETH_TO_ETH_FEED = AggregatorV3Interface(params.stEthToEthFeed);
        _DECIMAL = STETH_TO_ETH_FEED.decimals();
        _WST_ETH_PRECISION = int256(10 ** WST_ETH.decimals());
        _STETH_ETH_PRECISION = int256(10 ** STETH_TO_ETH_FEED.decimals());

        emit ParamsUpdated(params);
    }

    function decimals() external view returns (uint8) {
        return _DECIMAL;
    }

    function description() external pure returns (string memory) {
        return "WSTETH / ETH";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(uint80) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert UnsupportedMethod();
    }

    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        int256 wstETHToStETH = int256(WST_ETH.stEthPerToken());
        require(wstETHToStETH > 0, BadWstETHToStETH());

        (roundId, answer, startedAt, updatedAt, answeredInRound) = STETH_TO_ETH_FEED.latestRoundData();
        if (answer > _STETH_ETH_PRECISION) {
            answer = _STETH_ETH_PRECISION;
        }
        answer = answer * wstETHToStETH / _WST_ETH_PRECISION;
    }
}
