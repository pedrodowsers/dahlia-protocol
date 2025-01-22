// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "@forge-std/Test.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { Constants } from "src/core/helpers/Constants.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { MarketMath } from "src/core/helpers/MarketMath.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { IDahliaFlashLoanCallback } from "src/core/interfaces/IDahliaCallbacks.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { DahliaTransUtils } from "test/common/DahliaTransUtils.sol";
import { TestConstants, TestContext } from "test/common/TestContext.sol";
import { TestTypes } from "test/common/TestTypes.sol";
import { ERC20Mock } from "test/common/mocks/ERC20Mock.sol";

contract FlashLoanIntegrationLendingCollateralTest is Test, IDahliaFlashLoanCallback {
    using FixedPointMathLib for uint256;
    using SharesMathLib for uint256;
    using BoundUtils for Vm;
    using DahliaTransUtils for Vm;

    TestContext.MarketContext $;
    TestContext ctx;
    ERC20Mock token;
    address param;
    address internal location;

    function supplyOrLend(uint256 amount) internal {
        vm.dahliaSupplyCollateralBy($.carol, amount, $);
    }

    function setUp() public {
        ctx = new TestContext(vm);
        $ = ctx.bootstrapMarket("USDC", "WBTC", vm.randomLltv());
        token = $.collateralToken;
        param = address(token);
        location = address($.dahlia);
    }

    function onDahliaSupplyCollateral(uint256 amount, bytes memory data) external {
        assertEq(msg.sender, address($.dahlia));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.test_int_flashActions.selector) {
            uint256 toBorrow = abi.decode(data, (uint256));
            $.collateralToken.setBalance(address(this), amount);
            $.collateralToken.approve(address($.dahlia), amount);
            $.dahlia.borrow($.marketId, toBorrow, address(this), address(this));
        }
    }

    function onDahliaRepay(uint256 amount, bytes memory data) external {
        assertEq(msg.sender, address($.dahlia));
        bytes4 selector;
        (selector, data) = abi.decode(data, (bytes4, bytes));
        if (selector == this.test_int_flashActions.selector) {
            uint256 toWithdraw = abi.decode(data, (uint256));

            $.loanToken.approve(address($.dahlia), amount);
            $.dahlia.withdrawCollateral($.marketId, toWithdraw, address(this), address(this));
        }
    }

    function onDahliaFlashLoan(uint256 amount, uint256 fee, bytes memory data) external {
        assertEq(msg.sender, address($.dahlia));
        bytes4 selector = abi.decode(data, (bytes4));
        if (selector == this.test_int_flashLoan_success.selector) {
            assertEq(token.balanceOf(address(this)), amount + fee, "balance mismatch");
            token.approve(address($.dahlia), amount + fee);
        }
    }

    function test_int_flashLoan_ZeroAssets() public {
        vm.expectRevert(Errors.ZeroAssets.selector);
        $.dahlia.flashLoan(param, 0, abi.encode(this.test_int_flashLoan_ZeroAssets.selector));
    }

    function test_int_flashLoan_shouldRevertIfNotReimbursed(uint256 amount) public {
        vm.pauseGasMetering();
        amount = vm.boundAmount(amount);
        supplyOrLend(amount);

        token.approve(location, 0);

        vm.resumeGasMetering();
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        $.dahlia.flashLoan(param, amount, abi.encode(this.test_int_flashLoan_shouldRevertIfNotReimbursed.selector, TestConstants.EMPTY_CALLBACK));
    }

    function test_int_flashLoan_success(uint256 amount) public {
        vm.pauseGasMetering();
        amount = vm.boundAmount(amount);

        supplyOrLend(amount);
        vm.resumeGasMetering();
        $.dahlia.flashLoan(param, amount, abi.encode(this.test_int_flashLoan_success.selector));
        vm.pauseGasMetering();

        assertEq(token.balanceOf($.carol), 0, "Balance of Carol should stay 0");
        assertEq(token.balanceOf(location), amount, "Balance of Dahlia the same after");
    }

    function test_int_flashLoan_withFee(uint256 amount, uint24 flashLoanFeeRate) public {
        vm.pauseGasMetering();
        amount = vm.boundAmount(amount);
        flashLoanFeeRate = uint24(bound(flashLoanFeeRate, 0, Constants.MAX_FLASH_LOAN_FEE_RATE));

        vm.prank($.owner);
        $.dahlia.setFlashLoanFeeRate(flashLoanFeeRate);

        uint256 expectedFee = MarketMath.mulPercentUp(amount, flashLoanFeeRate);
        token.setBalance(address(this), expectedFee);

        supplyOrLend(amount);
        vm.resumeGasMetering();
        $.dahlia.flashLoan(param, amount, abi.encode(this.test_int_flashLoan_success.selector));
        vm.pauseGasMetering();

        assertEq(token.balanceOf(ctx.wallets("PROTOCOL_FEE_RECIPIENT")), expectedFee, "Balance of owner should increase with fee");
        assertEq(token.balanceOf($.carol), 0, "Balance of Carol should stay 0");
        assertEq(token.balanceOf(location), amount, "Balance of Dahlia the same after");
    }

    function test_int_flashActions(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);

        $.oracle.setPrice(pos.price);

        vm.dahliaLendBy($.carol, pos.lent, $);

        vm.resumeGasMetering();
        $.dahlia.supplyCollateral($.marketId, pos.collateral, address(this), abi.encode(this.test_int_flashActions.selector, abi.encode(pos.borrowed)));
        IDahlia.UserPosition memory userPos1 = $.dahlia.getPosition($.marketId, address(this));

        assertGt(userPos1.borrowShares, 0, "no borrow");

        $.dahlia.repay($.marketId, pos.borrowed, 0, address(this), abi.encode(this.test_int_flashActions.selector, abi.encode(pos.collateral)));
        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, address(this));
        assertEq(userPos.collateral, 0, "no withdraw collateral");
    }
}
