// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { MarketMath } from "src/core/helpers/MarketMath.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";

/// @title LiquidationImpl library
/// @notice Implements position liquidation
library LiquidationImpl {
    using FixedPointMathLib for uint256;
    using SharesMathLib for uint256;
    using MarketMath for uint256;
    using SafeCastLib for uint256;

    function internalLiquidate(
        IDahlia.MarketId id,
        IDahlia.Market storage market,
        IDahlia.UserPosition storage borrowerPosition,
        IDahlia.UserPosition storage reservePosition,
        address borrower
    ) internal returns (uint256 repaidAssets, uint256 repaidShares, uint256) {
        uint256 rescueAssets = 0;
        uint256 rescueShares = 0;
        uint256 totalBorrowAssets = market.totalBorrowAssets;
        uint256 totalBorrowShares = market.totalBorrowShares;
        uint256 borrowShares = borrowerPosition.borrowShares;
        uint256 collateral = borrowerPosition.collateral;

        // Retrieve collateral price from oracle
        uint256 collateralPrice = MarketMath.getCollateralPrice(market.oracle);
        // Calculate the current loan-to-value (LTV) ratio of the borrower's position
        uint256 borrowedAssets = borrowShares.toAssetsUp(totalBorrowAssets, totalBorrowShares);
        uint256 positionLTV = MarketMath.getLTV(borrowedAssets, collateral, collateralPrice);
        // Verify if the borrower's position is not healthy
        uint24 lltv = market.lltv;
        if (positionLTV < lltv) {
            revert Errors.HealthyPositionLiquidation(positionLTV, lltv);
        }

        // Determine collateral to seize and any bad debt
        (uint256 borrowAssets, uint256 seizedCollateral, uint256 bonusCollateral, uint256 badDebtAssets, uint256 badDebtShares) =
            MarketMath.calcLiquidation(totalBorrowAssets, totalBorrowShares, collateral, collateralPrice, borrowShares, market.liquidationBonusRate);

        // Remove all shares from the borrower's position
        borrowerPosition.borrowShares = 0;
        // Deduct seized collateral from the borrower's position
        borrowerPosition.collateral = (collateral - seizedCollateral).toUint128();
        market.totalCollateralAssets -= seizedCollateral;
        // Deduct borrower's assets from the market
        market.totalBorrowAssets = totalBorrowAssets - borrowAssets;
        // Deduct borrower's shares from the market
        market.totalBorrowShares = totalBorrowShares - borrowShares;

        if (badDebtAssets > 0) {
            // Determine available shares from reserves
            uint256 reserveShares = reservePosition.lendShares;
            // Calculate rescue assets and shares if reserve funds are available to cover the bad debt
            if (reserveShares > 0) {
                (rescueAssets, rescueShares) = MarketMath.calcRescueAssets(market.totalLendAssets, market.totalLendShares, badDebtAssets, reserveShares);
                // Reduce reserve lend shares
                reservePosition.lendShares -= rescueShares.toUint128();
                // Reduce total lend shares
                market.totalLendShares -= rescueShares;
            }
            // Reduce total lend assets by the amount of bad debt minus rescue assets
            market.totalLendAssets -= (badDebtAssets - rescueAssets);
        }

        // Calculate repaid assets and shares
        repaidAssets = borrowAssets - badDebtAssets;
        repaidShares = borrowShares - badDebtShares;

        emit IDahlia.Liquidate(
            id,
            msg.sender,
            borrower,
            repaidAssets,
            repaidShares,
            seizedCollateral,
            bonusCollateral,
            badDebtAssets,
            badDebtShares,
            rescueAssets,
            rescueShares,
            collateralPrice
        );

        return (repaidAssets, repaidShares, seizedCollateral);
    }
}
