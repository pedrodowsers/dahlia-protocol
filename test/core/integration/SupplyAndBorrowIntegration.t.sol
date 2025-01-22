// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "@forge-std/Test.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { MarketMath } from "src/core/helpers/MarketMath.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { DahliaTransUtils } from "test/common/DahliaTransUtils.sol";
import { TestConstants, TestContext } from "test/common/TestContext.sol";
import { TestTypes } from "test/common/TestTypes.sol";

contract SupplyAndBorrowIntegrationTest is Test {
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;
    using SharesMathLib for uint256;
    using MarketMath for uint256;
    using BoundUtils for Vm;
    using DahliaTransUtils for Vm;

    uint256 nonce;

    TestContext.MarketContext $;
    TestContext ctx;

    function setUp() public {
        ctx = new TestContext(vm);
        $ = ctx.bootstrapMarket("USDC", "WBTC", 80_000);
    }

    function test_int_supplyAndBorrow_marketNotDeployed(IDahlia.MarketId marketIdFuzz, uint256 assets) public {
        vm.assume(assets > 0);
        vm.assume(!vm.marketsEq($.marketId, marketIdFuzz));
        vm.prank($.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.WrongStatus.selector, IDahlia.MarketStatus.Uninitialized));
        $.dahlia.supplyAndBorrow(marketIdFuzz, assets, assets, $.alice, $.alice);
    }

    function test_int_supplyAndBorrow_zeroAmount() public {
        vm.expectRevert(Errors.ZeroAssets.selector);
        vm.prank($.alice);
        $.dahlia.supplyAndBorrow($.marketId, 0, 0, $.alice, $.alice);

        vm.expectRevert(Errors.ZeroAssets.selector);
        vm.prank($.alice);
        $.dahlia.supplyAndBorrow($.marketId, 0, 1, $.alice, $.alice);

        vm.expectRevert(Errors.ZeroAssets.selector);
        vm.prank($.alice);
        $.dahlia.supplyAndBorrow($.marketId, 1, 0, $.alice, $.alice);
    }

    function test_int_supplyAndBorrow_zeroAddress(uint256 assets) public {
        vm.assume(assets > 0);
        vm.startPrank($.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotPermitted.selector, $.alice));
        $.dahlia.supplyAndBorrow($.marketId, assets, assets, address(0), $.alice);

        vm.expectRevert(Errors.ZeroAddress.selector);
        $.dahlia.supplyAndBorrow($.marketId, assets, assets, $.alice, address(0));
        vm.stopPrank();
    }

    function test_int_supplyAndBorrow_unhealthyPosition(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, BoundUtils.toPercent(100), BoundUtils.toPercent(150));

        $.oracle.setPrice(pos.price);
        vm.dahliaLendBy($.carol, pos.lent, $);
        vm.dahliaPrepareCollateralBalanceFor($.alice, pos.collateral, $);

        uint256 maxBorrowAssets = pos.collateral.collateralToLendUp(pos.price).mulPercentUp($.marketConfig.lltv);

        vm.prank($.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientCollateral.selector, pos.borrowed, maxBorrowAssets));
        vm.resumeGasMetering();
        $.dahlia.supplyAndBorrow($.marketId, pos.collateral, pos.borrowed, $.alice, $.alice);
    }

    function test_int_supplyAndBorrow_insufficientLiquidity(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();

        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.assume(pos.borrowed >= 10);

        // Make lend less then borrow
        pos.lent = bound(pos.lent, 1, pos.borrowed - 1);

        $.oracle.setPrice(pos.price);
        vm.dahliaLendBy($.carol, pos.lent, $);
        vm.dahliaPrepareCollateralBalanceFor($.alice, pos.collateral, $);

        vm.prank($.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientLiquidity.selector, pos.borrowed, pos.lent));
        vm.resumeGasMetering();
        $.dahlia.supplyAndBorrow($.marketId, pos.collateral, pos.borrowed, $.alice, $.alice);
    }

    function test_int_supplyAndBorrow_byAssets(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();

        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        $.oracle.setPrice(pos.price);
        vm.dahliaLendBy($.carol, pos.lent, $);
        vm.dahliaPrepareCollateralBalanceFor($.alice, pos.collateral, $);
        uint256 expectedBorrowShares = pos.borrowed.toSharesUp(0, 0);

        vm.startPrank($.alice);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.SupplyCollateral($.marketId, $.alice, $.alice, pos.collateral);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.Borrow($.marketId, $.alice, $.alice, $.bob, pos.borrowed, expectedBorrowShares);
        vm.resumeGasMetering();
        uint256 _shares = $.dahlia.supplyAndBorrow($.marketId, pos.collateral, pos.borrowed, $.alice, $.bob);
        vm.pauseGasMetering();
        vm.stopPrank();

        _checkMarketBorrowValid(_shares, pos.lent, pos.borrowed, expectedBorrowShares);
    }

    function test_int_supplyAndBorrow_onBehalfOfOwner(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();

        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        $.oracle.setPrice(pos.price);
        vm.dahliaLendBy($.carol, pos.lent, $);
        vm.dahliaPrepareCollateralBalanceFor($.alice, pos.collateral, $);
        uint256 expectedBorrowShares = pos.borrowed.toSharesUp(0, 0);

        address caller = ctx.createWallet("CALLER");
        vm.prank($.alice);
        $.dahlia.updatePermission(caller, true);

        // caller must have possibility to supplyAndBorrow on behalf of alice
        vm.startPrank(caller);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.SupplyCollateral($.marketId, caller, $.alice, pos.collateral);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.Borrow($.marketId, caller, $.alice, $.bob, pos.borrowed, expectedBorrowShares);
        vm.resumeGasMetering();
        uint256 _shares = $.dahlia.supplyAndBorrow($.marketId, pos.collateral, pos.borrowed, $.alice, $.bob);
        vm.pauseGasMetering();
        vm.stopPrank();

        _checkMarketBorrowValid(_shares, pos.lent, pos.borrowed, expectedBorrowShares);
    }

    function _checkMarketBorrowValid(uint256 returnShares, uint256 amountLent, uint256 amountBorrowed, uint256 expectedBorrowShares) internal view {
        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, $.alice);
        assertEq(returnShares, expectedBorrowShares, "returned shares amount");
        assertEq($.dahlia.getMarket($.marketId).totalBorrowAssets, amountBorrowed, "total borrow");
        assertEq(userPos.borrowShares, expectedBorrowShares, "borrow share");
        assertEq($.loanToken.balanceOf($.bob), amountBorrowed, "receiver balance");
        assertEq($.loanToken.balanceOf(address($.vault)), amountLent - amountBorrowed, "dahlia balance");
    }

    function test_int_supplyAndBorrow_WithInterest() public {
        vm.pauseGasMetering();

        TestTypes.MarketPosition memory pos = TestTypes.MarketPosition({ borrowed: 0, collateral: 1000e18, ltv: 80_000, price: 1e36, lent: 1000e18 });
        $.oracle.setPrice(pos.price);
        vm.dahliaLendBy($.carol, pos.lent, $);
        vm.dahliaPrepareCollateralBalanceFor($.alice, pos.collateral, $);
        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);
        uint256 maxBorrowAssets = MarketMath.calcMaxBorrowAssets(pos.price, pos.collateral, market.lltv);
        assertGt(pos.collateral, 0, "user has collateral");
        assertGt(maxBorrowAssets, 0, "allow to borrow");
        pos.borrowed = maxBorrowAssets;

        uint256 expectedBorrowShares = pos.borrowed.toSharesUp(0, 0);

        vm.startPrank($.alice);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.SupplyCollateral($.marketId, $.alice, $.alice, pos.collateral - 1);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.Borrow($.marketId, $.alice, $.alice, $.bob, pos.borrowed / 2, expectedBorrowShares / 2);
        vm.resumeGasMetering();
        uint256 _shares = $.dahlia.supplyAndBorrow($.marketId, pos.collateral - 1, pos.borrowed / 2, $.alice, $.bob);
        assertEq(_shares, expectedBorrowShares / 2, "returned shares amount");
        vm.pauseGasMetering();
        vm.forward(1); // we expect accrue interest will not allow to borrow second initially allowed
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.AccrueInterest($.marketId, 292_291_602, 116_916_640_800, 0, 0);
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientCollateral.selector, 800_000_000_116_916_640_800, 800e18)); // InsufficientCollateral
        vm.resumeGasMetering();
        $.dahlia.supplyAndBorrow($.marketId, 1, pos.borrowed / 2, $.alice, $.bob);
        vm.pauseGasMetering();

        vm.stopPrank();
    }
}
