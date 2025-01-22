// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "@forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { InitializableERC20 } from "src/royco/periphery/InitializableERC20.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { DahliaTransUtils } from "test/common/DahliaTransUtils.sol";
import { Constants, TestConstants, TestContext } from "test/common/TestContext.sol";
import { TestTypes } from "test/common/TestTypes.sol";
import { DahliaTest } from "test/common/abstracts/DahliaTest.sol";
import { ERC20Mock, IERC20 } from "test/common/mocks/ERC20Mock.sol";
import { OracleMock } from "test/common/mocks/OracleMock.sol";

contract StaleMarketIntegrationTest is DahliaTest {
    using SharesMathLib for uint256;
    using BoundUtils for Vm;
    using DahliaTransUtils for Vm;

    TestContext ctx;
    TestContext.MarketContext $;

    function setUp() public {
        vm.createSelectFork("mainnet", 20_921_816);
        ctx = new TestContext(vm);
        $ = ctx.bootstrapMarket("USDC", "WBTC", vm.randomLltv());
    }

    function test_int_staleMarket_marketNotDeployed(IDahlia.MarketId marketIdFuzz) public {
        vm.pauseGasMetering();
        vm.assume(!vm.marketsEq($.marketId, marketIdFuzz));
        vm.startPrank($.owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.WrongStatus.selector, IDahlia.MarketStatus.Uninitialized));
        vm.resumeGasMetering();
        $.dahlia.staleMarket(marketIdFuzz);
    }

    function test_int_staleMarket_marketDeprecated() public {
        vm.pauseGasMetering();
        vm.startPrank($.owner);
        $.dahlia.deprecateMarket($.marketId);

        vm.expectRevert(abi.encodeWithSelector(Errors.WrongStatus.selector, IDahlia.MarketStatus.Deprecated));
        vm.resumeGasMetering();
        $.dahlia.staleMarket($.marketId);
    }

    function test_int_staleMarket_doubleStale() public {
        staleMarket($.marketId);
        vm.pauseGasMetering();

        vm.startPrank($.owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.WrongStatus.selector, IDahlia.MarketStatus.Stalled));
        vm.resumeGasMetering();
        $.dahlia.staleMarket($.marketId);
    }

    function test_int_staleMarket_unauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        $.dahlia.staleMarket($.marketId);
    }

    function test_int_staleMarket_marketNoBadOracle() public {
        vm.pauseGasMetering();
        vm.startPrank($.owner);
        vm.expectRevert(Errors.OraclePriceNotStalled.selector);
        vm.resumeGasMetering();
        $.dahlia.staleMarket($.marketId);
    }

    function test_int_staleMarket_ActiveMarket_success() public {
        vm.pauseGasMetering();
        OracleMock($.oracle).setIsOracleBadData(true);

        assertEq(IDahlia.MarketStatus.Active, $.dahlia.getMarket($.marketId).status, "market is active");
        vm.startPrank($.owner);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.MarketStatusChanged($.marketId, IDahlia.MarketStatus.Active, IDahlia.MarketStatus.Stalled);
        vm.resumeGasMetering();
        $.dahlia.staleMarket($.marketId);
        vm.pauseGasMetering();

        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);
        assertEq(market.status, IDahlia.MarketStatus.Stalled, "market is staled");
        assertEq(market.repayPeriodEndTimestamp, uint48(block.timestamp + $.dahliaRegistry.getValue(Constants.VALUE_ID_REPAY_PERIOD)));

        // disallow deprecate stalled market
        vm.expectRevert(abi.encodeWithSelector(Errors.WrongStatus.selector, IDahlia.MarketStatus.Stalled));
        $.dahlia.deprecateMarket($.marketId);

        vm.expectRevert(abi.encodeWithSelector(Errors.WrongStatus.selector, IDahlia.MarketStatus.Stalled));
        $.dahlia.pauseMarket($.marketId);

        vm.expectRevert(abi.encodeWithSelector(Errors.WrongStatus.selector, IDahlia.MarketStatus.Stalled));
        $.dahlia.unpauseMarket($.marketId);
    }

    function test_int_staleMarket_pauseMarket_success() public {
        vm.pauseGasMetering();
        OracleMock($.oracle).setIsOracleBadData(true);

        vm.startPrank($.owner);

        $.dahlia.pauseMarket($.marketId);

        assertEq(IDahlia.MarketStatus.Paused, $.dahlia.getMarket($.marketId).status, "market is paused");

        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.MarketStatusChanged($.marketId, IDahlia.MarketStatus.Paused, IDahlia.MarketStatus.Stalled);
        vm.resumeGasMetering();
        $.dahlia.staleMarket($.marketId);
        vm.pauseGasMetering();

        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);
        assertEq(market.status, IDahlia.MarketStatus.Stalled, "market is staled");
        assertEq(market.repayPeriodEndTimestamp, uint48(block.timestamp + $.dahliaRegistry.getValue(Constants.VALUE_ID_REPAY_PERIOD)));
    }

    function staleMarket(IDahlia.MarketId id) internal {
        vm.pauseGasMetering();
        OracleMock($.oracle).setIsOracleBadData(true);
        vm.prank($.owner);
        vm.resumeGasMetering();
        $.dahlia.staleMarket(id);
    }

    function test_int_staleMarket_NotPermitted(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);

        vm.dahliaLendBy($.carol, pos.lent, $);
        vm.dahliaSupplyCollateralBy($.alice, pos.collateral, $);

        vm.resumeGasMetering();
        staleMarket($.marketId);
        vm.pauseGasMetering();

        vm.prank($.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotPermitted.selector, $.alice));
        vm.resumeGasMetering();
        $.dahlia.withdrawDepositAndClaimCollateral($.marketId, $.carol, $.bob);
    }

    function test_int_staleMarket_disallowBorrow(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);

        vm.dahliaLendBy($.carol, pos.lent, $);
        vm.dahliaSupplyCollateralBy($.alice, pos.collateral, $);

        vm.resumeGasMetering();
        staleMarket($.marketId);
        vm.pauseGasMetering();

        vm.prank($.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.WrongStatus.selector, IDahlia.MarketStatus.Stalled));
        vm.resumeGasMetering();
        $.dahlia.borrow($.marketId, pos.borrowed, $.alice, $.bob);
    }

    function test_int_staleMarket_disallowSupplyCollateral(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);

        vm.resumeGasMetering();
        staleMarket($.marketId);
        vm.pauseGasMetering();

        vm.prank($.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.WrongStatus.selector, IDahlia.MarketStatus.Stalled));
        vm.resumeGasMetering();
        $.dahlia.supplyCollateral($.marketId, pos.collateral, $.alice, TestConstants.EMPTY_CALLBACK);
    }

    function test_int_staleMarket_disallowLend(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.resumeGasMetering();
        staleMarket($.marketId);
        vm.pauseGasMetering();

        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);
        ERC20Mock($.marketConfig.loanToken).setBalance($.alice, pos.lent);

        vm.startPrank($.alice);
        IERC20($.marketConfig.loanToken).approve(address(market.vault), pos.lent);
        vm.expectRevert(abi.encodeWithSelector(Errors.WrongStatus.selector, IDahlia.MarketStatus.Stalled));
        vm.resumeGasMetering();
        market.vault.deposit(pos.lent, $.alice);
    }

    function test_int_staleMarket_disallowWithdrawLent(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        vm.resumeGasMetering();
        staleMarket($.marketId);
        vm.pauseGasMetering();

        uint256 lendShares = $.dahlia.getPosition($.marketId, $.carol).lendShares;
        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);

        vm.startPrank($.carol);
        vm.expectRevert(abi.encodeWithSelector(Errors.WrongStatus.selector, IDahlia.MarketStatus.Stalled));
        vm.resumeGasMetering();
        market.vault.redeem(lendShares, $.carol, $.carol);
    }

    function test_int_staleMarket_disallowWithdrawCollateralWithoutRepay(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        vm.resumeGasMetering();
        staleMarket($.marketId);
        vm.pauseGasMetering();

        vm.prank($.alice);
        vm.expectRevert(Errors.OraclePriceBadData.selector);
        vm.resumeGasMetering();
        $.dahlia.withdrawCollateral($.marketId, pos.collateral, $.alice, $.alice);
    }

    function test_int_staleMarket_disallowLiquidate(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, $.marketConfig.lltv + 1, TestConstants.MAX_TEST_LLTV);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        vm.resumeGasMetering();
        staleMarket($.marketId);
        vm.pauseGasMetering();

        vm.expectRevert(abi.encodeWithSelector(Errors.WrongStatus.selector, IDahlia.MarketStatus.Stalled));
        vm.resumeGasMetering();
        $.dahlia.liquidate($.marketId, $.alice, TestConstants.EMPTY_CALLBACK);
    }

    function test_int_staleMarket_repayPlusWithdraw(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);
        skip(26 weeks);
        {
            (uint256 assets, uint256 shares) = $.dahlia.getPositionInterest($.marketId, $.carol);
            assertGt(assets, 0, "carol assets position interest");
            assertGt(shares, 0, "carol shares position interest");
        }

        vm.resumeGasMetering();
        staleMarket($.marketId);
        vm.pauseGasMetering();

        IDahlia.UserPosition memory alicePosition = $.dahlia.getPosition($.marketId, $.alice);
        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);
        uint256 expectedAmountRepaid = uint256(alicePosition.borrowShares).toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);
        vm.startPrank($.alice);
        ERC20Mock($.marketConfig.loanToken).setBalance($.alice, expectedAmountRepaid);
        $.loanToken.approve(address($.dahlia), expectedAmountRepaid);
        vm.resumeGasMetering();
        $.dahlia.repay($.marketId, 0, alicePosition.borrowShares, $.alice, TestConstants.EMPTY_CALLBACK);
        $.dahlia.withdrawCollateral($.marketId, pos.collateral, $.alice, $.alice);
        vm.pauseGasMetering();
        vm.stopPrank();

        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, $.alice);
        assertEq(userPos.borrowShares, 0, "position borrow shares balance");
        assertEq(userPos.collateral, 0, "position collateral balance");
        assertEq($.collateralToken.balanceOf($.alice), pos.collateral, "user collateral token balance");
        assertEq($.collateralToken.balanceOf(address($.dahlia)), 0, "Dahlia collateral token balance");
    }

    function test_int_staleMarket_repayAndWithdraw(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);
        skip(26 weeks);
        {
            (uint256 assets, uint256 shares) = $.dahlia.getPositionInterest($.marketId, $.carol);
            assertGt(assets, 0, "carol assets position interest");
            assertGt(shares, 0, "carol shares position interest");
        }

        vm.resumeGasMetering();
        staleMarket($.marketId);
        vm.pauseGasMetering();

        IDahlia.UserPosition memory alicePosition = $.dahlia.getPosition($.marketId, $.alice);
        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);
        uint256 expectedAmountRepaid = uint256(alicePosition.borrowShares).toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);
        vm.startPrank($.alice);
        ERC20Mock($.marketConfig.loanToken).setBalance($.alice, expectedAmountRepaid);
        $.loanToken.approve(address($.dahlia), expectedAmountRepaid);
        vm.resumeGasMetering();
        $.dahlia.repayAndWithdraw($.marketId, pos.collateral, 0, alicePosition.borrowShares, $.alice, $.alice);
        vm.pauseGasMetering();
        vm.stopPrank();

        IDahlia.UserPosition memory userPos = $.dahlia.getPosition($.marketId, $.alice);
        assertEq(userPos.borrowShares, 0, "position borrow shares balance");
        assertEq(userPos.collateral, 0, "position collateral balance");
        assertEq($.collateralToken.balanceOf($.alice), pos.collateral, "user collateral token balance");
        assertEq($.collateralToken.balanceOf(address($.dahlia)), 0, "Dahlia collateral token balance");
    }

    function test_int_staleMarket_disallowWithdrawNotStalled(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        vm.startPrank($.alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.WrongStatus.selector, IDahlia.MarketStatus.Active));
        vm.resumeGasMetering();
        $.dahlia.withdrawDepositAndClaimCollateral($.marketId, $.alice, $.bob);
    }

    function test_int_staleMarket_disallowWithdrawRepayPeriodNotEnded(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        vm.resumeGasMetering();
        staleMarket($.marketId);
        vm.pauseGasMetering();

        vm.startPrank($.alice);
        vm.expectRevert(Errors.RepayPeriodNotEnded.selector);
        vm.resumeGasMetering();
        $.dahlia.withdrawDepositAndClaimCollateral($.marketId, $.alice, $.bob);
    }

    function calcMarketClaims(IDahlia.MarketId id, address user) internal view returns (uint256 lendAssets, uint256 collateralAssets, uint256 shares) {
        IDahlia.Market memory market = $.dahlia.getMarket(id);
        IDahlia.UserPosition memory lenderPosition = $.dahlia.getPosition(id, user);
        shares = uint256(lenderPosition.lendShares);

        // calculate owner assets based on liquidity in the market
        lendAssets = shares.toAssetsDown(market.totalLendAssets - market.totalBorrowAssets, market.totalLendShares);
        // calculate owed collateral based on lend shares
        collateralAssets = (lenderPosition.lendPrincipalAssets * market.totalCollateralAssets) / market.totalLendPrincipalAssets;
    }

    function test_int_staleMarket_withdrawRepayPeriodEnded(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        vm.resumeGasMetering();
        staleMarket($.marketId);
        vm.pauseGasMetering();

        uint256 repayPeriod = $.dahliaRegistry.getValue(Constants.VALUE_ID_REPAY_PERIOD);
        skip(repayPeriod);

        (uint256 lendAssets, uint256 collateralAssets, uint256 shares) = calcMarketClaims($.marketId, $.carol);

        vm.startPrank($.carol);
        emit IDahlia.WithdrawDepositAndClaimCollateral($.marketId, $.carol, $.bob, $.carol, lendAssets, collateralAssets, shares);
        vm.resumeGasMetering();
        $.dahlia.withdrawDepositAndClaimCollateral($.marketId, $.carol, $.bob);
        vm.pauseGasMetering();

        IDahlia.UserPosition memory carolPosition = $.dahlia.getPosition($.marketId, $.carol);
        assertEq(carolPosition.lendShares, 0, "position lend shares balance");
        assertEq(carolPosition.lendPrincipalAssets, 0, "position lend assets balance");
        assertEq($.collateralToken.balanceOf($.bob), collateralAssets, "carol collateral token balance");
        assertEq($.loanToken.balanceOf($.bob), lendAssets, "carol loan token balance");
    }

    function test_int_staleMarket_withdrawMultiRepayPeriodEnded(TestTypes.MarketPosition memory pos) public {
        vm.pauseGasMetering();
        pos = vm.generatePositionInLtvRange(pos, TestConstants.MIN_TEST_LLTV, $.marketConfig.lltv);
        vm.dahliaSubmitPosition(pos, $.carol, $.alice, $);

        vm.dahliaLendBy($.maria, pos.lent, $);
        skip(26 weeks);

        vm.resumeGasMetering();
        staleMarket($.marketId);
        vm.pauseGasMetering();

        uint256 repayPeriod = $.dahliaRegistry.getValue(Constants.VALUE_ID_REPAY_PERIOD);
        skip(repayPeriod);

        // withdraw by carol
        (uint256 lendAssetsCarol, uint256 collateralAssetsCarol, uint256 sharesCarol) = calcMarketClaims($.marketId, $.carol);

        IDahlia.Market memory marketBefore = $.dahlia.getMarket($.marketId);
        vm.startPrank($.carol);
        vm.expectEmit(true, true, true, true, address($.vault));
        emit InitializableERC20.Transfer($.carol, address(0), $.dahlia.getPosition($.marketId, $.carol).lendPrincipalAssets);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.WithdrawDepositAndClaimCollateral($.marketId, $.carol, $.bob, $.carol, lendAssetsCarol, collateralAssetsCarol, sharesCarol);
        vm.expectEmit(true, true, true, true, address($.loanToken));
        emit InitializableERC20.Transfer(address($.vault), $.bob, lendAssetsCarol);
        vm.expectEmit(true, true, true, true, address($.collateralToken));
        emit InitializableERC20.Transfer(address($.dahlia), $.bob, collateralAssetsCarol);
        vm.resumeGasMetering();
        $.dahlia.withdrawDepositAndClaimCollateral($.marketId, $.carol, $.bob);
        vm.pauseGasMetering();

        IDahlia.UserPosition memory carolPosition = $.dahlia.getPosition($.marketId, $.carol);
        assertEq(carolPosition.lendShares, 0, "carol position lend shares balance");
        assertEq(carolPosition.lendPrincipalAssets, 0, "carol position lend principal balance");
        assertEq($.collateralToken.balanceOf($.bob), collateralAssetsCarol, "carol collateral token balance");
        assertEq($.loanToken.balanceOf($.bob), lendAssetsCarol, "carol loan token balance");

        // withdraw by maria
        vm.startPrank($.maria);

        (uint256 lendAssetsMaria, uint256 collateralAssetsMaria, uint256 sharesMaria) = calcMarketClaims($.marketId, $.maria);

        vm.expectEmit(true, true, true, true, address($.vault));
        emit InitializableERC20.Transfer($.maria, address(0), $.dahlia.getPosition($.marketId, $.maria).lendPrincipalAssets);
        vm.expectEmit(true, true, true, true, address($.dahlia));
        emit IDahlia.WithdrawDepositAndClaimCollateral($.marketId, $.maria, $.maria, $.maria, lendAssetsMaria, collateralAssetsMaria, sharesMaria);
        vm.expectEmit(true, true, true, true, address($.loanToken));
        emit InitializableERC20.Transfer(address($.vault), $.maria, lendAssetsMaria);
        vm.expectEmit(true, true, true, true, address($.collateralToken));
        emit InitializableERC20.Transfer(address($.dahlia), $.maria, collateralAssetsMaria);
        vm.resumeGasMetering();
        $.dahlia.withdrawDepositAndClaimCollateral($.marketId, $.maria, $.maria);
        vm.pauseGasMetering();

        IDahlia.UserPosition memory mariaPosition = $.dahlia.getPosition($.marketId, $.maria);
        assertEq(mariaPosition.lendShares, 0, "maria position lend shares balance");
        assertEq($.collateralToken.balanceOf($.maria), collateralAssetsMaria, "maria collateral token balance");
        assertEq($.loanToken.balanceOf($.maria), lendAssetsMaria, "maria loan token balance");

        IDahlia.Market memory market = $.dahlia.getMarket($.marketId);
        assertEq(market.status, IDahlia.MarketStatus.Stalled, "market is staled");
        assertEq(market.totalLendShares, 0, "market total lend shares");
        assertEq($.loanToken.balanceOf(address($.vault)), 0, "Dahlia lend token balance");
        assertLe($.collateralToken.balanceOf(address($.dahlia)), 1, "Dahlia collateral token balance should not be bigger than 1");
        assertEq(market.totalLendAssets - market.totalBorrowAssets, 0, "market available assets");
        assertGt(market.totalCollateralAssets, 0, "market collateral assets stays the same");
        assertGt(market.totalLendAssets, 0, "market left over lend assets covered after all withdrawals");
        assertGt(market.totalBorrowAssets, 0, "market left over borrow assets covered by collateral");
        assertEq(market.totalCollateralAssets, marketBefore.totalCollateralAssets, "totalCollateralAssets as it used to distribute collateral");
        assertEq(market.totalLendPrincipalAssets, marketBefore.totalLendPrincipalAssets, "totalLendPrincipalAssets as it used to distribute borrow");
    }
}
