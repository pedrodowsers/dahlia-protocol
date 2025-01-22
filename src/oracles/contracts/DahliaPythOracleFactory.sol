// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { DahliaPythOracle } from "./DahliaPythOracle.sol";
import { CREATE3 } from "@solady/utils/CREATE3.sol";
import { DahliaOracleFactoryBase } from "src/oracles/abstracts/DahliaOracleFactoryBase.sol";
import { DahliaOracleStaticAddress } from "src/oracles/abstracts/DahliaOracleStaticAddress.sol";

contract DahliaPythOracleFactory is DahliaOracleFactoryBase, DahliaOracleStaticAddress {
    /// @notice Emitted when a new Pyth oracle is created.
    event DahliaPythOracleCreated(address indexed caller, address indexed oracle);

    /// @notice Constructor sets the timelockAddress and pythStaticOracleAddress.
    /// @param timelock The address of the timelock.
    /// @param pythStaticOracle The address of a deployed Pyth static oracle.
    constructor(address timelock, address pythStaticOracle) DahliaOracleFactoryBase(timelock) DahliaOracleStaticAddress(pythStaticOracle) { }

    /// @notice Deploys a new DahliaPythOracle contract, or return the existing one if already deployed.
    /// @param params DahliaPythOracle.Params struct.
    /// @param delays DahliaPythOracle.Delays struct.
    /// @return oracle The deployed (or existing) DahliaPythOracle contract.
    function createPythOracle(DahliaPythOracle.Params memory params, DahliaPythOracle.Delays memory delays) external returns (address oracle) {
        bytes memory encodedArgs = abi.encode(_TIMELOCK, params, delays, _STATIC_ORACLE_ADDRESS);
        bytes32 salt = keccak256(encodedArgs);
        oracle = CREATE3.predictDeterministicAddress(salt);

        if (oracle.code.length == 0) {
            bytes memory initCode = abi.encodePacked(type(DahliaPythOracle).creationCode, encodedArgs);
            oracle = CREATE3.deployDeterministic(0, initCode, salt);
            emit DahliaPythOracleCreated(msg.sender, oracle);
        }
    }
}
