// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { BaseScript } from "./BaseScript.sol";
import { console } from "@forge-std/console.sol";
import { CREATE3 } from "@solady/utils/CREATE3.sol";
import { DahliaPythOracle } from "src/oracles/contracts/DahliaPythOracle.sol";
import { DahliaPythOracleFactory } from "src/oracles/contracts/DahliaPythOracleFactory.sol";

contract DahliaPythOracleScript is BaseScript {
    function run() public {
        DahliaPythOracleFactory oracleFactory = DahliaPythOracleFactory(_envAddress(DEPLOYED_PYTH_ORACLE_FACTORY));
        string memory INDEX = _envString(INDEX);
        address baseToken = _envAddress("PYTH_ORACLE_BASE_TOKEN");
        bytes32 baseFeed = _envBytes32("PYTH_ORACLE_BASE_FEED");
        address quoteToken = _envAddress("PYTH_ORACLE_QUOTE_TOKEN");
        bytes32 quoteFeed = _envBytes32("PYTH_ORACLE_QUOTE_FEED");
        uint256 baseMaxDelay = _envUint("PYTH_ORACLE_BASE_MAX_DELAY");
        uint256 quoteMaxDelay = _envUint("PYTH_ORACLE_QUOTE_MAX_DELAY");
        DahliaPythOracle.Params memory params = DahliaPythOracle.Params(baseToken, baseFeed, quoteToken, quoteFeed);
        DahliaPythOracle.Delays memory delays = DahliaPythOracle.Delays(baseMaxDelay, quoteMaxDelay);

        bytes memory encodedArgs = abi.encode(oracleFactory.timelockAddress(), params, delays, oracleFactory.STATIC_ORACLE_ADDRESS());
        bytes32 salt = keccak256(encodedArgs);
        address pythOracle = CREATE3.predictDeterministicAddress(salt, address(oracleFactory));
        string memory contractName = string(abi.encodePacked("DEPLOYED_PYTH_ORACLE_", INDEX));
        if (pythOracle.code.length == 0) {
            vm.startBroadcast(deployer);
            pythOracle = oracleFactory.createPythOracle(params, delays);
            _printContract(contractName, pythOracle);
            vm.stopBroadcast();
        } else {
            console.log(pythOracle, "already deployed");
        }
    }
}
