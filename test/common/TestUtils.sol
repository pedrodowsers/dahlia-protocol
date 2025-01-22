// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "@forge-std/Test.sol";
import { TestContext } from "test/common/TestContext.sol";
import { TestContextSepolia } from "test/common/TestContextSepolia.sol";

library TestUtils {
    error NetworkEnvironmentNotSet();

    function createContext(Vm vm) public returns (TestContext) {
        return new TestContext(vm);
    }

    function createContextByEnv(Vm vm) public returns (TestContext) {
        bytes32 network = keccak256(bytes(vm.envOr("NETWORK", string("sepolia"))));
        if (network == keccak256(bytes("sepolia"))) {
            return new TestContextSepolia(vm);
        }
        // else if (network == keccak256(bytes("mainnet"))) {
        //     return initializeMainnet(vm);
        // }
        revert NetworkEnvironmentNotSet();
    }
}
