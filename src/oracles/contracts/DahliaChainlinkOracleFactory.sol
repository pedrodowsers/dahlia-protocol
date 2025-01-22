// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { DahliaChainlinkOracle } from "./DahliaChainlinkOracle.sol";
import { CREATE3 } from "@solady/utils/CREATE3.sol";
import { DahliaOracleFactoryBase } from "src/oracles/abstracts/DahliaOracleFactoryBase.sol";

/// @title DahliaChainlinkOracleFactory factory to create chainlink oracle
contract DahliaChainlinkOracleFactory is DahliaOracleFactoryBase {
    /// @notice Emitted when a new Chainlink oracle is created.
    event DahliaChainlinkOracleCreated(address indexed caller, address indexed oracle);

    /// @notice Constructor sets the timelockAddress.
    /// @param timelock The address of the timelock.
    constructor(address timelock) DahliaOracleFactoryBase(timelock) { }

    /// @notice Creates a new Chainlink oracle contract, or return the existing one if already deployed.
    /// @param params Chainlink oracle parameters.
    /// @param maxDelays Chainlink maximum delay parameters.
    /// @return oracle The deployed (or existing) DahliaChainlinkOracle contract.
    function createChainlinkOracle(DahliaChainlinkOracle.Params memory params, DahliaChainlinkOracle.Delays memory maxDelays)
        external
        returns (address oracle)
    {
        bytes memory encodedArgs = abi.encode(_TIMELOCK, params, maxDelays);
        bytes32 salt = keccak256(encodedArgs);
        oracle = CREATE3.predictDeterministicAddress(salt);

        if (oracle.code.length == 0) {
            bytes memory initCode = abi.encodePacked(type(DahliaChainlinkOracle).creationCode, encodedArgs);
            oracle = CREATE3.deployDeterministic(0, initCode, salt);
            emit DahliaChainlinkOracleCreated(msg.sender, oracle);
        }
    }
}
