// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "@forge-std/Test.sol";
import { DahliaUniswapV3Oracle, Ownable } from "src/oracles/contracts/DahliaUniswapV3Oracle.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { TestContext } from "test/common/TestContext.sol";
import { Mainnet } from "test/oracles/Constants.sol";

contract DahliaUniswapV3OracleTest is Test {
    using BoundUtils for Vm;

    TestContext ctx;
    DahliaUniswapV3Oracle oracle;

    function setUp() public {
        vm.createSelectFork("mainnet", 20_921_816);
        ctx = new TestContext(vm);
        address owner = ctx.createWallet("OWNER");
        uint32 twapDuration = 900;
        oracle = new DahliaUniswapV3Oracle(
            owner,
            DahliaUniswapV3Oracle.Params({ baseToken: Mainnet.WETH_ERC20, quoteToken: Mainnet.UNI_ERC20, uniswapV3PairAddress: Mainnet.UNI_ETH_UNI_V3_POOL }),
            Mainnet.UNISWAP_STATIC_ORACLE_ADDRESS,
            twapDuration
        );
    }

    function test_oracle_uniswap_success() public view {
        (uint256 _price, bool _isBadData) = oracle.getPrice();
        assertEq(_price, 342_170_188_147_668_813_010_937_084_335_830_514_402);
        assertEq(((_price * 1e18) / 1e18) / 1e36, 342); // 342 UNI per 1 ETH
        assertEq(_isBadData, false);
    }

    function test_oracle_uniswap_setTwapDurationNotOwner() public {
        address alice = ctx.createWallet("ALICE");
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(alice)));
        oracle.setTwapDuration(500);
        vm.stopPrank();
    }

    function test_oracle_uniswap_setTwapDurationOwner() public {
        address owner = ctx.createWallet("OWNER");
        vm.startPrank(owner);

        oracle.setTwapDuration(500);

        vm.stopPrank();

        assertEq(oracle.twapDuration(), 500);
    }

    function test_oracle_uniswap_setTwapDurationTooShort() public {
        address owner = ctx.createWallet("OWNER");
        vm.prank(owner);
        vm.expectRevert(DahliaUniswapV3Oracle.TwapDurationIsTooShort.selector);
        oracle.setTwapDuration(299);
    }

    function test_oracle_createWithShortTwapDuration() public {
        vm.expectRevert(DahliaUniswapV3Oracle.TwapDurationIsTooShort.selector);
        new DahliaUniswapV3Oracle(
            address(0x1),
            DahliaUniswapV3Oracle.Params({ baseToken: Mainnet.WETH_ERC20, quoteToken: Mainnet.UNI_ERC20, uniswapV3PairAddress: Mainnet.UNI_ETH_UNI_V3_POOL }),
            Mainnet.UNISWAP_STATIC_ORACLE_ADDRESS,
            200
        );
    }
}
