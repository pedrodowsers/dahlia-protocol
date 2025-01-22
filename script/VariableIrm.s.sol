// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { BaseScript } from "./BaseScript.sol";
import { console } from "@forge-std/console.sol";
import { CREATE3 } from "@solady/utils/CREATE3.sol";
import { IrmFactory } from "src/irm/contracts/IrmFactory.sol";
import { VariableIrm } from "src/irm/contracts/VariableIrm.sol";

contract VariableIrmScript is BaseScript {
    function run() public {
        VariableIrm.Config memory config = VariableIrm.Config({
            minTargetUtilization: _envUint("MIN_TARGET_UTILIZATION"),
            maxTargetUtilization: _envUint("MAX_TARGET_UTILIZATION"),
            targetUtilization: _envUint("TARGET_UTILIZATION"),
            minFullUtilizationRate: _envUint("MIN_FULL_UTIL_RATE"),
            maxFullUtilizationRate: _envUint("MAX_FULL_UTIL_RATE"),
            zeroUtilizationRate: _envUint("ZERO_UTIL_RATE"),
            rateHalfLife: _envUint("RATE_HALF_LIFE"),
            targetRatePercent: _envUint("TARGET_RATE_PERCENT"),
            name: _envString("IRM_NAME")
        });
        IrmFactory irmFactory = IrmFactory(_envAddress(DEPLOYED_IRM_FACTORY));
        string memory INDEX = _envString(INDEX);

        bytes memory encodedArgs = abi.encode(config);
        bytes32 salt = keccak256(encodedArgs);
        address irm = CREATE3.predictDeterministicAddress(salt, address(irmFactory));
        string memory contractName = string(abi.encodePacked("DEPLOYED_IRM_", INDEX));
        if (irm.code.length == 0) {
            vm.startBroadcast(deployer);
            irm = irmFactory.createVariableIrm(config);
            _printContract(contractName, irm);
            vm.stopBroadcast();
        } else {
            console.log(contractName, "already deployed");
        }
    }
}
