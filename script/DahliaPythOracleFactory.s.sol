// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { BaseScript } from "./BaseScript.sol";
import { DahliaPythOracleFactory } from "src/oracles/contracts/DahliaPythOracleFactory.sol";

contract DahliaPythOracleFactoryScript is BaseScript {
    bytes32 private constant _SALT = keccak256(abi.encode("DahliaPythOracleFactory_V1"));

    function run() public {
        address pythStaticOracleAddress = _envAddress("PYTH_STATIC_ORACLE_ADDRESS");
        address timelock = _envAddress(DEPLOYED_TIMELOCK);
        bytes memory encodedArgs = abi.encode(timelock, pythStaticOracleAddress);
        bytes memory initCode = abi.encodePacked(type(DahliaPythOracleFactory).creationCode, encodedArgs);
        string memory name = type(DahliaPythOracleFactory).name;
        _deploy(name, DEPLOYED_PYTH_ORACLE_FACTORY, _SALT, initCode);
    }
}
