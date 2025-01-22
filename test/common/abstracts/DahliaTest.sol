// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "@forge-std/Test.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";

abstract contract DahliaTest is Test {
    address public dualOracleAddress;

    function()[] internal setupFunctions;

    modifier useMultipleSetupFunctions() {
        for (uint256 i = 0; i < setupFunctions.length; i++) {
            setupFunctions[i]();
            _;
            vm.clearMockedCalls();
        }
    }

    function assertEq(IDahlia.MarketStatus a, IDahlia.MarketStatus b, string memory err) internal pure virtual {
        vm.assertEq(uint256(a), uint256(b), err);
    }
}
