// SPDX-License-Identifier: ISC
pragma solidity ^0.8.27;

import { CREATE3 } from "@solady/utils/CREATE3.sol";
import { VariableIrm } from "src/irm/contracts/VariableIrm.sol";
import { IrmConstants } from "src/irm/helpers/IrmConstants.sol";

contract IrmFactory {
    event VariableIrmCreated(address indexed caller, address indexed irmAddress);

    error MaxUtilizationTooHigh();
    error MinUtilizationOutOfRange();
    error FullUtilizationRateRangeInvalid();
    error IrmNameIsNotSet();

    function createVariableIrm(VariableIrm.Config memory config) external returns (address irm) {
        require(config.maxTargetUtilization < IrmConstants.UTILIZATION_100_PERCENT, MaxUtilizationTooHigh());
        require(config.minTargetUtilization < config.maxTargetUtilization, MinUtilizationOutOfRange());
        require(config.minFullUtilizationRate <= config.maxFullUtilizationRate, FullUtilizationRateRangeInvalid());
        require(bytes(config.name).length > 0, IrmNameIsNotSet());

        bytes memory encodedArgs = abi.encode(config);
        bytes32 salt = keccak256(encodedArgs);
        irm = CREATE3.predictDeterministicAddress(salt);
        if (irm.code.length == 0) {
            bytes memory initCode = abi.encodePacked(type(VariableIrm).creationCode, encodedArgs);
            irm = CREATE3.deployDeterministic(0, initCode, salt);
            emit VariableIrmCreated(msg.sender, irm);
        }
    }
}
