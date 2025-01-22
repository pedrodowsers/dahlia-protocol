// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "@forge-std/Test.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { MarketMath } from "src/core/helpers/MarketMath.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { DahliaTransUtils } from "test/common/DahliaTransUtils.sol";
import { TestConstants, TestContext } from "test/common/TestContext.sol";
import { TestTypes } from "test/common/TestTypes.sol";

contract RepayAndWithdrawIntegrationTest is Test {
    using FixedPointMathLib for uint256;
    using SharesMathLib for uint256;
    using MarketMath for uint256;
    using BoundUtils for Vm;
    using DahliaTransUtils for Vm;

    TestContext.MarketContext $;
    TestContext ctx;

    function setUp() public {
        ctx = new TestContext(vm);
        $ = ctx.bootstrapMarket("USDC", "WBTC", vm.randomLltv());
    }

    function test_int_repayAndWithdraw_marketNotDeployed(IDahlia.MarketId marketIdFuzz, uint256 assets) public {
        vm.assume(!vm.marketsEq($.marketId, marketIdFuzz));
        vm.assume(assets > 0);
        vm.prank($.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.WrongStatus.selector, IDahlia.MarketStatus.Uninitialized));
        $.dahlia.repayAndWithdraw(marketIdFuzz, assets, 0, assets, $.alice, $.alice);
    }

    function test_int_repayAndWithdraw_zeroAmount() public {
        vm.expectRevert(Errors.ZeroAssets.selector);
        vm.prank($.alice);
        $.dahlia.repayAndWithdraw($.marketId, 0, 0, 0, $.alice, $.alice);
    }

    function test_int_repayAndWithdraw_zeroAddress(uint256 assets) public {
        vm.assume(assets > 0);
        vm.startPrank($.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotPermitted.selector, $.alice));
        $.dahlia.repayAndWithdraw($.marketId, assets, assets, 0, address(0), $.alice);
        vm.startPrank($.alice);
        vm.expectRevert(Errors.ZeroAddress.selector);
        $.dahlia.repayAndWithdraw($.marketId, assets, assets, 0, $.alice, address(0));
    }

    function test_int_repayAndWithdraw_inconsistentAssetsOrSharesInput(uint256 amount, uint256 shares) public {
        amount = vm.boundAmount(amount);
        shares = bound(shares, 1, TestConstants.MAX_TEST_SHARES);

        vm.prank($.alice);
        vm.expectRevert(Errors.InconsistentAssetsOrSharesInput.selector);
        $.dahlia.repayAndWithdraw($.marketId, amount, amount, shares, $.alice, $.alice);
    }

    function test_int_repayAndWithdraw_byAssets(TestTypes.MarketPosition memory pos, uint256 amountRepaid) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        amountRepaid = bound(amountRepaid, 1, pos.borrowed);
        uint256 expectedBorrowShares = pos.borrowed.toSharesUp(0, 0);
        uint256 expectedRepaidShares = amountRepaid.toSharesDown(pos.borrowed, expectedBorrowShares);
        uint256 amountCollateral = amountRepaid.lendToCollateralUp(pos.price).mulPercentUp($.marketConfig.lltv);

        vm.startPrank($.alice);
        $.loanToken.approve(address($.dahlia), amountRepaid);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.Repay($.marketId, $.alice, $.alice, amountRepaid, expectedRepaidShares);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.WithdrawCollateral($.marketId, $.alice, $.alice, $.alice, amountCollateral);

        vm.resumeGasMetering();
        (uint256 returnAssets, uint256 returnShares) = $.dahlia.repayAndWithdraw($.marketId, amountCollateral, amountRepaid, 0, $.alice, $.alice);
        vm.pauseGasMetering();
        vm.stopPrank();

        expectedBorrowShares -= expectedRepaidShares;

        IDahlia.Market memory stateAfter = $.dahlia.getMarket($.marketId);
        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, $.alice);
        assertEq(returnAssets, amountRepaid, "returned asset amount");
        assertEq(returnShares, expectedRepaidShares, "returned shares amount");
        assertEq(userPos.borrowShares, expectedBorrowShares, "borrow shares");
        assertEq(stateAfter.totalBorrowAssets, pos.borrowed - amountRepaid, "total borrow");
        assertEq(stateAfter.totalBorrowShares, expectedBorrowShares, "total borrow shares");
        assertEq($.loanToken.balanceOf($.alice), pos.borrowed - amountRepaid, "RECEIVER balance");
        assertEq($.loanToken.balanceOf(address($.vault)), pos.lent - pos.borrowed + amountRepaid, "Dahlia loan balance");
        assertEq($.collateralToken.balanceOf($.alice), amountCollateral, "borrower collateral");
        assertEq($.collateralToken.balanceOf(address($.dahlia)), pos.collateral - amountCollateral, "Dahlia collateral balance");
    }

    function test_int_repayAndWithdraw_onBehalfOfOwner(TestTypes.MarketPosition memory pos, uint256 amountRepaid) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        amountRepaid = bound(amountRepaid, 1, pos.borrowed);
        uint256 expectedBorrowShares = pos.borrowed.toSharesUp(0, 0);
        uint256 expectedRepaidShares = amountRepaid.toSharesDown(pos.borrowed, expectedBorrowShares);
        uint256 amountCollateral = amountRepaid.lendToCollateralUp(pos.price).mulPercentUp($.marketConfig.lltv);

        address caller = ctx.createWallet("CALLER");
        vm.startPrank($.alice);
        $.dahlia.updatePermission(caller, true);
        $.loanToken.approve(address($.dahlia), amountRepaid);
        vm.stopPrank();

        vm.startPrank(caller);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.Repay($.marketId, caller, $.alice, amountRepaid, expectedRepaidShares);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.WithdrawCollateral($.marketId, caller, $.alice, $.alice, amountCollateral);

        vm.resumeGasMetering();
        (uint256 returnAssets, uint256 returnShares) = $.dahlia.repayAndWithdraw($.marketId, amountCollateral, amountRepaid, 0, $.alice, $.alice);
        vm.pauseGasMetering();
        vm.stopPrank();

        expectedBorrowShares -= expectedRepaidShares;

        IDahlia.Market memory stateAfter = $.dahlia.getMarket($.marketId);
        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, $.alice);
        assertEq($.loanToken.balanceOf(caller), 0, "caller balance");
        assertEq($.collateralToken.balanceOf(caller), 0, "caller balance");

        assertEq(returnAssets, amountRepaid, "returned asset amount");
        assertEq(returnShares, expectedRepaidShares, "returned shares amount");
        assertEq(userPos.borrowShares, expectedBorrowShares, "borrow shares");
        assertEq(stateAfter.totalBorrowAssets, pos.borrowed - amountRepaid, "total borrow");
        assertEq(stateAfter.totalBorrowShares, expectedBorrowShares, "total borrow shares");
        assertEq($.loanToken.balanceOf($.alice), pos.borrowed - amountRepaid, "RECEIVER balance");
        assertEq($.loanToken.balanceOf(address($.vault)), pos.lent - pos.borrowed + amountRepaid, "Dahlia loan balance");
        assertEq($.collateralToken.balanceOf($.alice), amountCollateral, "borrower collateral");
        assertEq($.collateralToken.balanceOf(address($.dahlia)), pos.collateral - amountCollateral, "Dahlia collateral balance");
    }

    function test_int_repayAndWithdraw_byShares(TestTypes.MarketPosition memory pos, uint256 sharesRepaid) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        uint256 expectedBorrowShares = pos.borrowed.toSharesUp(0, 0);
        sharesRepaid = bound(sharesRepaid, 1, expectedBorrowShares);
        uint256 expectedAmountRepaid = sharesRepaid.toAssetsUp(pos.borrowed, expectedBorrowShares);
        uint256 amountCollateral = expectedAmountRepaid.lendToCollateralUp(pos.price).mulPercentUp($.marketConfig.lltv);

        vm.startPrank($.alice);
        $.loanToken.approve(address($.dahlia), expectedAmountRepaid);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.Repay($.marketId, $.alice, $.alice, expectedAmountRepaid, sharesRepaid);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.WithdrawCollateral($.marketId, $.alice, $.alice, $.alice, amountCollateral);
        vm.resumeGasMetering();
        (uint256 returnAssets, uint256 returnShares) = $.dahlia.repayAndWithdraw($.marketId, amountCollateral, 0, sharesRepaid, $.alice, $.alice);
        vm.pauseGasMetering();
        vm.stopPrank();

        expectedBorrowShares -= sharesRepaid;

        IDahlia.Market memory stateAfter = $.dahlia.getMarket($.marketId);
        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, $.alice);
        assertEq(returnAssets, expectedAmountRepaid, "returned asset amount");
        assertEq(returnShares, sharesRepaid, "returned shares amount");
        assertEq(userPos.borrowShares, expectedBorrowShares, "borrow shares");
        assertEq(stateAfter.totalBorrowAssets, pos.borrowed - expectedAmountRepaid, "total borrow");
        assertEq(stateAfter.totalBorrowShares, expectedBorrowShares, "total borrow shares");

        assertEq($.loanToken.balanceOf($.alice), pos.borrowed - expectedAmountRepaid, "RECEIVER balance");
        assertEq($.loanToken.balanceOf(address($.vault)), pos.lent - pos.borrowed + expectedAmountRepaid, "Dahlia balance");

        assertEq($.collateralToken.balanceOf($.alice), amountCollateral, "borrower collateral");
        assertEq($.collateralToken.balanceOf(address($.dahlia)), pos.collateral - amountCollateral, "Dahlia collateral balance");
    }
}
