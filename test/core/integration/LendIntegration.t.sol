// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

import { Test, Vm } from "forge-std/Test.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { DahliaTransUtils } from "test/common/DahliaTransUtils.sol";
import { TestContext } from "test/common/TestContext.sol";

contract LendIntegrationTest is Test {
    using FixedPointMathLib for uint256;
    using SharesMathLib for uint256;
    using BoundUtils for Vm;
    using DahliaTransUtils for Vm;

    TestContext.MarketContext $;

    function setUp() public {
        $ = (new TestContext(vm)).bootstrapMarket("USDC", "WBTC", vm.randomLltv());
    }

    function test_int_lend_marketNotDeployed(IDahlia.MarketId marketIdFuzz, uint256 assets) public {
        vm.assume(!vm.marketsEq($.marketId, marketIdFuzz));
        vm.startPrank($.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotPermitted.selector, $.alice));
        $.dahlia.lend(marketIdFuzz, assets, 0, $.alice);
    }

    function test_int_lend_zeroAmount() public {
        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);
        market.vault.deposit(0, $.alice);
    }

    function test_int_lend_directCallNotPermitted(uint256 assets) public {
        IERC20($.marketConfig.loanToken).approve(address($.dahlia), assets);
        vm.startPrank($.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotPermitted.selector, $.alice));
        $.dahlia.lend($.marketId, assets, 0, $.alice);
    }

    function test_int_lend_zeroAddress(uint256 assets) public {
        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);
        vm.startPrank(address(market.vault));
        vm.expectRevert(Errors.ZeroAddress.selector);
        $.dahlia.lend($.marketId, assets, 0, address(0));
    }

    function test_int_lend_byAssets(uint256 amount) public {
        vm.pauseGasMetering();
        amount = vm.boundAmount(amount);
        uint256 expectedLendShares = amount.toSharesDown(0, 0);

        $.loanToken.setBalance($.alice, amount);

        vm.startPrank($.alice);
        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);
        $.loanToken.approve(address(market.vault), amount);

        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.Lend($.marketId, address(market.vault), $.bob, amount, expectedLendShares);
        vm.resumeGasMetering();
        (uint256 _shares) = market.vault.deposit(amount, $.bob);
        vm.pauseGasMetering();
        vm.stopPrank();

        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, $.bob);

        assertEq(_shares, expectedLendShares, "returned shares amount");
        assertEq(userPos.lendShares, expectedLendShares, "supply shares");
        assertEq($.dahlia.getMarket($.marketId).totalLendAssets, amount, "total supply");
        assertEq($.dahlia.getMarket($.marketId).totalLendShares, expectedLendShares, "total supply shares");
        assertEq($.dahlia.getMarket($.marketId).totalLendPrincipalAssets, amount, "total principal assets");
        assertEq($.dahlia.getPosition($.marketId, $.bob).lendPrincipalAssets, amount, "user principal assets");
        assertEq($.loanToken.balanceOf($.alice), 0, "Alice balance");
        assertEq($.loanToken.balanceOf(address($.vault)), amount, "Dahlia balance");
    }
}
