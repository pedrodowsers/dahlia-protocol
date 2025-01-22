// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { BaseScript } from "./BaseScript.sol";
import { Timelock } from "src/oracles/contracts/Timelock.sol";

contract TimelockScript is BaseScript {
    bytes32 private constant _SALT = keccak256(abi.encode("Timelock_V1"));

    function run() public {
        address dahliaOwner = _envAddress(DAHLIA_OWNER);
        uint256 timelockDelay = _envUint(TIMELOCK_DELAY);
        bytes memory encodedArgs = abi.encode(dahliaOwner, timelockDelay);
        bytes memory initCode = abi.encodePacked(type(Timelock).creationCode, encodedArgs);
        string memory name = type(Timelock).name;
        _deploy(name, DEPLOYED_TIMELOCK, _SALT, initCode);
    }
}
