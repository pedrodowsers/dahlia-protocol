// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { LibString } from "@solady/utils/LibString.sol";
import { Constants } from "src/core/helpers/Constants.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";
import { IDahliaOracle } from "src/oracles/interfaces/IDahliaOracle.sol";

/// @title MarketMath
/// @notice Math utilities for the Dahlia protocol, handling collateral, loan calculations, and liquidation logic
/// @dev Provides safe math operations for lending and borrowing calculations
library MarketMath {
    using FixedPointMathLib for uint256;
    using SharesMathLib for *;
    using LibString for uint256;

    /// @dev Converts collateral to loan assets, rounding up
    function collateralToLendUp(uint256 collateral, uint256 collateralPrice) internal pure returns (uint256) {
        return collateral.mulDivUp(collateralPrice, Constants.ORACLE_PRICE_SCALE);
    }

    function lendToCollateralUp(uint256 assets, uint256 collateralPrice) internal pure returns (uint256) {
        return assets.mulDivUp(Constants.ORACLE_PRICE_SCALE, collateralPrice);
    }

    /// @dev Get percentage up (x * %) / 100
    function mulPercentUp(uint256 value, uint256 percent) internal pure returns (uint256) {
        return value.mulDivUp(percent, Constants.LLTV_100_PERCENT);
    }

    /// @dev Get percentage down (x * 100) / %
    function divPercentUp(uint256 value, uint256 percent) internal pure returns (uint256) {
        return value.mulDivUp(Constants.LLTV_100_PERCENT, percent);
    }

    /// @dev Calculates liquidation details, including borrowed assets, collateral seized, bonuses, and any bad debt
    function calcLiquidation(
        uint256 totalBorrowAssets,
        uint256 totalBorrowShares,
        uint256 collateral,
        uint256 collateralPrice,
        uint256 borrowShares,
        uint256 liquidationBonusRate
    ) internal pure returns (uint256 borrowedAssets, uint256 seizedCollateral, uint256 bonusCollateral, uint256 badDebtInAssets, uint256 badDebtInShares) {
        // Convert borrow shares to assets
        borrowedAssets = borrowShares.toAssetsDown(totalBorrowAssets, totalBorrowShares);
        // Convert borrowed assets to collateral
        uint256 borrowedInCollateral = lendToCollateralUp(borrowedAssets, collateralPrice);
        // Limit collateral for bonus calculation
        uint256 limitedCollateralForCalcBonus = FixedPointMathLib.min(borrowedInCollateral, collateral);
        // Calculate liquidator bonus
        bonusCollateral = mulPercentUp(limitedCollateralForCalcBonus, liquidationBonusRate);
        // Total collateral to seize
        seizedCollateral = borrowedInCollateral + bonusCollateral;

        // Check for bad debt
        if (seizedCollateral > collateral) {
            // Calculate bad debt in collateral
            uint256 badDebtInCollateral = seizedCollateral - collateral;
            // Convert to loan assets
            badDebtInAssets = collateralToLendUp(badDebtInCollateral, collateralPrice);
            // Convert to shares
            badDebtInShares = badDebtInAssets.toSharesUp(totalBorrowAssets, totalBorrowShares);
            // Adjust seized collateral
            seizedCollateral = collateral;
        }
    }

    /// @dev Calculates the assets to rescue from reserves, given bad debt and available reserve shares
    function calcRescueAssets(uint256 totalLendAssets, uint256 totalLendShares, uint256 badDebtAssets, uint256 reserveShares)
        internal
        pure
        returns (uint256 rescueAssets, uint256 rescueShares)
    {
        uint256 reserveAssets = reserveShares.toAssetsUp(totalLendAssets, totalLendShares);
        rescueAssets = FixedPointMathLib.min(badDebtAssets, reserveAssets);
        rescueShares = rescueAssets.toSharesDown(totalLendAssets, totalLendShares);
    }

    /// @dev Calculates the maximum liquidation bonus rate based on the given LLTV
    function getMaxLiquidationBonusRate(uint256 lltv) internal pure returns (uint256) {
        return FixedPointMathLib.min(Constants.DEFAULT_MAX_LIQUIDATION_BONUS_RATE, (Constants.LLTV_100_PERCENT - lltv) * 3 / 4);
    }

    /// @dev Checks if exactly one of two values is zero, used for validation purposes
    function validateExactlyOneZero(uint256 x, uint256 y) internal pure {
        bool z;
        assembly {
            z := xor(iszero(x), iszero(y))
        }
        require(z, Errors.InconsistentAssetsOrSharesInput());
    }

    /// @dev Calculates the maximum amount of assets that can be borrowed based on collateral and LLTV
    function calcMaxBorrowAssets(uint256 collateralPrice, uint256 collateral, uint256 lltv) internal pure returns (uint256) {
        uint256 totalCollateralCapacity = collateralToLendUp(collateral, collateralPrice);
        return mulPercentUp(totalCollateralCapacity, lltv);
    }

    /// @dev Calculates the LTV based on borrowed assets and collateral value
    function getLTV(uint256 borrowedAssets, uint256 collateral, uint256 collateralPrice) internal pure returns (uint256) {
        uint256 totalCollateralCapacity = collateralToLendUp(collateral, collateralPrice);
        return totalCollateralCapacity == 0 ? 0 : borrowedAssets.mulDivUp(Constants.LLTV_100_PERCENT, totalCollateralCapacity);
    }

    /// @dev Fetches the current collateral price from the oracle
    function getCollateralPrice(IDahliaOracle oracle) internal view returns (uint256 collateralPrice) {
        bool isBadData;
        (collateralPrice, isBadData) = oracle.getPrice();
        require(!isBadData && collateralPrice > 0, Errors.OraclePriceBadData());
    }
}
