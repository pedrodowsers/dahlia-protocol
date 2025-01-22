// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { AggregatorV3Interface } from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { Test, Vm } from "@forge-std/Test.sol";
import { ChainlinkWstETHToETH } from "src/oracles/contracts/ChainlinkWstETHToETH.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { TestContext } from "test/common/TestContext.sol";
import { Mainnet } from "test/oracles/Constants.sol";

contract ChainlinkWstETHToETHTest is Test {
    using BoundUtils for Vm;

    TestContext ctx;
    ChainlinkWstETHToETH oracle;
    AggregatorV3Interface constant stEthToEthFeed = AggregatorV3Interface(Mainnet.STETH_ETH_CHAINLINK_ORACLE);

    function setUp() public {
        vm.createSelectFork("mainnet", 21_630_303);
        ctx = new TestContext(vm);

        oracle = new ChainlinkWstETHToETH(ChainlinkWstETHToETH.Params({ wstEth: Mainnet.WSTETH_ERC20, stEthToEthFeed: address(stEthToEthFeed) }));
    }

    function test_ChainlinkWstETHToETH_getRoundData() public {
        (uint80 roundId,,,,) = oracle.latestRoundData();
        vm.expectRevert(ChainlinkWstETHToETH.UnsupportedMethod.selector);
        oracle.getRoundData(roundId);
    }

    function test_ChainlinkWstETHToETH_latestRoundData() public view {
        (uint80 roundId1, int256 answer1, uint256 startedAt1, uint256 updatedAt1, uint80 answeredInRound1) = stEthToEthFeed.latestRoundData();
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = oracle.latestRoundData();
        assertEq(roundId, roundId1, "roundId=roundId1");
        assertEq(startedAt, startedAt1, "startedAt=startedAt1");
        assertEq(updatedAt, updatedAt1, "updatedAt=updatedAt");
        assertEq(answeredInRound, answeredInRound1, "answeredInRound=answeredInRound1");
        assertEq(answer1, 999_133_585_167_552_700, "answer1"); // almost 1e18
        assertLt(answer1, int256(10 ** stEthToEthFeed.decimals())); // < 1 ether

        assertEq(roundId, 36_893_488_147_419_103_486, "roundId");
        assertEq(startedAt, 1_736_913_811, "startedAt");
        assertEq(updatedAt, 1_736_913_827, "updatedAt");
        assertEq(answeredInRound, roundId, "answeredInRound");
        assertEq(answer, 1_189_711_017_776_113_580, "answer");
    }

    function test_ChainlinkWstETHToETH_interface() public view {
        assertEq(oracle.decimals(), 18, "oracle decimals");
        assertEq(oracle.version(), 1, "oracle version");
        assertEq(oracle.description(), "WSTETH / ETH", "oracle description");
        assertEq(address(oracle.WST_ETH()), Mainnet.WSTETH_ERC20, "oracle WST_ETH");
    }
}
