// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "@forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Timelock } from "src/oracles/contracts/Timelock.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { TestContext } from "test/common/TestContext.sol";
import { TestConstants } from "test/common/TestContext.sol";

contract TimelockTest is Test {
    using BoundUtils for Vm;

    uint256 constant NEW_TIMELOCK_DELAY = 2 days;
    TestContext ctx;
    address owner;
    address timelockAddr;
    Timelock timelock;
    uint256 eta;
    bytes data;
    string signature = "";

    function setUp() public {
        vm.createSelectFork("mainnet", 20_921_816);
        ctx = new TestContext(vm);
        owner = ctx.OWNER();
        timelockAddr = ctx.createTimelock();
        timelock = Timelock(timelockAddr);

        eta = block.timestamp + timelock.delay() + 1;
    }

    function test_timelock_setDelay() public {
        vm.prank(timelockAddr);
        vm.expectEmit(true, true, false, true, timelockAddr);
        emit Timelock.NewDelay(NEW_TIMELOCK_DELAY);
        timelock.setDelay(NEW_TIMELOCK_DELAY);
        assertEq(timelock.delay(), NEW_TIMELOCK_DELAY);
    }

    function test_timelock_unauthorized() public {
        bytes memory ownerError = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this));
        data = abi.encodeWithSelector(Timelock.setDelay.selector, NEW_TIMELOCK_DELAY);
        vm.expectRevert(ownerError);
        timelock.queueTransaction(timelockAddr, 0, signature, data, eta);

        vm.expectRevert(ownerError);
        timelock.executeTransaction(timelockAddr, 0, signature, data, eta);

        vm.expectRevert(ownerError);
        timelock.cancelTransaction(timelockAddr, 0, signature, data, eta);

        vm.expectRevert(Timelock.CallMustComeFromTimelock.selector);
        timelock.setDelay(NEW_TIMELOCK_DELAY);
    }

    function test_timelock_setDelayInTransaction() public {
        data = abi.encodeWithSelector(Timelock.setDelay.selector, NEW_TIMELOCK_DELAY);
        bytes32 expectedTxHash = keccak256(abi.encode(timelockAddr, 0, signature, data, eta));

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, timelockAddr);
        emit Timelock.QueueTransaction(expectedTxHash, timelockAddr, 0, signature, data, eta);
        bytes32 txHash = timelock.queueTransaction(timelockAddr, 0, signature, data, eta);
        assertEq(txHash, expectedTxHash);

        vm.forward(timelock.delay() + 1);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, timelockAddr);
        emit Timelock.ExecuteTransaction(txHash, timelockAddr, 0, signature, data, eta);
        timelock.executeTransaction(timelockAddr, 0, signature, data, eta);

        assertEq(timelock.delay(), NEW_TIMELOCK_DELAY);
    }

    function test_timelock_setDelayWithSignature() public {
        signature = "setDelay(uint256)";
        data = abi.encodePacked(NEW_TIMELOCK_DELAY);
        bytes32 expectedTxHash = keccak256(abi.encode(timelockAddr, 0, signature, data, eta));

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, timelockAddr);
        emit Timelock.QueueTransaction(expectedTxHash, timelockAddr, 0, signature, data, eta);
        bytes32 txHash = timelock.queueTransaction(timelockAddr, 0, signature, data, eta);
        assertEq(txHash, expectedTxHash);

        vm.forward(timelock.delay() + 1);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, timelockAddr);
        emit Timelock.ExecuteTransaction(txHash, timelockAddr, 0, signature, data, eta);
        timelock.executeTransaction(timelockAddr, 0, signature, data, eta);

        assertEq(timelock.delay(), NEW_TIMELOCK_DELAY);
    }

    function test_timelock_setDelayEtaRevert() public {
        data = abi.encodeWithSelector(Timelock.setDelay.selector, NEW_TIMELOCK_DELAY);

        vm.startPrank(owner);
        vm.expectRevert(Timelock.EstimatedExecutionBlockMustSatisfyDelay.selector);
        timelock.queueTransaction(timelockAddr, 0, signature, data, block.timestamp);

        timelock.queueTransaction(timelockAddr, 0, signature, data, eta);

        vm.forward(timelock.delay());

        vm.expectRevert(Timelock.TransactionHasNotSurpassedTimeLock.selector);
        timelock.executeTransaction(timelockAddr, 0, signature, data, eta);

        vm.forward(timelock.GRACE_PERIOD() + 2);

        vm.expectRevert(Timelock.TransactionIsStale.selector);
        timelock.executeTransaction(timelockAddr, 0, signature, data, eta);
    }

    function test_timelock_cancelTransaction() public {
        data = abi.encodeWithSelector(Timelock.setDelay.selector, NEW_TIMELOCK_DELAY);

        vm.prank(owner);
        bytes32 txHash = timelock.queueTransaction(timelockAddr, 0, signature, data, eta);

        vm.forward(TestConstants.TIMELOCK_DELAY + 1);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, timelockAddr);
        emit Timelock.CancelTransaction(txHash, timelockAddr, 0, signature, data, eta);
        timelock.cancelTransaction(timelockAddr, 0, signature, data, eta);

        vm.prank(owner);
        vm.expectRevert(Timelock.TransactionHasNotBeenQueued.selector);
        timelock.executeTransaction(timelockAddr, 0, signature, data, eta);
    }
}
