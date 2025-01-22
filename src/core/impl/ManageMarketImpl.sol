// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { Constants } from "src/core/helpers/Constants.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { IDahliaWrappedVault } from "src/royco/interfaces/IDahliaWrappedVault.sol";

/// @title ManageMarketImpl library
/// @notice Implements market deployment and protocol fee
library ManageMarketImpl {
    using SafeCastLib for uint256;

    function setProtocolFeeRate(IDahlia.MarketId id, IDahlia.Market storage market, uint256 newFee) internal {
        require(newFee <= Constants.MAX_FEE_RATE, Errors.MaxFeeExceeded());
        market.protocolFeeRate = uint24(newFee);
        emit IDahlia.SetProtocolFeeRate(id, newFee);
    }

    function setReserveFeeRate(IDahlia.MarketId id, IDahlia.Market storage market, uint256 newFee) internal {
        require(newFee != market.reserveFeeRate, Errors.AlreadySet());
        require(newFee <= Constants.MAX_FEE_RATE, Errors.MaxFeeExceeded());

        market.reserveFeeRate = newFee.toUint24();
        emit IDahlia.SetReserveFeeRate(id, newFee);
    }

    function deployMarket(
        mapping(IDahlia.MarketId => IDahlia.MarketData) storage markets,
        IDahlia.MarketId id,
        IDahlia.MarketConfig memory marketConfig,
        IDahliaWrappedVault vault,
        uint256 protocolFeeRate
    ) internal {
        IDahlia.Market storage market = markets[id].market;
        require(market.updatedAt == 0, Errors.MarketAlreadyDeployed());

        market.loanToken = marketConfig.loanToken;
        market.collateralToken = marketConfig.collateralToken;
        market.oracle = marketConfig.oracle;
        market.irm = marketConfig.irm;
        market.fullUtilizationRate = marketConfig.irm.minFullUtilizationRate().toUint64();
        market.ratePerSec = marketConfig.irm.zeroUtilizationRate().toUint64();
        market.lltv = marketConfig.lltv.toUint24();
        market.updatedAt = uint48(block.timestamp);
        market.status = IDahlia.MarketStatus.Active;
        market.liquidationBonusRate = marketConfig.liquidationBonusRate.toUint24();
        market.vault = vault;
        emit IDahlia.DeployMarket(id, vault, marketConfig);
        setProtocolFeeRate(id, market, protocolFeeRate);
    }
}
