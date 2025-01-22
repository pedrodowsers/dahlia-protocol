// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "@forge-std/Test.sol";
import { console } from "@forge-std/console.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { DahliaPythOracle } from "src/oracles/contracts/DahliaPythOracle.sol";
import { DahliaPythOracleFactory } from "src/oracles/contracts/DahliaPythOracleFactory.sol";
import { Timelock } from "src/oracles/contracts/Timelock.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { TestContext } from "test/common/TestContext.sol";
import { Mainnet } from "test/oracles/Constants.sol";

contract DahliaPythOracleTest is Test {
    using BoundUtils for Vm;

    TestContext ctx;
    DahliaPythOracle oracle;
    DahliaPythOracle.Delays delays;

    function setUp() public {
        vm.createSelectFork("mainnet", 20_921_816);
        ctx = new TestContext(vm);
        delays = DahliaPythOracle.Delays({ baseMaxDelay: 86_400, quoteMaxDelay: 86_400 });
        DahliaPythOracleFactory factory = ctx.createPythOracleFactory();
        oracle = DahliaPythOracle(
            factory.createPythOracle(
                DahliaPythOracle.Params({
                    baseToken: Mainnet.WETH_ERC20,
                    baseFeed: 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace,
                    quoteToken: Mainnet.UNI_ERC20,
                    quoteFeed: 0x78d185a741d07edb3412b09008b7c5cfb9bbbd7d568bf00ba737b456ba171501
                }),
                delays
            )
        );
    }

    function test_oracle_pythWithMaxDelay_success() public view {
        (uint256 _price, bool _isBadData) = oracle.getPrice();
        assertEq(_price, 349_637_857_989_881_860_139_699_580_376_458_729_677);
        assertEq(_isBadData, false);
    }

    function test_oracle_pythWithMaxDelay_setDelayNotOwner() public {
        vm.startPrank(ctx.ALICE());

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ctx.ALICE()));
        oracle.setMaximumOracleDelays(DahliaPythOracle.Delays({ quoteMaxDelay: 1, baseMaxDelay: 2 }));
        vm.stopPrank();
    }

    function test_oracle_pythWithMaxDelay_setDelayOwner() public {
        vm.pauseGasMetering();
        DahliaPythOracle.Delays memory newDelays = DahliaPythOracle.Delays({ quoteMaxDelay: 1, baseMaxDelay: 2 });

        string memory signature = "setMaximumOracleDelays((uint256,uint256))";
        bytes memory data = abi.encode(newDelays);
        console.logBytes(data);
        Timelock timelock = Timelock(oracle.owner());
        uint256 eta = block.timestamp + timelock.delay() + 1;
        uint256 value = 0;
        bytes32 expectedTxHash = keccak256(abi.encode(address(oracle), value, signature, data, eta));

        vm.startPrank(ctx.OWNER());
        vm.resumeGasMetering();

        vm.expectEmit(true, true, false, true, address(timelock));
        emit Timelock.QueueTransaction(expectedTxHash, address(oracle), value, signature, data, eta);

        bytes32 txHash = timelock.queueTransaction(address(oracle), value, signature, data, eta);
        assertEq(txHash, expectedTxHash);

        skip(timelock.delay() + 1);

        vm.expectEmit(true, true, true, true, address(oracle));
        emit DahliaPythOracle.MaximumOracleDelaysUpdated(delays, newDelays);

        vm.expectEmit(true, true, false, true, address(timelock));
        emit Timelock.ExecuteTransaction(txHash, address(oracle), value, signature, data, eta);

        timelock.executeTransaction(address(oracle), value, signature, data, eta);

        vm.pauseGasMetering();
        assertEq(oracle.quoteMaxDelay(), 1);
        assertEq(oracle.baseMaxDelay(), 2);
    }
}
