// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { AggregatorV3Interface } from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { Test, Vm } from "@forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { DahliaOracleFactoryBase } from "src/oracles/abstracts/DahliaOracleFactoryBase.sol";
import { DahliaChainlinkOracle } from "src/oracles/contracts/DahliaChainlinkOracle.sol";
import { DahliaChainlinkOracleFactory } from "src/oracles/contracts/DahliaChainlinkOracleFactory.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { TestContext } from "test/common/TestContext.sol";
import { Mainnet } from "test/oracles/Constants.sol";

contract DahliaChainlinkOracleFactoryTest is Test {
    using BoundUtils for Vm;

    TestContext private ctx;
    DahliaChainlinkOracleFactory private oracleFactory;

    function setUp() public {
        vm.createSelectFork("mainnet", 20_921_816);
        ctx = new TestContext(vm);
        oracleFactory = ctx.createChainlinkOracleFactory();
    }

    function test_oracleFactory_zero_address() public {
        vm.expectRevert(DahliaOracleFactoryBase.ZeroTimelockAddress.selector);
        new DahliaChainlinkOracleFactory(address(0));
    }

    function test_oracleFactory_chainlink() public {
        DahliaChainlinkOracle.Params memory params = DahliaChainlinkOracle.Params({
            baseToken: Mainnet.USDC_ERC20,
            baseFeedPrimary: AggregatorV3Interface(Mainnet.USDC_USD_CHAINLINK_ORACLE),
            baseFeedSecondary: AggregatorV3Interface(address(0)),
            quoteToken: Mainnet.WBTC_ERC20,
            quoteFeedPrimary: AggregatorV3Interface(Mainnet.BTC_USD_CHAINLINK_ORACLE),
            quoteFeedSecondary: AggregatorV3Interface(Mainnet.WBTC_BTC_CHAINLINK_ORACLE)
        });

        DahliaChainlinkOracle.Delays memory delays = DahliaChainlinkOracle.Delays({
            baseMaxDelayPrimary: 86_400,
            baseMaxDelaySecondary: 0,
            quoteMaxDelayPrimary: 86_400,
            quoteMaxDelaySecondary: 86_400
        });

        vm.expectEmit(true, true, true, true);
        emit Ownable.OwnershipTransferred(address(0), ctx.OWNER());

        vm.expectEmit(true, true, true, true);
        emit DahliaChainlinkOracle.ParamsUpdated(params);

        vm.expectEmit(true, true, true, true);
        emit DahliaChainlinkOracle.MaximumOracleDelayUpdated(delays);

        vm.expectEmit(true, false, true, true, address(oracleFactory));
        emit DahliaChainlinkOracleFactory.DahliaChainlinkOracleCreated(address(this), address(0));

        /// @dev USDC is collateral, WBTC is loan, then result is 0.000016xxx
        DahliaChainlinkOracle oracle = DahliaChainlinkOracle(oracleFactory.createChainlinkOracle(params, delays));
        (uint256 price, bool isBadData) = oracle.getPrice();
        assertEq(price, 1_611_859_162_144_102_979_080_952_870_358_934);
        assertEq(isBadData, false);

        address oracle2 = oracleFactory.createChainlinkOracle(params, delays);
        assertEq(address(oracle), oracle2, "should be the same address");
    }

    function test_oracleFactory_paxg_chainlink() public {
        /// @dev PAXG is collateral, USDC is loan, then result is 2617
        DahliaChainlinkOracle oracle = DahliaChainlinkOracle(
            oracleFactory.createChainlinkOracle(
                DahliaChainlinkOracle.Params({
                    baseToken: 0x45804880De22913dAFE09f4980848ECE6EcbAf78,
                    baseFeedPrimary: AggregatorV3Interface(0x7C4561Bb0F2d6947BeDA10F667191f6026E7Ac0c),
                    baseFeedSecondary: AggregatorV3Interface(address(0)),
                    quoteToken: Mainnet.USDC_ERC20,
                    quoteFeedPrimary: AggregatorV3Interface(Mainnet.USDC_USD_CHAINLINK_ORACLE),
                    quoteFeedSecondary: AggregatorV3Interface(address(0))
                }),
                DahliaChainlinkOracle.Delays({ baseMaxDelayPrimary: 86_400, baseMaxDelaySecondary: 0, quoteMaxDelayPrimary: 86_400, quoteMaxDelaySecondary: 0 })
            )
        );
        (uint256 price, bool isBadData) = oracle.getPrice();
        assertEq(price, 2_617_340_351_185_118_511_851_185_118);
        assertEq(((price * 1e18) / 1e6) / 1e36, 2617); // 2617 USDC per 1 PAXG
        assertEq(isBadData, false);
    }

    function test_oracleFactory_wethUsdc() public {
        DahliaChainlinkOracle oracle = DahliaChainlinkOracle(
            oracleFactory.createChainlinkOracle(
                DahliaChainlinkOracle.Params({
                    baseToken: Mainnet.WETH_ERC20,
                    baseFeedPrimary: AggregatorV3Interface(Mainnet.ETH_USD_CHAINLINK_ORACLE),
                    baseFeedSecondary: AggregatorV3Interface(address(0)),
                    quoteToken: Mainnet.USDC_ERC20,
                    quoteFeedPrimary: AggregatorV3Interface(Mainnet.USDC_USD_CHAINLINK_ORACLE),
                    quoteFeedSecondary: AggregatorV3Interface(address(0))
                }),
                DahliaChainlinkOracle.Delays({ baseMaxDelayPrimary: 86_400, baseMaxDelaySecondary: 0, quoteMaxDelayPrimary: 86_400, quoteMaxDelaySecondary: 0 })
            )
        );
        (uint256 price, bool isBadData) = oracle.getPrice();
        assertEq(price, 2_404_319_134_993_499_349_934_993_499);
        assertEq(((price * 1e18) / 1e6) / 1e36, 2404); // 2404 USDC per 1 ETH
        assertEq(isBadData, false);
    }
}
