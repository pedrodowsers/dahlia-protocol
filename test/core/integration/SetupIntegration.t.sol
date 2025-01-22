// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "@forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Dahlia } from "src/core/contracts/Dahlia.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { DahliaTransUtils } from "test/common/DahliaTransUtils.sol";
import { TestContext } from "test/common/TestContext.sol";

contract SetupIntegrationTest is Test {
    using BoundUtils for Vm;
    using DahliaTransUtils for Vm;

    TestContext ctx;
    address dahliaRegistry;
    address owner;

    function setUp() public {
        ctx = new TestContext(vm);
        owner = ctx.createWallet("OWNER");
        dahliaRegistry = ctx.createDahliaRegistry(owner);
    }

    function test_int_setup_createDahlia_revert() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new Dahlia(owner, address(0));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new Dahlia(address(0), address(1));
    }

    function test_int_setup_createDahlia_withSalt() public {
        bytes32 salt = 0x5e3e6b1e01c5708055548d82d01db741e37d03b948a7ef9f3d4b962648bcbfa0;

        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(this), salt, keccak256(abi.encodePacked(type(Dahlia).creationCode, abi.encode(owner, dahliaRegistry)))
                        )
                    )
                )
            )
        );

        Dahlia dahliaAddress = new Dahlia{ salt: salt }(owner, dahliaRegistry);
        assertEq(address(dahliaAddress), predictedAddress);
    }
}
