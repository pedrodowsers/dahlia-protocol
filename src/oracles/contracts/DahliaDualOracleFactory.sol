// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { DahliaDualOracle } from "./DahliaDualOracle.sol";
import { CREATE3 } from "@solady/utils/CREATE3.sol";
import { Errors } from "src/oracles/helpers/Errors.sol";

contract DahliaDualOracleFactory {
    /// @notice Emitted when a new DahliaDualOracle is deployed.
    /// @param caller The address that triggered the deployment.
    /// @param oracle Deployed oracle address.
    event DahliaDualOracleCreated(address indexed caller, address indexed oracle);

    /// @notice Deploy a new DahliaDualOracle or return the existing one if already deployed.
    /// @param primary primary oracle address.
    /// @param secondary secondary oracle address.
    /// @return oracle The deployed (or existing) DahliaDualOracle contract.
    function createDualOracle(address primary, address secondary) external returns (address oracle) {
        require(primary != address(0) && secondary != address(0), Errors.ZeroAddress());

        bytes memory encodedArgs = abi.encode(primary, secondary);
        bytes32 salt = keccak256(encodedArgs);
        oracle = CREATE3.predictDeterministicAddress(salt);

        if (oracle.code.length == 0) {
            bytes memory initCode = abi.encodePacked(type(DahliaDualOracle).creationCode, encodedArgs);
            oracle = CREATE3.deployDeterministic(0, initCode, salt);
            emit DahliaDualOracleCreated(msg.sender, oracle);
        }
    }
}
