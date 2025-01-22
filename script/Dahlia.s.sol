// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { BaseScript } from "./BaseScript.sol";
import { Dahlia } from "src/core/contracts/Dahlia.sol";

contract DeployDahlia is BaseScript {
    bytes32 private constant _SALT = keccak256(abi.encode("Dahlia_V1"));

    function run() public {
        address dahliaOwner = _envAddress(DAHLIA_OWNER);
        address registry = _envAddress(DEPLOYED_REGISTRY);
        bytes memory encodedArgs = abi.encode(dahliaOwner, registry);
        bytes memory initCode = abi.encodePacked(type(Dahlia).creationCode, encodedArgs);
        string memory name = type(Dahlia).name;
        _deploy(name, DEPLOYED_DAHLIA, _SALT, initCode);
    }
}
