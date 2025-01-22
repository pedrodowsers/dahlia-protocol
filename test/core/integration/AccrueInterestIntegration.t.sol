// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { LibString } from "@solady/utils/LibString.sol";
import { Test, Vm } from "forge-std/Test.sol";
import { Constants } from "src/core/helpers/Constants.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { IIrm } from "src/irm/interfaces/IIrm.sol";
import { InitializableERC20 } from "src/royco/periphery/InitializableERC20.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { DahliaTransUtils } from "test/common/DahliaTransUtils.sol";
import { TestConstants, TestContext } from "test/common/TestContext.sol";
import { TestTypes } from "test/common/TestTypes.sol";

contract AccrueInterestIntegrationTest is Test {
    using FixedPointMathLib for uint256;
    using SharesMathLib for uint256;
    using BoundUtils for Vm;
    using DahliaTransUtils for Vm;
    using LibString for uint256;

    TestContext.MarketContext $;
    TestContext ctx;

    function setUp() public {
        ctx = new TestContext(vm);
        $ = ctx.bootstrapMarket("USDC", "WBTC", vm.randomLltv());
    }

    function _checkInterestDidntChange() internal {
        vm.pauseGasMetering();
        IDahlia.Market memory state = $.dahlia.getMarket($.marketId);
        uint256 totalBorrowBeforeAccrued = state.totalBorrowAssets;
        uint256 totalLendBeforeAccrued = state.totalLendAssets;
        uint256 totalLendSharesBeforeAccrued = state.totalLendShares;

        vm.resumeGasMetering();
        $.dahlia.accrueMarketInterest($.marketId);
        vm.pauseGasMetering();

        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, $.owner);
        IDahlia.Market memory stateAfter = $.dahlia.getMarket($.marketId);
        assertEq(stateAfter.totalBorrowAssets, totalBorrowBeforeAccrued, "total borrow");
        assertEq(stateAfter.totalLendAssets, totalLendBeforeAccrued, "total supply");
        assertEq(stateAfter.totalLendShares, totalLendSharesBeforeAccrued, "total supply shares");
        assertEq(userPos.lendShares, 0, "feeRecipient's supply shares");
    }

    function test_int_accrueInterest_marketNotDeployed(IDahlia.MarketId marketIdFuzz) public {
        vm.assume(!vm.marketsEq($.marketId, marketIdFuzz));
        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSelector(Errors.WrongStatus.selector, IDahlia.MarketStatus.Uninitialized));
        $.dahlia.accrueMarketInterest(marketIdFuzz);
    }

    function test_int_accrueInterest_zeroIrm() public {
        vm.pauseGasMetering();
        $.marketConfig.irm = IIrm(address(0));
        vm.resumeGasMetering();
        $.dahlia.accrueMarketInterest($.marketId);
        _checkInterestDidntChange();
    }

    function test_int_accrueInterest_noTimeElapsed(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);
        _checkInterestDidntChange();
    }

    function test_int_accrueInterest_noBorrow(uint256 amountLent, uint256 blocks) public {
        vm.pauseGasMetering();
        amountLent = bound(amountLent, 2, TestConstants.MAX_TEST_AMOUNT);
        blocks = vm.boundBlocks(blocks);

        vm.dahliaLendBy($.carol, amountLent, $);
        vm.forward(blocks);
        _checkInterestDidntChange();
    }

    function test_int_accrueInterest_smallTimeElapsed() public {
        vm.pauseGasMetering();
        TestTypes.MarketPosition memory pos =
            TestTypes.MarketPosition({ collateral: 10e18, lent: 100e6, borrowed: 100_000_000, price: 1e34, ltv: Constants.DEFAULT_MAX_LLTV });

        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        IDahlia.Market memory state = $.dahlia.getActualMarketState($.marketId);
        assertEq(1, state.updatedAt, "updatedAt should be 1");
        vm.forward(1);
        vm.resumeGasMetering();
        $.dahlia.accrueMarketInterest($.marketId);
        vm.pauseGasMetering();
        assertEq(state.updatedAt, $.dahlia.getActualMarketState($.marketId).updatedAt, "updatedAt should not change for too small time elapsed");
        assertEq(state.totalBorrowAssets, $.dahlia.getActualMarketState($.marketId).totalBorrowAssets, "totalBorrowAssets should not change");
        assertEq(state.totalLendShares, $.dahlia.getActualMarketState($.marketId).totalLendShares, "totalLendShares should not change");
        assertEq(state.totalLendAssets, $.dahlia.getActualMarketState($.marketId).totalLendAssets, "totalLendAssets should not change");
        assertLt(state.ratePerSec, $.dahlia.getActualMarketState($.marketId).ratePerSec, "ratePerSec should increase");
        uint256 longestTimeElapsed = 100;
        for (uint256 i = 0; i < longestTimeElapsed; i++) {
            IDahlia.Market memory state1 = $.dahlia.getActualMarketState($.marketId);
            vm.forward(1);
            $.dahlia.accrueMarketInterest($.marketId);
            IDahlia.Market memory state2 = $.dahlia.getActualMarketState($.marketId);
            assertLt(state1.ratePerSec, state2.ratePerSec, "ratePerSec should increase");
        }
        assertEq(99, $.dahlia.getActualMarketState($.marketId).updatedAt, "updatedAt should change after longestTimeElapsed blocks");
        assertEq(pos.borrowed + 14, $.dahlia.getActualMarketState($.marketId).totalBorrowAssets, "we should accrue interest for longestTimeElapsed blocks");
        _checkInterestDidntChange();
    }

    function test_int_accrueInterest_noFee(TestTypes.MarketPosition memory pos, uint256 blocks) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        blocks = vm.boundBlocks(blocks);
        IDahlia.Market memory state = $.dahlia.getMarket($.marketId);
        uint256 deltaTime = blocks * TestConstants.BLOCK_TIME;

        (uint256 interestEarnedAssets, uint256 newRatePerSec,) =
            $.marketConfig.irm.calculateInterest(deltaTime, state.totalLendAssets, state.totalBorrowAssets, state.fullUtilizationRate);

        vm.forward(blocks);
        if (interestEarnedAssets > 0) {
            vm.expectEmit(true, true, true, true, address($.dahlia));
            emit IDahlia.AccrueInterest($.marketId, newRatePerSec, interestEarnedAssets, 0, 0);
        }

        vm.resumeGasMetering();
        $.dahlia.accrueMarketInterest($.marketId);
        vm.pauseGasMetering();
        IDahlia.Market memory stateAfter = $.dahlia.getMarket($.marketId);
        assertEq(stateAfter.totalLendShares, state.totalLendShares, "total lend shares stay the same if no protocol fee");

        _checkInterestDidntChange();
    }

    function test_int_accrueInterest_withFees(TestTypes.MarketPosition memory pos, uint256 blocks, uint32 fee) public {
        vm.pauseGasMetering();

        vm.prank($.owner);
        $.dahlia.setReserveFeeRecipient($.reserveFeeRecipient);

        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        uint32 protocolFee = uint32(bound(uint256(fee), BoundUtils.toPercent(2), BoundUtils.toPercent(5)));
        uint32 reserveFee = uint32(bound(uint256(fee), BoundUtils.toPercent(1), BoundUtils.toPercent(2)));

        vm.startPrank($.owner);
        if (protocolFee != $.dahlia.getMarket($.marketId).protocolFeeRate) {
            $.dahlia.setProtocolFeeRate($.marketId, protocolFee);
        }
        if (reserveFee != $.dahlia.getMarket($.marketId).reserveFeeRate) {
            $.dahlia.setReserveFeeRate($.marketId, reserveFee);
        }
        vm.stopPrank();

        blocks = vm.boundBlocks(blocks);

        IDahlia.Market memory state = $.dahlia.getMarket($.marketId);
        uint256 totalBorrowBeforeAccrued = state.totalBorrowAssets;
        uint256 totalLendBeforeAccrued = state.totalLendAssets;
        uint256 totalLendSharesBeforeAccrued = state.totalLendShares;

        uint256 deltaTime = blocks * TestConstants.BLOCK_TIME;
        (uint256 interestEarnedAssets, uint256 newRatePerSec,) =
            $.marketConfig.irm.calculateInterest(deltaTime, state.totalLendAssets, state.totalBorrowAssets, state.fullUtilizationRate);

        uint256 protocolFeeAssets = interestEarnedAssets * protocolFee / Constants.FEE_PRECISION;
        uint256 reserveFeeAssets = interestEarnedAssets * reserveFee / Constants.FEE_PRECISION;
        uint256 sumOfFeeAssets = protocolFeeAssets + reserveFeeAssets;
        uint256 sumOfFeeShares = sumOfFeeAssets.toSharesDown(state.totalLendAssets + interestEarnedAssets - sumOfFeeAssets, state.totalLendShares);

        uint256 protocolFeeShares = protocolFeeAssets.toSharesDown(state.totalLendAssets + interestEarnedAssets, state.totalLendShares + sumOfFeeShares);
        uint256 reserveFeeShares = sumOfFeeShares - protocolFeeShares;

        vm.forward(blocks);
        if (interestEarnedAssets > 0) {
            if (protocolFeeShares > 0) {
                vm.expectEmit(true, true, true, true, address($.vault));
                emit InitializableERC20.Transfer(address(0), $.protocolFeeRecipient, protocolFeeShares);
            }
            if (reserveFeeShares > 0) {
                vm.expectEmit(true, true, true, true, address($.vault));
                emit InitializableERC20.Transfer(address(0), $.reserveFeeRecipient, reserveFeeShares);
            }
            vm.expectEmit(true, true, true, true, address($.dahlia));
            emit IDahlia.AccrueInterest($.marketId, newRatePerSec, interestEarnedAssets, protocolFeeShares, reserveFeeShares);
        }
        vm.resumeGasMetering();
        $.dahlia.accrueMarketInterest($.marketId);
        vm.pauseGasMetering();
        assertEq($.vault.balanceOf($.protocolFeeRecipient), protocolFeeShares, "protocol fee recipient balance");
        assertEq($.vault.balanceOf($.reserveFeeRecipient), reserveFeeShares, "reserve fee recipient balance");

        IDahlia.Market memory stateAfter = $.dahlia.getMarket($.marketId);
        assertEq(stateAfter.totalLendAssets, totalLendBeforeAccrued + interestEarnedAssets, "total supply");
        assertEq(stateAfter.totalBorrowAssets, totalBorrowBeforeAccrued + interestEarnedAssets, "total borrow");
        assertEq(stateAfter.totalLendShares, totalLendSharesBeforeAccrued + protocolFeeShares + reserveFeeShares, "total lend shares");

        IDahlia.UserPosition memory protocolFeePos = $.dahlia.getPosition($.marketId, $.protocolFeeRecipient);
        IDahlia.UserPosition memory reserveFeePos = $.dahlia.getPosition($.marketId, $.reserveFeeRecipient);
        assertEq(protocolFeePos.lendShares, protocolFeeShares, "protocolFeeRecipient's lend shares");
        assertEq(reserveFeePos.lendShares, reserveFeeShares, "reserveFeeRecipient's lend shares");
        if (interestEarnedAssets > 0) {
            assertEq(stateAfter.updatedAt, block.timestamp, "last update");
        }
    }

    function test_int_accrueInterest_getLatestMarketStateWithFees(TestTypes.MarketPosition memory pos, uint256 blocks, uint32 fee) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        fee = uint32(bound(uint256(fee), 1, Constants.MAX_FEE_RATE));

        vm.startPrank($.owner);
        if (fee != $.dahlia.getMarket($.marketId).protocolFeeRate) {
            $.dahlia.setProtocolFeeRate($.marketId, fee);
        }
        vm.stopPrank();

        blocks = vm.boundBlocks(blocks);

        IDahlia.Market memory state = $.dahlia.getMarket($.marketId);
        uint256 totalBorrowBeforeAccrued = state.totalBorrowAssets;
        uint256 totalLendBeforeAccrued = state.totalLendAssets;
        uint256 totalLendSharesBeforeAccrued = state.totalLendShares;

        uint256 deltaTime = blocks * TestConstants.BLOCK_TIME;
        (uint256 interestEarnedAssets,,) =
            $.marketConfig.irm.calculateInterest(deltaTime, state.totalLendAssets, state.totalBorrowAssets, state.fullUtilizationRate);
        uint256 protocolFeeAssets = interestEarnedAssets * state.protocolFeeRate / Constants.FEE_PRECISION;
        uint256 sumOfFeeAssets = protocolFeeAssets;
        uint256 sumOfFeeShares = sumOfFeeAssets.toSharesDown(state.totalLendAssets + interestEarnedAssets - sumOfFeeAssets, state.totalLendShares);

        uint256 protocolFeeShares = protocolFeeAssets.toSharesDown(state.totalLendAssets + interestEarnedAssets, state.totalLendShares + sumOfFeeShares);

        vm.forward(blocks);
        vm.resumeGasMetering();
        IDahlia.Market memory m = $.dahlia.getMarket($.marketId);

        assertEq(m.totalLendAssets, totalLendBeforeAccrued + interestEarnedAssets, "total supply");
        assertEq(m.totalBorrowAssets, totalBorrowBeforeAccrued + interestEarnedAssets, "total borrow");
        assertEq(m.totalLendShares, totalLendSharesBeforeAccrued + protocolFeeShares, "total supply shares");
        assertLt($.dahlia.previewLendRateAfterDeposit($.marketId, 0), $.dahlia.getMarket($.marketId).ratePerSec);
    }

    function test_previewLendRateAfterDeposit_wrong_market() public view {
        assertEq($.dahlia.previewLendRateAfterDeposit(IDahlia.MarketId.wrap(0), 0), 0);
    }

    function test_previewLendRateAfterDeposit_no_borrow_position() public view {
        assertEq($.dahlia.previewLendRateAfterDeposit($.marketId, 0), 0);
        assertEq($.dahlia.previewLendRateAfterDeposit($.marketId, 100_000), 0);
    }
}
