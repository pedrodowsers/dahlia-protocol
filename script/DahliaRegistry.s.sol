// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { BaseScript } from "./BaseScript.sol";
import { DahliaRegistry } from "src/core/contracts/DahliaRegistry.sol";

contract DahliaRegistryScript is BaseScript {
    bytes32 private constant _SALT = keccak256(abi.encode("DahliaRegistry_V1"));

    function run() public {
        string memory name = type(DahliaRegistry).name;
        bytes memory encodedArgs = abi.encode(deployer); // this is not a mistake we deploy registry to be able set values
        bytes memory initCode = abi.encodePacked(type(DahliaRegistry).creationCode, encodedArgs);
        _deploy(name, DEPLOYED_REGISTRY, _SALT, initCode);
    }
}
