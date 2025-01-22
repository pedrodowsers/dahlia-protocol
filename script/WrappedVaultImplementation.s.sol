// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { BaseScript } from "./BaseScript.sol";
import { WrappedVault } from "src/royco/contracts/WrappedVault.sol";

contract WrappedVaultImplementationScript is BaseScript {
    bytes32 private constant _SALT = keccak256(abi.encode("WrappedVault_V1"));

    function run() public {
        bytes memory initCode = type(WrappedVault).creationCode;
        string memory name = type(WrappedVault).name;
        _deploy(name, DEPLOYED_WRAPPED_VAULT_IMPLEMENTATION, _SALT, initCode);
    }
}
