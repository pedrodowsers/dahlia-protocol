// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "@forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { DahliaOracleFactoryBase } from "src/oracles/abstracts/DahliaOracleFactoryBase.sol";

import { DahliaOracleStaticAddress } from "src/oracles/abstracts/DahliaOracleStaticAddress.sol";
import { DahliaUniswapV3Oracle } from "src/oracles/contracts/DahliaUniswapV3Oracle.sol";
import { DahliaUniswapV3OracleFactory } from "src/oracles/contracts/DahliaUniswapV3OracleFactory.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { TestContext } from "test/common/TestContext.sol";
import { Mainnet } from "test/oracles/Constants.sol";

contract DahliaUniswapV3OracleFactoryTest is Test {
    using BoundUtils for Vm;

    TestContext ctx;
    DahliaUniswapV3OracleFactory oracleFactory;

    function setUp() public {
        vm.createSelectFork("mainnet", 20_921_816);
        ctx = new TestContext(vm);
        oracleFactory = ctx.createUniswapOracleFactory();
    }

    function test_oracleFactory_zero_address() public {
        vm.expectRevert(DahliaOracleFactoryBase.ZeroTimelockAddress.selector);
        new DahliaUniswapV3OracleFactory(address(0), Mainnet.UNISWAP_STATIC_ORACLE_ADDRESS);
        vm.expectRevert(DahliaOracleStaticAddress.ZeroStaticOracleAddress.selector);
        new DahliaUniswapV3OracleFactory(address(this), address(0));
    }

    function test_oracleFactory_constructor() public {
        vm.expectEmit(true, true, true, true);
        emit DahliaOracleFactoryBase.TimelockAddressUpdated(address(this));

        vm.expectEmit(true, true, true, true);
        emit DahliaOracleStaticAddress.StaticOracleAddressUpdated(Mainnet.UNISWAP_STATIC_ORACLE_ADDRESS);

        new DahliaUniswapV3OracleFactory(address(this), Mainnet.UNISWAP_STATIC_ORACLE_ADDRESS);
    }

    function test_oracleFactory_uniswap_wethUsdc() public {
        uint32 twapDuration = 900;
        DahliaUniswapV3Oracle.Params memory params =
            DahliaUniswapV3Oracle.Params({ baseToken: Mainnet.WETH_ERC20, quoteToken: Mainnet.USDC_ERC20, uniswapV3PairAddress: Mainnet.WETH_USDC_UNI_V3_POOL });

        vm.expectEmit(true, true, true, true);
        emit Ownable.OwnershipTransferred(address(0), ctx.OWNER());

        vm.expectEmit(true, true, true, true);
        emit DahliaOracleStaticAddress.StaticOracleAddressUpdated(Mainnet.UNISWAP_STATIC_ORACLE_ADDRESS);

        vm.expectEmit(true, true, true, true);
        emit DahliaUniswapV3Oracle.TwapDurationUpdated(0, twapDuration);

        vm.expectEmit(true, true, true, true);
        emit DahliaUniswapV3Oracle.ParamsUpdated(params);

        vm.expectEmit(true, false, true, true, address(oracleFactory));
        emit DahliaUniswapV3OracleFactory.DahliaUniswapV3OracleCreated(address(this), address(0));

        address oracle = oracleFactory.createUniswapOracle(params, twapDuration);
        (uint256 price, bool isBadData) = DahliaUniswapV3Oracle(oracle).getPrice();
        assertEq(price, 2_412_486_481_775_144_671_894_069_994);
        assertEq(((price * 1e18) / 1e6) / 1e36, 2412); // 2412 USDC per 1 WETH
        assertEq(isBadData, false);

        address oracle2 = oracleFactory.createUniswapOracle(params, twapDuration);
        assertEq(oracle, oracle2, "should be the same address");
    }
}
