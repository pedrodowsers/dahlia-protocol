// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "@forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { DahliaTransUtils } from "test/common/DahliaTransUtils.sol";
import { TestConstants } from "test/common/TestConstants.sol";
import { TestContext } from "test/common/TestContext.sol";
import { TestTypes } from "test/common/TestTypes.sol";

contract WithdrawIntegrationTest is Test {
    using SharesMathLib for uint256;
    using BoundUtils for Vm;
    using DahliaTransUtils for Vm;

    TestContext.MarketContext $;
    TestContext ctx;

    function setUp() public {
        ctx = new TestContext(vm);
        $ = ctx.bootstrapMarket("USDC", "WBTC", vm.randomLltv());
    }

    function test_int_withdraw_marketNotDeployed(IDahlia.MarketId marketIdFuzz, uint256 assets) public {
        vm.assume(!vm.marketsEq($.marketId, marketIdFuzz));
        vm.prank($.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotPermitted.selector, $.alice));
        $.dahlia.withdraw(marketIdFuzz, assets, 0, $.alice, $.alice);
    }

    function test_int_withdraw_zeroAmount() public {
        vm.pauseGasMetering();
        vm.dahliaLendBy($.alice, 1, $);

        vm.prank($.alice);
        vm.resumeGasMetering();
        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);
        uint256 assets = market.vault.withdraw(0, $.alice, $.alice);
        assertEq(assets, 0);
    }

    function test_int_lend_directCallNotPermitted(uint256 shares) public {
        vm.startPrank($.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotPermitted.selector, $.alice));
        $.dahlia.withdraw($.marketId, 0, shares, $.alice, $.alice);
    }

    function test_int_withdraw_zeroAddress(uint256 lent) public {
        vm.pauseGasMetering();
        lent = vm.boundAmount(lent);
        vm.dahliaLendBy($.alice, lent, $);

        vm.resumeGasMetering();
        vm.startPrank($.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotPermitted.selector, $.alice));
        $.dahlia.withdraw($.marketId, lent, 0, $.alice, address(0));

        vm.expectRevert(Errors.ZeroAddress.selector);
        $.dahlia.withdraw($.marketId, lent, 0, address(0), $.alice);
        vm.stopPrank();
    }

    function test_int_withdraw_insufficientLiquidity(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        uint256 expectedSupplyShares = pos.lent.toSharesDown(0, 0);
        uint256 expectedWithdrawnShares = pos.lent.toSharesUp(pos.lent, expectedSupplyShares);

        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);

        // Carol cannot withdraw own assets, because alice already borrowed part
        vm.prank($.carol);
        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientLiquidity.selector, pos.borrowed, 0));
        market.vault.redeem(expectedWithdrawnShares, $.carol, $.carol);
    }

    function test_int_withdraw_byAssets(TestTypes.MarketPosition memory pos, uint256 amountWithdrawn) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.alice, $.carol, $);

        amountWithdrawn = bound(amountWithdrawn, 1, pos.lent - pos.borrowed);
        uint256 expectedSupplyShares = pos.lent.toSharesDown(0, 0);
        uint256 expectedWithdrawnShares = amountWithdrawn.toSharesUp(pos.lent, expectedSupplyShares);

        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);

        vm.prank($.alice);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.Withdraw($.marketId, address(market.vault), $.bob, $.alice, amountWithdrawn, expectedWithdrawnShares);
        vm.resumeGasMetering();
        uint256 returnAssets = market.vault.redeem(expectedWithdrawnShares, $.bob, $.alice);
        vm.pauseGasMetering();

        expectedSupplyShares -= expectedWithdrawnShares;
        assertEq(returnAssets, amountWithdrawn, "returned asset amount");
        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, $.alice);
        assertEq(userPos.lendShares, expectedSupplyShares, "lend shares");
        assertEq($.dahlia.getMarket($.marketId).totalLendShares, expectedSupplyShares, "total lend shares");
        assertEq($.dahlia.getMarket($.marketId).totalLendAssets, pos.lent - amountWithdrawn, "total supply");
        assertEq($.loanToken.balanceOf($.bob), amountWithdrawn, "receiver balance");
        assertEq($.loanToken.balanceOf($.carol), pos.borrowed, "borrower balance");
        assertEq($.loanToken.balanceOf(address($.vault)), pos.lent - pos.borrowed - amountWithdrawn, "Dahlia balance");
    }

    function test_int_withdraw_protocolFee(TestTypes.MarketPosition memory pos, uint256 blocks, uint32 fee) public {
        vm.pauseGasMetering();
        address protocolRecipient = ctx.wallets("PROTOCOL_FEE_RECIPIENT");
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        uint32 protocolFee = uint32(bound(uint256(fee), BoundUtils.toPercent(2), BoundUtils.toPercent(5)));

        vm.startPrank($.owner);
        if (protocolFee != $.dahlia.getMarket($.marketId).protocolFeeRate) {
            $.dahlia.setProtocolFeeRate($.marketId, protocolFee);
        }
        vm.stopPrank();

        blocks = vm.boundBlocks(blocks);

        vm.forward(blocks);
        $.dahlia.accrueMarketInterest($.marketId);

        (uint256 borrowedAssets,,) = $.dahlia.getMaxBorrowableAmount($.marketId, $.alice, 0);
        vm.dahliaRepayByShares($.alice, $.dahlia.getPosition($.marketId, $.alice).borrowShares, borrowedAssets, $);

        IDahlia.Market memory state = $.dahlia.getMarket($.marketId);
        uint256 protocolFeeShares = $.dahlia.getPosition($.marketId, protocolRecipient).lendShares;
        uint256 expectedAssets = protocolFeeShares.toAssetsDown(state.totalLendAssets, state.totalLendShares);

        // anyone can call function withdrawProtocolFee
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.Withdraw($.marketId, address($.vault), protocolRecipient, protocolRecipient, expectedAssets, protocolFeeShares);

        vm.prank(protocolRecipient);
        uint256 assetsWithdrawn = $.vault.redeem(protocolFeeShares, protocolRecipient, protocolRecipient);

        IDahlia.UserPosition memory protocolRecipientPos = $.dahlia.getPosition($.marketId, protocolRecipient);
        assertEq(assetsWithdrawn, expectedAssets, "assetsWithdrawn check");
        assertEq(protocolRecipientPos.lendShares, 0, "protocolRecipient lend shares");
        assertEq($.loanToken.balanceOf(protocolRecipient), expectedAssets, "reserveRecipient balance");
    }

    function test_int_withdraw_reserveFee(TestTypes.MarketPosition memory pos, uint256 blocks, uint32 fee) public {
        vm.pauseGasMetering();
        address reserveRecipient = ctx.createWallet("RESERVE_FEE_RECIPIENT");
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        uint32 reserveFee = uint32(bound(uint256(fee), BoundUtils.toPercent(2), BoundUtils.toPercent(5)));

        vm.startPrank($.owner);
        $.dahlia.setReserveFeeRecipient(reserveRecipient);
        $.dahlia.setReserveFeeRate($.marketId, reserveFee);
        vm.stopPrank();

        blocks = vm.boundBlocks(blocks);

        vm.forward(blocks);
        $.dahlia.accrueMarketInterest($.marketId);

        (uint256 borrowedAssets,,) = $.dahlia.getMaxBorrowableAmount($.marketId, $.alice, 0);
        vm.dahliaRepayByShares($.alice, $.dahlia.getPosition($.marketId, $.alice).borrowShares, borrowedAssets, $);

        IDahlia.Market memory state = $.dahlia.getMarket($.marketId);
        uint256 reserveFeeShares = $.dahlia.getPosition($.marketId, reserveRecipient).lendShares;
        uint256 expectedAssets = reserveFeeShares.toAssetsDown(state.totalLendAssets, state.totalLendShares);

        vm.prank(reserveRecipient);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.Withdraw($.marketId, address($.vault), reserveRecipient, reserveRecipient, expectedAssets, reserveFeeShares);
        uint256 assetsWithdrawn = $.vault.redeem(reserveFeeShares, reserveRecipient, reserveRecipient);

        IDahlia.UserPosition memory reserveRecipientPos = $.dahlia.getPosition($.marketId, reserveRecipient);
        assertEq(assetsWithdrawn, expectedAssets, "assetsWithdrawn check");
        assertEq(reserveRecipientPos.lendShares, 0, "reserveRecipient lend shares");
        assertEq($.loanToken.balanceOf(reserveRecipient), expectedAssets, "reserveRecipient balance");
    }

    function test_int_withdraw_byShares(TestTypes.MarketPosition memory pos, uint256 sharesWithdrawn) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.alice, $.carol, $);

        uint256 expectedSupplyShares = pos.lent.toSharesDown(0, 0);
        uint256 availableLiquidity = pos.lent - pos.borrowed;
        uint256 withdrawalShares = availableLiquidity.toSharesDown(pos.lent, expectedSupplyShares);
        vm.assume(withdrawalShares != 0);

        sharesWithdrawn = bound(sharesWithdrawn, 1, withdrawalShares);
        uint256 expectedAmountWithdrawn = sharesWithdrawn.toAssetsDown(pos.lent, expectedSupplyShares);

        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);

        vm.prank($.alice);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.Withdraw($.marketId, address(market.vault), $.bob, $.alice, expectedAmountWithdrawn, sharesWithdrawn);
        vm.resumeGasMetering();
        uint256 returnAssets = market.vault.redeem(sharesWithdrawn, $.bob, $.alice);
        vm.pauseGasMetering();

        expectedSupplyShares -= sharesWithdrawn;
        assertEq(returnAssets, expectedAmountWithdrawn, "returned asset amount");
        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, $.alice);
        assertEq(userPos.lendShares, expectedSupplyShares, "lend shares");
        assertEq($.dahlia.getMarket($.marketId).totalLendAssets, pos.lent - expectedAmountWithdrawn, "total supply");
        assertEq($.dahlia.getMarket($.marketId).totalLendShares, expectedSupplyShares, "total lend shares");
        assertEq($.loanToken.balanceOf($.bob), expectedAmountWithdrawn, "receiver balance");
        assertEq($.loanToken.balanceOf(address($.vault)), pos.lent - pos.borrowed - expectedAmountWithdrawn, "Dahlia balance");
    }

    function test_int_withdraw_onBehalfOfByAssets(TestTypes.MarketPosition memory pos, uint256 amountWithdrawn) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.alice, $.carol, $);

        amountWithdrawn = bound(amountWithdrawn, 1, pos.lent - pos.borrowed);

        uint256 expectedSupplyShares = pos.lent.toSharesDown(0, 0);
        uint256 expectedWithdrawnShares = amountWithdrawn.toSharesUp(pos.lent, expectedSupplyShares);

        address ALICE_MONEY_MANAGER = makeAddr("ALICE_MONEY_MANAGER");
        //        vm.prank($.alice);
        //        $.dahlia.updatePermission(ALICE_MONEY_MANAGER, true);

        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);
        vm.prank($.alice);
        IERC20(address(market.vault)).approve(ALICE_MONEY_MANAGER, expectedWithdrawnShares);

        vm.prank(ALICE_MONEY_MANAGER);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.Withdraw($.marketId, address(market.vault), $.bob, $.alice, amountWithdrawn, expectedWithdrawnShares);
        vm.resumeGasMetering();
        uint256 returnAssets = market.vault.redeem(expectedWithdrawnShares, $.bob, $.alice);
        vm.pauseGasMetering();

        expectedSupplyShares -= expectedWithdrawnShares;
        assertEq(returnAssets, amountWithdrawn, "returned asset amount");

        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, $.alice);
        assertEq(userPos.lendShares, expectedSupplyShares, "lend shares");
        assertEq($.dahlia.getMarket($.marketId).totalLendShares, expectedSupplyShares, "total lend shares");
        assertEq($.dahlia.getMarket($.marketId).totalLendAssets, pos.lent - amountWithdrawn, "total supply");
        assertEq($.loanToken.balanceOf($.bob), amountWithdrawn, "receiver balance");
        assertEq($.loanToken.balanceOf($.carol), pos.borrowed, "borrower balance");
        assertEq($.loanToken.balanceOf(address($.vault)), pos.lent - pos.borrowed - amountWithdrawn, "Dahlia balance");
    }

    function test_int_withdraw_onBehalfOfByShares(TestTypes.MarketPosition memory pos, uint256 sharesWithdrawn) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.alice, $.carol, $);

        uint256 expectedSupplyShares = pos.lent.toSharesDown(0, 0);
        uint256 availableLiquidity = pos.lent - pos.borrowed;
        uint256 withdrawalShares = availableLiquidity.toSharesDown(pos.lent, expectedSupplyShares);
        vm.assume(withdrawalShares != 0);

        sharesWithdrawn = bound(sharesWithdrawn, 1, withdrawalShares);
        uint256 expectedAmountWithdrawn = sharesWithdrawn.toAssetsDown(pos.lent, expectedSupplyShares);

        address ALICE_MONEY_MANAGER = makeAddr("ALICE_MONEY_MANAGER");
        //        vm.prank($.alice);
        //        $.dahlia.updatePermission(ALICE_MONEY_MANAGER, true);

        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);
        vm.prank($.alice);
        IERC20(address(market.vault)).approve(ALICE_MONEY_MANAGER, sharesWithdrawn);

        vm.prank(ALICE_MONEY_MANAGER);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.Withdraw($.marketId, address(market.vault), $.bob, $.alice, expectedAmountWithdrawn, sharesWithdrawn);
        vm.resumeGasMetering();
        uint256 returnAssets = market.vault.redeem(sharesWithdrawn, $.bob, $.alice);
        vm.pauseGasMetering();

        expectedSupplyShares -= sharesWithdrawn;
        assertEq(returnAssets, expectedAmountWithdrawn, "returned asset amount");
        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, $.alice);
        assertEq(userPos.lendShares, expectedSupplyShares, "lend shares");
        assertEq($.dahlia.getMarket($.marketId).totalLendAssets, pos.lent - expectedAmountWithdrawn, "total supply");
        assertEq($.dahlia.getMarket($.marketId).totalLendShares, expectedSupplyShares, "total lend shares");
        assertEq($.loanToken.balanceOf($.bob), expectedAmountWithdrawn, "receiver balance");
        assertEq($.loanToken.balanceOf(address($.vault)), pos.lent - pos.borrowed - expectedAmountWithdrawn, "Dahlia balance");
    }
}
