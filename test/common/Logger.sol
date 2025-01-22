// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { LibString } from "@solady/utils/LibString.sol";
import { console2 as console } from "forge-std/Test.sol";

library Logger {
    using LibString for *;

    uint64 internal constant FIFTY_BPS = 158_247_046;
    uint64 internal constant ONE_PERCENT = FIFTY_BPS * 2;
    uint64 internal constant ONE_BPS = FIFTY_BPS / 50;

    function toDecimal(uint256 _value, uint256 _precision) public pure returns (string memory) {
        uint256 _decimals = bytes(_precision.toString()).length - 1;
        uint256 _integer = _value >= _precision ? _value / _precision : 0;
        string memory _decimalString = padLeft((_value - (_integer * _precision)).toString(), "0", _decimals);
        return string(abi.encodePacked(_integer.toString(), ".", _decimalString));
    }

    function padLeft(string memory _string, string memory _pad, uint256 _length) public pure returns (string memory) {
        while (bytes(_string).length < _length) {
            _string = string(abi.encodePacked(_pad, _string));
        }
        return _string;
    }

    function logRate(string memory _string, uint256 _rate) public pure {
        console.log(string(abi.encodePacked(_string, " BPS: ", (_rate / ONE_BPS).toString(), " (raw: ", _rate.toString(), ")")));
    }

    function rate(string memory _string, uint256 _rate) public pure {
        logRate(_string, _rate);
    }

    function logDecimal(string memory _string, uint256 _value, uint256 _precision) public pure {
        string memory _valueString = toDecimal(_value, _precision);
        console.log(string(abi.encodePacked(_string, " ", _valueString, " (raw: ", _value.toString(), ")")));
    }

    function decimal(string memory _string, uint256 _value, uint256 _precision) public pure {
        logDecimal(_string, _value, _precision);
    }

    function decimal(string memory _string, uint256 _value) public pure {
        logDecimal(_string, _value, 1e18);
    }

    function logPercent(string memory _string, uint256 _percent, uint256 _precision) public pure {
        string memory _valueString = toDecimal(_percent * 100, _precision);
        console.log(string(abi.encodePacked(_string, " ", _valueString, "%", " (raw: ", _percent.toString(), ")")));
    }

    function percent(string memory _string, uint256 _percent, uint256 _precision) public pure {
        logPercent(_string, _percent, _precision);
    }

    function percent(string memory _string, uint256 _percent) public pure {
        logPercent(_string, _percent, 1e18);
    }

    function addressWithEtherscanLink(string memory _string, address _address) public pure {
        console.log(string(abi.encodePacked(_string, " ", _address.toHexString(), " (", toEtherscanLink(_address), ")")));
    }

    function toEtherscanLink(address _address) public pure returns (string memory) {
        return string(abi.encodePacked("https://etherscan.io/address/", _address.toHexString()));
    }
}
