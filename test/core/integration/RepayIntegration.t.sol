// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "@forge-std/Test.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { DahliaTransUtils } from "test/common/DahliaTransUtils.sol";
import { TestConstants, TestContext } from "test/common/TestContext.sol";
import { TestTypes } from "test/common/TestTypes.sol";

contract RepayIntegrationTest is Test {
    using FixedPointMathLib for uint256;
    using SharesMathLib for uint256;
    using BoundUtils for Vm;
    using DahliaTransUtils for Vm;

    TestContext.MarketContext $;
    TestContext ctx;

    function setUp() public {
        ctx = new TestContext(vm);
        $ = ctx.bootstrapMarket("USDC", "WBTC", vm.randomLltv());
    }

    function test_int_repay_marketNotDeployed(IDahlia.MarketId marketIdFuzz, uint256 assets) public {
        vm.assume(!vm.marketsEq($.marketId, marketIdFuzz));
        vm.prank($.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.WrongStatus.selector, IDahlia.MarketStatus.Uninitialized));
        $.dahlia.repay(marketIdFuzz, assets, 0, $.alice, TestConstants.EMPTY_CALLBACK);
    }

    function test_int_repay_zeroAmount() public {
        vm.expectRevert(Errors.InconsistentAssetsOrSharesInput.selector);
        vm.prank($.alice);
        $.dahlia.repay($.marketId, 0, 0, $.alice, TestConstants.EMPTY_CALLBACK);
    }

    function test_int_repay_zeroAddress(uint256 assets) public {
        vm.startPrank($.alice);
        vm.expectRevert(Errors.ZeroAddress.selector);
        $.dahlia.repay($.marketId, assets, 0, address(0), TestConstants.EMPTY_CALLBACK);
    }

    function test_int_repay_InconsistentAssetsOrSharesInput(uint256 amount, uint256 shares) public {
        amount = vm.boundAmount(amount);
        shares = bound(shares, 1, TestConstants.MAX_TEST_SHARES);

        vm.prank($.alice);
        vm.expectRevert(Errors.InconsistentAssetsOrSharesInput.selector);
        $.dahlia.repay($.marketId, amount, shares, $.alice, TestConstants.EMPTY_CALLBACK);
    }

    function test_int_repay_byAssets(TestTypes.MarketPosition memory pos, uint256 amountRepaid) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        amountRepaid = bound(amountRepaid, 1, pos.borrowed);
        uint256 expectedBorrowShares = pos.borrowed.toSharesUp(0, 0);
        uint256 expectedRepaidShares = amountRepaid.toSharesDown(pos.borrowed, expectedBorrowShares);

        vm.dahliaPrepareLoanBalanceFor($.bob, amountRepaid, $);

        vm.prank($.bob);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.Repay($.marketId, $.bob, $.alice, amountRepaid, expectedRepaidShares);
        vm.resumeGasMetering();
        (uint256 returnAssets, uint256 returnShares) = $.dahlia.repay($.marketId, amountRepaid, 0, $.alice, TestConstants.EMPTY_CALLBACK);
        vm.pauseGasMetering();

        expectedBorrowShares -= expectedRepaidShares;

        IDahlia.Market memory stateAfter = $.dahlia.getMarket($.marketId);
        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, $.alice);
        assertEq(returnAssets, amountRepaid, "returned asset amount");
        assertEq(returnShares, expectedRepaidShares, "returned shares amount");
        assertEq(userPos.borrowShares, expectedBorrowShares, "borrow shares");
        assertEq(stateAfter.totalBorrowAssets, pos.borrowed - amountRepaid, "total borrow");
        assertEq(stateAfter.totalBorrowShares, expectedBorrowShares, "total borrow shares");
        assertEq($.loanToken.balanceOf($.alice), pos.borrowed, "RECEIVER balance");
        assertEq($.loanToken.balanceOf(address($.vault)), pos.lent - pos.borrowed + amountRepaid, "Dahlia balance");
    }

    function test_int_repay_byShares(TestTypes.MarketPosition memory pos, uint256 sharesRepaid) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        uint256 expectedBorrowShares = pos.borrowed.toSharesUp(0, 0);
        sharesRepaid = bound(sharesRepaid, 1, expectedBorrowShares);
        uint256 expectedAmountRepaid = sharesRepaid.toAssetsUp(pos.borrowed, expectedBorrowShares);

        vm.dahliaPrepareLoanBalanceFor($.bob, expectedAmountRepaid, $);

        vm.prank($.bob);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.Repay($.marketId, $.bob, $.alice, expectedAmountRepaid, sharesRepaid);
        vm.resumeGasMetering();
        (uint256 returnAssets, uint256 returnShares) = $.dahlia.repay($.marketId, 0, sharesRepaid, $.alice, TestConstants.EMPTY_CALLBACK);
        vm.pauseGasMetering();

        expectedBorrowShares -= sharesRepaid;

        IDahlia.Market memory stateAfter = $.dahlia.getMarket($.marketId);
        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, $.alice);
        assertEq(returnAssets, expectedAmountRepaid, "returned asset amount");
        assertEq(returnShares, sharesRepaid, "returned shares amount");
        assertEq(userPos.borrowShares, expectedBorrowShares, "borrow shares");
        assertEq(stateAfter.totalBorrowAssets, pos.borrowed - expectedAmountRepaid, "total borrow");
        assertEq(stateAfter.totalBorrowShares, expectedBorrowShares, "total borrow shares");

        assertEq($.loanToken.balanceOf($.alice), pos.borrowed, "RECEIVER balance");
        assertEq($.loanToken.balanceOf(address($.vault)), pos.lent - pos.borrowed + expectedAmountRepaid, "Dahlia balance");
    }

    function test_int_repay_maxOnBehalf(uint256 shares) public {
        vm.pauseGasMetering();
        shares = vm.boundShares(shares);
        uint256 assets = shares.toAssetsUp(0, 0);

        vm.dahliaLendBy($.carol, assets, $);
        vm.dahliaSupplyCollateralBy($.alice, TestConstants.MAX_COLLATERAL_ASSETS, $);
        vm.dahliaBorrowBy($.alice, assets, $);

        $.loanToken.setBalance($.bob, assets);

        vm.startPrank($.bob);
        $.loanToken.approve(address($.dahlia), assets);

        vm.resumeGasMetering();
        $.dahlia.repay($.marketId, 0, shares, $.alice, TestConstants.EMPTY_CALLBACK);
        vm.pauseGasMetering();
        vm.stopPrank();

        vm.startPrank($.alice);
        $.dahlia.withdrawCollateral($.marketId, assets, $.alice, $.alice);
        vm.stopPrank();
    }
}
