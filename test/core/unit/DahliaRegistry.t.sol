// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Test, Vm } from "forge-std/Test.sol";
import { DahliaRegistry, IDahliaRegistry } from "src/core/contracts/DahliaRegistry.sol";
import { Constants } from "src/core/helpers/Constants.sol";
import { IIrm } from "src/irm/interfaces/IIrm.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { TestContext } from "test/common/TestContext.sol";

contract DahliaRegistryTest is Test {
    using BoundUtils for Vm;

    TestContext ctx;
    address owner;
    DahliaRegistry registry;

    function setUp() public {
        ctx = new TestContext(vm);
        owner = ctx.createWallet("OWNER");
        registry = new DahliaRegistry(owner);
    }

    function test_unit_registry_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new DahliaRegistry(address(0));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        registry.setValue(1, 1);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        registry.setAddress(1, address(1));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        registry.allowIrm(IIrm(address(1)));
    }

    function test_unit_registry_value(uint256 key, uint256 value) public {
        vm.assume(key > 1);
        vm.assume(value != 0);
        // this is special key added in constructor
        vm.assume(key != Constants.VALUE_ID_ROYCO_WRAPPED_VAULT_MIN_INITIAL_FRONTEND_FEE);
        vm.assume(key != Constants.VALUE_ID_REPAY_PERIOD);
        vm.assume(key != Constants.VALUE_ID_DAHLIA_MARKET_INITIAL_PROTOCOL_FEE);
        assertEq(registry.getValue(key), 0);

        vm.prank(owner);
        registry.setValue(key, value);

        assertEq(registry.getValue(key), value);
        assertEq(registry.getValue(1, 2), 2, "check default value");
        assertEq(registry.getValue(key, 2), value, "check default value 2");
    }

    function test_unit_registry_address(uint256 key, address addr) public {
        vm.assume(addr != address(1));
        assertEq(registry.getAddress(key), address(0));

        vm.prank(owner);
        registry.setAddress(key, addr);

        assertEq(registry.getAddress(key), addr);

        vm.prank(owner);
        registry.allowIrm(IIrm(addr));

        assertEq(registry.isIrmAllowed(IIrm(addr)), true);
        assertEq(registry.isIrmAllowed(IIrm(address(1))), false);
    }

    function test_unit_registry_allowIrmSuccess(IIrm irmFuzz) public {
        vm.assume(!registry.isIrmAllowed(irmFuzz));
        vm.prank(owner);
        vm.expectEmit(true, true, true, true, address(registry));
        emit IDahliaRegistry.AllowIrm(irmFuzz);
        registry.allowIrm(irmFuzz);

        assertEq(registry.isIrmAllowed(irmFuzz), true);
    }

    function test_unit_registry_disallowIrm(IIrm irmFuzz) public {
        vm.assume(!registry.isIrmAllowed(irmFuzz));
        vm.prank(owner);
        registry.allowIrm(irmFuzz);

        assertEq(registry.isIrmAllowed(irmFuzz), true);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true, address(registry));
        emit IDahliaRegistry.DisallowIrm(irmFuzz);
        registry.disallowIrm(irmFuzz);

        assertEq(registry.isIrmAllowed(irmFuzz), false);
    }
}
