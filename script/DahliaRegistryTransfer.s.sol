// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { BaseScript } from "./BaseScript.sol";
import { DahliaRegistry } from "src/core/contracts/DahliaRegistry.sol";

contract DahliaRegistryTransferScript is BaseScript {
    function run() public {
        address dahliaOwner = _envAddress(DAHLIA_OWNER);
        DahliaRegistry registry = DahliaRegistry(_envAddress(DEPLOYED_REGISTRY));

        address owner = registry.owner();
        if (owner == deployer) {
            vm.startBroadcast(deployer);
            // Set properly dahlia owner
            registry.transferOwnership(dahliaOwner);
            vm.stopBroadcast();
        }
    }
}
