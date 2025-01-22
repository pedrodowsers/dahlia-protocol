// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { console } from "@forge-std/console.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { LibString } from "@solady/utils/LibString.sol";
import { Test, Vm } from "forge-std/Test.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { WrappedVault } from "src/royco/contracts/WrappedVault.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { DahliaTransUtils } from "test/common/DahliaTransUtils.sol";
import { TestContext } from "test/common/TestContext.sol";
import { TestTypes } from "test/common/TestTypes.sol";

// Test for tracking and validating market interest accruals, lender/borrower positions,
// and fee distribution in Dahlia Protocol.
contract POSTest is Test {
    using FixedPointMathLib for uint256;
    using SharesMathLib for uint256;
    using BoundUtils for Vm;
    using DahliaTransUtils for Vm;
    using LibString for uint256;

    TestContext.MarketContext $;
    TestContext ctx;

    // Sets up the test environment by creating a lending market with 80% Liquidation Loan-to-Value.
    function setUp() public {
        ctx = new TestContext(vm);
        $ = ctx.bootstrapMarket("USDC", "WBTC", BoundUtils.toPercent(80));
    }

    // Verifies that no interest accrual has occurred when market conditions remain static.
    function _checkInterestDidntChange() internal {
        vm.pauseGasMetering();
        IDahlia.Market memory state = $.dahlia.getMarket($.marketId);

        uint256 totalBorrowBeforeAccrued = state.totalBorrowAssets;
        uint256 totalLendBeforeAccrued = state.totalLendAssets;
        uint256 totalLendSharesBeforeAccrued = state.totalLendShares;

        vm.resumeGasMetering();
        $.dahlia.accrueMarketInterest($.marketId); // Simulate interest accrual
        vm.pauseGasMetering();

        // Fetch updated market state to validate
        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, $.owner);
        IDahlia.Market memory stateAfter = $.dahlia.getMarket($.marketId);

        assertEq(stateAfter.totalBorrowAssets, totalBorrowBeforeAccrued, "total borrow unchanged");
        assertEq(stateAfter.totalLendAssets, totalLendBeforeAccrued, "total supply unchanged");
        assertEq(stateAfter.totalLendShares, totalLendSharesBeforeAccrued, "total supply shares unchanged");
        assertEq(userPos.lendShares, 0, "feeRecipient's supply shares");
    }

    // Prints the state of the lending market for debugging and analysis.
    function printMarketState(string memory suffix, string memory title) public view {
        console.log("\n#### BLOCK:", block.number, title);
        IDahlia.Market memory state = $.dahlia.getMarket($.marketId);

        console.log(suffix, "market.totalLendAssets", state.totalLendAssets);
        console.log(suffix, "market.totalLendShares", state.totalLendShares);
        console.log(suffix, "market.totalBorrowShares", state.totalBorrowShares);
        console.log(suffix, "market.totalBorrowAssets", state.totalBorrowAssets);
        console.log(suffix, "market.totalPrincipal", state.totalLendPrincipalAssets);
        console.log(suffix, "market.utilization", state.totalBorrowAssets * 100_000 / state.totalLendAssets);
        console.log(suffix, "dahlia.usdc.balance", $.loanToken.balanceOf(address($.dahlia)));

        // Display positions for key actors in the market
        printUserPos(string.concat(suffix, " carol"), $.carol);
        printUserPos(string.concat(suffix, " bob"), $.bob);
        printUserPos(string.concat(suffix, " protocolFee"), $.protocolFeeRecipient);
        printUserPos(string.concat(suffix, " reserveFee"), $.reserveFeeRecipient);
    }

    // Prints a user's position in the lending market.
    function printUserPos(string memory suffix, address user) public view {
        IDahlia.UserPosition memory pos = $.dahlia.getPosition($.marketId, user);

        console.log(suffix, ".WrappedVault.balanceOf", WrappedVault(address($.dahlia.getMarket($.marketId).vault)).balanceOf(user));
        console.log(suffix, ".WrappedVault.principal", WrappedVault(address($.dahlia.getMarket($.marketId).vault)).principal(user));
        console.log(suffix, ".lendAssets", pos.lendPrincipalAssets);
        console.log(suffix, ".lendShares", pos.lendShares);
        console.log(suffix, ".usdc.balance", $.loanToken.balanceOf(user));
    }

    // Validates a user's position, including interest and shares, against expected values.
    function validateUserPos(string memory suffix, uint256 expectedBob, uint256 expectedCarol, uint256 expectedBobAssets, uint256 expectedCarolAssets)
        public
        view
    {
        (uint256 bobAssetsInterest, uint256 bobSharesInterest) = $.dahlia.getPositionInterest($.marketId, $.bob);
        assertEq(bobSharesInterest, expectedBob, string(abi.encodePacked("block ", block.number.toString(), " bob:", suffix)));
        assertEq(bobAssetsInterest, expectedBobAssets, string(abi.encodePacked("block ", block.number.toString(), " bob:", suffix)));

        (uint256 carolAssetsInterest, uint256 carolSharesInterest) = $.dahlia.getPositionInterest($.marketId, $.carol);
        assertEq(carolSharesInterest, expectedCarol, string(abi.encodePacked("carol:", suffix)));
        assertEq(carolAssetsInterest, expectedCarolAssets, string(abi.encodePacked("carol:", suffix)));
    }

    // Validates interest accrual and interaction with lending rates over a series of blocks.
    function test_int_accrueInterest_Test1() public {
        vm.pauseGasMetering();

        // Define initial market position parameters
        TestTypes.MarketPosition memory pos = TestTypes.MarketPosition({
            collateral: 10_000e8,
            lent: 10_000e6,
            borrowed: 1000e6, // 10% borrowed
            price: 1e34,
            ltv: BoundUtils.toPercent(80)
        });

        uint32 protocolFee = BoundUtils.toPercent(1);
        uint32 reserveFee = BoundUtils.toPercent(1);

        // Validate initial market conditions
        assertEq($.dahlia.previewLendRateAfterDeposit($.marketId, 0), 0, "start lend rate");
        $.oracle.setPrice(pos.price);

        // Simulate market activities: lending, collateral supply, borrowing
        vm.dahliaLendBy($.carol, pos.lent, $);
        vm.dahliaLendBy($.bob, pos.lent, $);
        vm.dahliaSupplyCollateralBy($.alice, pos.collateral, $);
        vm.dahliaBorrowBy($.alice, pos.borrowed, $);

        // Ensure fees and rates are set correctly
        uint256 ltv = $.dahlia.getPositionLTV($.marketId, $.alice);
        console.log("ltv: ", ltv);

        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);
        WrappedVault vault = WrappedVault(address(market.vault));
        vm.prank(vault.owner());
        vault.addRewardsToken(address($.loanToken));

        vm.startPrank($.owner);
        if (protocolFee != $.dahlia.getMarket($.marketId).protocolFeeRate) {
            $.dahlia.setProtocolFeeRate($.marketId, protocolFee);
        }
        if (reserveFee != $.dahlia.getMarket($.marketId).reserveFeeRate) {
            $.dahlia.setReserveFeeRecipient($.reserveFeeRecipient);
            $.dahlia.setReserveFeeRate($.marketId, reserveFee);
        }
        vm.stopPrank();
        printMarketState("0", "carol and bob has equal position with 10% ltv");
        assertEq($.dahlia.previewLendRateAfterDeposit($.marketId, 0), 8_750_130, "initial lend rate");
        validateUserPos("0", 0, 0, 0, 0);
        assertEq($.dahlia.previewLendRateAfterDeposit($.marketId, pos.lent), 5_647_210, "initial lend rate if deposit more assets");
        validateUserPos("0", 0, 0, 0, 0);

        vm.forward(1);
        assertEq($.dahlia.previewLendRateAfterDeposit($.marketId, 0), 8_750_130, "rate after 1 block");

        uint256 blocks = 10_000;
        vm.forward(blocks - 1);
        validateUserPos("1 ", 857_999_927, 857_999_927, 858, 858);
        assertEq($.dahlia.previewLendRateAfterDeposit($.marketId, 0), 8_750_145, "lend rate after 10000 blocks");
        assertEq($.vault.previewRateAfterDeposit(address($.loanToken), 0), 8_750_145, "lend rate after 10000 blocks using vault");
        assertEq($.dahlia.previewLendRateAfterDeposit($.marketId, pos.lent), 5_647_219, "lend rate if deposit more assets");
        assertEq($.vault.previewRateAfterDeposit(address($.loanToken), pos.lent), 5_647_219, "lend rate if deposit more assets using vault");
        vm.dahliaClaimInterestBy($.carol, $);
        validateUserPos("1 claim by carol", 857_999_927, 857_999_927, 858, 858);
        assertEq($.dahlia.getMarket($.marketId).ratePerSec, 175_002_615);
        assertLt($.dahlia.previewLendRateAfterDeposit($.marketId, pos.lent), $.dahlia.getMarket($.marketId).ratePerSec);
        printMarketState("1", "interest claimed by carol after 100 blocks");
        vm.dahliaClaimInterestBy($.carol, $);
        printMarketState("1.1", "interest again claimed by carol after 100 blocks");

        vm.forward(blocks / 2); // 50 block pass
        validateUserPos("1.2", 1_286_499_835, 1_286_499_835, 1286, 1286);
        vm.dahliaClaimInterestBy($.carol, $);
        printMarketState("1.2", "interest claimed by carol");
        validateUserPos("1.2 claim by carol", 1_286_499_835, 1_286_499_835, 1286, 1286);
        vm.dahliaClaimInterestBy($.bob, $);
        validateUserPos("1.3 claim by bob and carol", 1_286_499_835, 1_286_499_835, 1286, 1286);
        printMarketState("1.3", "interest claimed by bob");
        printMarketState("2", "accrual of interest and lending again by carol");
        vm.dahliaLendBy($.carol, pos.lent, $);
        validateUserPos("3 lending by carol", 1_286_499_835, 1_286_499_835, 1286, 1286);
        printMarketState("3", "carol lending again");
        //        vm.dahliaLendBy($.bob, pos.lent, $);
        //        printMarketState("4.1", "bob lending again");
        uint256 assets = vm.dahliaWithdrawBy($.bob, $.dahlia.getPosition($.marketId, $.bob).lendShares, $);
        validateUserPos("4 after bob withdraw all shares", 0, 1_286_999_835, 0, 1287);
        printMarketState("4", "after bob withdraw all shares");
        console.log("4 bob assets withdrawn: ", assets);
        vm.dahliaWithdrawBy($.carol, $.dahlia.getPosition($.marketId, $.carol).lendShares / 2, $);
        validateUserPos("5 carol withdraw 1/2 of shares", 0, 1_286_999_835, 0, 1287);
        printMarketState("5", "carol withdraw 1/2 of shares");
        vm.dahliaClaimInterestBy($.carol, $);
        validateUserPos("5 carol claim interest", 0, 1_286_999_835, 0, 1287);
        printMarketState("5.1", "interest claimed by carol and 1/2 of shares withdrawn");
        IDahlia.UserPosition memory alicePos = $.dahlia.getPosition($.marketId, $.alice);
        vm.dahliaRepayByShares($.alice, alicePos.borrowShares, $.dahlia.getMarket($.marketId).totalBorrowAssets, $);
        validateUserPos("6 repay by alice", 0, 1_286_999_835, 0, 1287);
        printMarketState("6", "repay by alice");
        vm.forward(blocks);
        uint256 assets2 = vm.dahliaWithdrawBy($.carol, $.dahlia.getPosition($.marketId, $.carol).lendShares, $);
        validateUserPos("8 carol withdraw all shares", 0, 0, 0, 0);
        printMarketState("8", "after carol withdraw all shares");
        console.log("8 carol assets withdrawn: ", assets2);
        vm.startPrank($.carol);
        // if not position claim will fail with NotPermitted
        // vm.expectRevert(abi.encodeWithSelector(Errors.NotPermitted.selector, address(market.vault)));
        market.vault.claim($.carol, address($.loanToken));
        assertEq(vault.balanceOf($.reserveFeeRecipient), 25_999_997, "reserveFeeRecipient balance");
        assertEq(vault.balanceOf($.protocolFeeRecipient), 25_999_996, "protocolFeeRecipient balance");
        vm.startPrank($.protocolFeeRecipient);
        uint256 protocolFees = $.vault.redeem(vault.balanceOf($.protocolFeeRecipient), $.protocolFeeRecipient, $.protocolFeeRecipient);
        assertEq(protocolFees, 25, "protocol fees");
        printMarketState("9", "after withdrawProtocolFee");
        assertEq(vault.balanceOf($.protocolFeeRecipient), 0, "protocolFeeRecipient balance is 0");
        assertEq(vault.balanceOf($.reserveFeeRecipient), 25_999_997, "reserveFeeRecipient balance");
        vm.stopPrank();
        vm.startPrank($.reserveFeeRecipient);
        uint256 reserveFees = $.vault.redeem(vault.balanceOf($.reserveFeeRecipient), $.reserveFeeRecipient, $.reserveFeeRecipient);
        assertEq(reserveFees, 26, "reserve fees");
        printMarketState("10", "after withdrawReserveFee");
        assertEq(vault.balanceOf($.protocolFeeRecipient), 0, "protocolFeeRecipient balance is 0");
        assertEq(vault.balanceOf($.reserveFeeRecipient), 0, "reserveFeeRecipient balance");
    }
}
