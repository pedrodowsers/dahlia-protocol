// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "forge-std/Test.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { DahliaTransUtils } from "test/common/DahliaTransUtils.sol";
import { TestConstants } from "test/common/TestConstants.sol";
import { TestContext } from "test/common/TestContext.sol";
import { TestTypes } from "test/common/TestTypes.sol";

contract WithdrawCollateralIntegrationTest is Test {
    using BoundUtils for Vm;
    using DahliaTransUtils for Vm;
    using SharesMathLib for uint256;

    TestContext.MarketContext $;
    TestContext ctx;

    function setUp() public {
        ctx = new TestContext(vm);
        $ = ctx.bootstrapMarket("USDC", "WBTC", vm.randomLltv());
    }

    function test_int_withdrawCollateral_zeros(uint256 assets) public {
        vm.pauseGasMetering();
        assets = vm.boundAmount(assets);
        vm.dahliaSupplyCollateralBy($.alice, assets, $);

        vm.resumeGasMetering();
        vm.startPrank($.alice);
        // check zero owner address
        vm.expectRevert(abi.encodeWithSelector(Errors.NotPermitted.selector, $.alice));
        $.dahlia.withdrawCollateral($.marketId, assets, address(0), $.alice);

        // check zero receiver address
        vm.expectRevert(Errors.ZeroAddress.selector);
        $.dahlia.withdrawCollateral($.marketId, assets, $.alice, address(0));

        // check zero assets
        vm.expectRevert(Errors.ZeroAssets.selector);
        $.dahlia.withdrawCollateral($.marketId, 0, $.alice, $.bob);
    }

    function test_int_withdrawCollateral_unauthorized(address attacker, uint256 assets) public {
        vm.pauseGasMetering();
        assets = vm.boundAmount(assets);
        vm.assume(attacker != $.alice);
        vm.dahliaSupplyCollateralBy($.alice, assets, $);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotPermitted.selector, attacker));
        vm.resumeGasMetering();
        $.dahlia.withdrawCollateral($.marketId, assets, $.alice, attacker);
    }

    function test_int_withdrawCollateral_unhealthyPosition(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        vm.prank($.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientCollateral.selector, pos.borrowed, 0));
        vm.resumeGasMetering();
        $.dahlia.withdrawCollateral($.marketId, pos.collateral, $.alice, $.alice);
    }

    function test_int_withdrawCollateral_success(TestTypes.MarketPosition memory pos, uint256 amountCollateralExcess) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.assume(pos.collateral < TestConstants.MAX_COLLATERAL_ASSETS);
        amountCollateralExcess = bound(
            amountCollateralExcess,
            1,
            FixedPointMathLib.min(TestConstants.MAX_COLLATERAL_ASSETS - pos.collateral, type(uint256).max / pos.price - pos.collateral)
        );
        pos.collateral += amountCollateralExcess;

        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        vm.prank($.alice);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.WithdrawCollateral($.marketId, $.alice, $.alice, $.bob, amountCollateralExcess);
        vm.resumeGasMetering();
        $.dahlia.withdrawCollateral($.marketId, amountCollateralExcess, $.alice, $.bob);
        vm.pauseGasMetering();

        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, $.alice);
        assertEq(userPos.collateral, pos.collateral - amountCollateralExcess, "collateral balance");
        assertEq($.collateralToken.balanceOf($.bob), amountCollateralExcess, "receiver balance");
        assertEq($.collateralToken.balanceOf(address($.dahlia)), pos.collateral - amountCollateralExcess, "Dahlia balance");
    }

    function test_int_withdrawCollateral_onBehalfSuccess(TestTypes.MarketPosition memory pos, uint256 amountCollateralExcess) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.assume(pos.collateral < TestConstants.MAX_COLLATERAL_ASSETS);
        amountCollateralExcess = bound(
            amountCollateralExcess,
            1,
            FixedPointMathLib.min(TestConstants.MAX_COLLATERAL_ASSETS - pos.collateral, type(uint256).max / pos.price - pos.collateral)
        );
        pos.collateral += amountCollateralExcess;

        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        vm.prank($.alice);
        $.dahlia.updatePermission($.bob, true);

        // Bob makes withdraw on behalf Alice
        vm.prank($.bob);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.WithdrawCollateral($.marketId, $.bob, $.alice, $.alice, amountCollateralExcess);
        vm.resumeGasMetering();
        $.dahlia.withdrawCollateral($.marketId, amountCollateralExcess, $.alice, $.alice);
        vm.pauseGasMetering();

        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, $.alice);
        assertEq(userPos.collateral, pos.collateral - amountCollateralExcess, "collateral balance");
        assertEq($.collateralToken.balanceOf($.alice), amountCollateralExcess, "lender balance");
        assertEq($.collateralToken.balanceOf(address($.dahlia)), pos.collateral - amountCollateralExcess, "Dahlia balance");
    }
}
