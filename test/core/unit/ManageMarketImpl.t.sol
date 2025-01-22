// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { Constants } from "src/core/helpers/Constants.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { ManageMarketImpl } from "src/core/impl/ManageMarketImpl.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { IDahliaWrappedVault } from "src/royco/interfaces/IDahliaWrappedVault.sol";
import { TestContext } from "test/common/TestContext.sol";

contract ManageMarketImplUnitTest is Test {
    TestContext ctx;
    mapping(IDahlia.MarketId => IDahlia.MarketData) internal markets;

    function setUp() public {
        ctx = new TestContext(vm);
    }

    function test_unit_manage_deployMarket_success(IDahlia.MarketConfig memory marketParamsFuzz, IDahliaWrappedVault vault) public {
        marketParamsFuzz.irm = ctx.createTestIrm();
        marketParamsFuzz.lltv = bound(marketParamsFuzz.lltv, Constants.DEFAULT_MIN_LLTV, Constants.DEFAULT_MAX_LLTV);
        marketParamsFuzz.liquidationBonusRate =
            bound(marketParamsFuzz.liquidationBonusRate, Constants.DEFAULT_MIN_LIQUIDATION_BONUS_RATE, Constants.DEFAULT_MAX_LIQUIDATION_BONUS_RATE);

        IDahlia.MarketId marketParamsFuzzId = IDahlia.MarketId.wrap(1);
        vm.expectEmit(true, true, true, true, address(this));
        emit IDahlia.DeployMarket(marketParamsFuzzId, vault, marketParamsFuzz);

        vm.expectEmit(true, true, true, true, address(this));
        emit IDahlia.SetProtocolFeeRate(marketParamsFuzzId, Constants.DAHLIA_MARKET_INITIAL_PROTOCOL_FEE);

        ManageMarketImpl.deployMarket(markets, marketParamsFuzzId, marketParamsFuzz, vault, Constants.DAHLIA_MARKET_INITIAL_PROTOCOL_FEE);

        IDahlia.Market memory market = markets[marketParamsFuzzId].market;
        assertEq(market.collateralToken, marketParamsFuzz.collateralToken);
        assertEq(market.loanToken, marketParamsFuzz.loanToken);
        assertEq(address(market.irm), address(marketParamsFuzz.irm));
        assertEq(address(market.oracle), address(marketParamsFuzz.oracle));
        assertEq(market.lltv, marketParamsFuzz.lltv);

        assertEq(market.updatedAt, block.timestamp, "updatedAt = block.timestamp");
        assertEq(market.totalLendAssets, 0, "totalLendAssets = 0");
        assertEq(market.totalLendShares, 0, "totalLendShares = 0");
        assertEq(market.totalBorrowAssets, 0, "totalBorrowAssets = 0");
        assertEq(market.totalBorrowShares, 0, "totalBorrowShares = 0");
        assertEq(market.protocolFeeRate, Constants.DAHLIA_MARKET_INITIAL_PROTOCOL_FEE, "fee != 0");
        assertEq(address(market.vault), address(vault), "marketProxy = vault");
    }

    function test_unit_manage_deployMarket_alreadyDeployed(IDahlia.MarketConfig memory marketParamsFuzz, IDahliaWrappedVault vault) public {
        marketParamsFuzz.irm = ctx.createTestIrm();
        marketParamsFuzz.lltv = bound(marketParamsFuzz.lltv, Constants.DEFAULT_MIN_LLTV, Constants.DEFAULT_MAX_LLTV);
        marketParamsFuzz.liquidationBonusRate =
            bound(marketParamsFuzz.liquidationBonusRate, Constants.DEFAULT_MIN_LIQUIDATION_BONUS_RATE, Constants.DEFAULT_MAX_LIQUIDATION_BONUS_RATE);
        IDahlia.MarketId marketParamsFuzzId = IDahlia.MarketId.wrap(1);

        ManageMarketImpl.deployMarket(markets, marketParamsFuzzId, marketParamsFuzz, vault, Constants.DAHLIA_MARKET_INITIAL_PROTOCOL_FEE);

        vm.expectRevert(Errors.MarketAlreadyDeployed.selector);
        ManageMarketImpl.deployMarket(markets, marketParamsFuzzId, marketParamsFuzz, vault, Constants.DAHLIA_MARKET_INITIAL_PROTOCOL_FEE);
    }
}
