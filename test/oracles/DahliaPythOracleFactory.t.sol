// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "@forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { CREATE3 } from "@solady/utils/CREATE3.sol";
import { DahliaOracleFactoryBase } from "src/oracles/abstracts/DahliaOracleFactoryBase.sol";
import { DahliaOracleStaticAddress } from "src/oracles/abstracts/DahliaOracleStaticAddress.sol";
import { DahliaPythOracle } from "src/oracles/contracts/DahliaPythOracle.sol";
import { DahliaPythOracleFactory } from "src/oracles/contracts/DahliaPythOracleFactory.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { TestContext } from "test/common/TestContext.sol";
import { Mainnet } from "test/oracles/Constants.sol";

contract DahliaPythOracleFactoryTest is Test {
    using BoundUtils for Vm;

    uint256 public immutable ORACLE_PRECISION = 1e18;
    TestContext public ctx;
    DahliaPythOracleFactory public oracleFactory;

    function setUp() public {
        vm.createSelectFork("mainnet", 20_921_816);
        ctx = new TestContext(vm);
        oracleFactory = ctx.createPythOracleFactory();
    }

    function test_PythOracleFactory_zero_address() public {
        vm.expectRevert(DahliaOracleFactoryBase.ZeroTimelockAddress.selector);
        new DahliaPythOracleFactory(address(0), Mainnet.PYTH_STATIC_ORACLE_ADDRESS);
        vm.expectRevert(DahliaOracleStaticAddress.ZeroStaticOracleAddress.selector);
        new DahliaPythOracleFactory(address(this), address(0));
    }

    function test_PythOracleFactory_constructor() public {
        vm.expectEmit(true, true, true, true);
        emit DahliaOracleFactoryBase.TimelockAddressUpdated(address(this));

        vm.expectEmit(true, true, true, true);
        emit DahliaOracleStaticAddress.StaticOracleAddressUpdated(Mainnet.PYTH_STATIC_ORACLE_ADDRESS);

        new DahliaPythOracleFactory(address(this), Mainnet.PYTH_STATIC_ORACLE_ADDRESS);
    }

    function test_oracleFactory_pyth_wethUniWithBadDataFromPyth() public {
        vm.pauseGasMetering();

        address timelock = address(ctx.createTimelock());

        DahliaPythOracle.Params memory params = DahliaPythOracle.Params({
            baseToken: Mainnet.WETH_ERC20,
            baseFeed: 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace,
            quoteToken: Mainnet.UNI_ERC20,
            quoteFeed: 0x78d185a741d07edb3412b09008b7c5cfb9bbbd7d568bf00ba737b456ba171501
        });
        DahliaPythOracle.Delays memory delays = DahliaPythOracle.Delays({ baseMaxDelay: 86_400, quoteMaxDelay: 86_400 });

        vm.expectEmit(true, true, true, true);
        emit Ownable.OwnershipTransferred(address(0), timelock);

        vm.expectEmit(true, true, true, true);
        emit DahliaOracleStaticAddress.StaticOracleAddressUpdated(Mainnet.PYTH_STATIC_ORACLE_ADDRESS);

        vm.expectEmit(true, true, true, true);
        emit DahliaPythOracle.ParamsUpdated(params);

        vm.expectEmit(true, true, true, true);
        emit DahliaPythOracle.MaximumOracleDelaysUpdated(DahliaPythOracle.Delays({ baseMaxDelay: 0, quoteMaxDelay: 0 }), delays);

        bytes memory encodedArgs = abi.encode(oracleFactory.timelockAddress(), params, delays, oracleFactory.STATIC_ORACLE_ADDRESS());
        bytes32 salt = keccak256(encodedArgs);
        address oracleAddress = CREATE3.predictDeterministicAddress(salt, address(oracleFactory));

        vm.expectEmit(true, true, true, true, address(oracleFactory));
        emit DahliaPythOracleFactory.DahliaPythOracleCreated(address(this), oracleAddress);

        vm.resumeGasMetering();
        DahliaPythOracle oracle = DahliaPythOracle(oracleFactory.createPythOracle(params, delays));
        (uint256 price, bool isBadData) = oracle.getPrice();
        vm.pauseGasMetering();
        assertEq(oracle.ORACLE_PRECISION(), 10 ** 36);
        assertEq(oracle.BASE_TOKEN(), Mainnet.WETH_ERC20);
        assertEq(oracle.BASE_FEED(), 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace);
        assertEq(oracle.baseMaxDelay(), 86_400);
        assertEq(oracle.QUOTE_TOKEN(), Mainnet.UNI_ERC20);
        assertEq(oracle.QUOTE_FEED(), 0x78d185a741d07edb3412b09008b7c5cfb9bbbd7d568bf00ba737b456ba171501);
        assertEq(oracle.quoteMaxDelay(), 86_400);
        assertEq(oracle.STATIC_ORACLE_ADDRESS(), oracleFactory.STATIC_ORACLE_ADDRESS());
        assertEq(price, 349_637_857_989_881_860_139_699_580_376_458_729_677);
        assertEq(((price * 1e18) / 1e18) / 1e36, 349); // 349 UNI per 1 WETH
        assertEq(isBadData, false);

        address oracle2 = oracleFactory.createPythOracle(params, delays);
        assertEq(address(oracle), address(oracle2), "should be the same address");
    }
}
