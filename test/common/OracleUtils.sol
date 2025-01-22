// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { AggregatorV3Interface } from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { Vm } from "forge-std/Test.sol";

library OracleUtils {
    struct LatestRoundDataReturn {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    function getLatestRoundDataStruct(AggregatorV3Interface _aggregatorV3) internal view returns (LatestRoundDataReturn memory _return) {
        (_return.roundId, _return.answer, _return.startedAt, _return.updatedAt, _return.answeredInRound) = _aggregatorV3.latestRoundData();
    }

    function setDecimals(Vm vm, AggregatorV3Interface _oracle, uint8 _decimals) public {
        vm.mockCall(address(_oracle), abi.encodeWithSelector(AggregatorV3Interface.decimals.selector), abi.encode(_decimals));
    }

    /// @notice The ```setPrice``` function uses a numerator and denominator value to set a price using the number of decimals from the oracle itself
    /// @dev Remember the units here, quote per asset i.e. USD per ETH for the ETH/USD oracle
    /// @param _oracle The oracle to mock
    /// @param numerator The numerator of the price
    /// @param denominator The denominator of the price
    /// @param vm The vm from forge
    function setPrice(Vm vm, AggregatorV3Interface _oracle, uint256 numerator, uint256 denominator, uint256 _lastUpdatedAt) public returns (int256 _price) {
        _price = int256((numerator * 10 ** _oracle.decimals()) / denominator);
        vm.mockCall(
            address(_oracle),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), _price, 0, _lastUpdatedAt, uint80(0))
        );
    }

    function setPrice(Vm vm, AggregatorV3Interface _oracle, uint256 price_, uint256 _lastUpdatedAt) public returns (int256 _price) {
        _price = int256(price_);
        vm.mockCall(
            address(_oracle),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), _price, 0, _lastUpdatedAt, uint80(0))
        );
    }

    function setPrice(Vm vm, AggregatorV3Interface _oracle, int256 price_, uint256 _lastUpdatedAt) public returns (int256 _price) {
        _price = int256(price_);
        vm.mockCall(
            address(_oracle),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), _price, 0, _lastUpdatedAt, uint80(0))
        );
    }

    function setPrice(Vm vm, AggregatorV3Interface _oracle, uint256 price_) public returns (int256 _price) {
        (,,, uint256 _updatedAt,) = _oracle.latestRoundData();
        _price = int256(price_);
        vm.mockCall(
            address(_oracle), abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), abi.encode(uint80(0), _price, 0, _updatedAt, uint80(0))
        );
    }

    function setPriceWithE18Param(Vm vm, AggregatorV3Interface _oracle, uint256 price_) public returns (int256 returnPrice) {
        (,,, uint256 _updatedAt,) = _oracle.latestRoundData();
        uint256 _decimals = _oracle.decimals();
        price_ = (price_ * 10 ** _decimals) / 1e18;
        returnPrice = int256(price_);
        vm.mockCall(
            address(_oracle),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), returnPrice, 0, _updatedAt, uint80(0))
        );
    }

    function setUpdatedAt(Vm vm, AggregatorV3Interface _oracle, uint256 _updatedAt) public returns (int256 _price) {
        (, _price,,,) = _oracle.latestRoundData();
        vm.mockCall(
            address(_oracle), abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), abi.encode(uint80(0), _price, 0, _updatedAt, uint80(0))
        );
    }
}
