// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { MarketMath } from "src/core/helpers/MarketMath.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";

/// @title BorrowImpl library
/// @notice Implements borrowing protocol functions
library BorrowImpl {
    using SafeCastLib for uint256;
    using FixedPointMathLib for uint256;
    using SharesMathLib for uint256;

    // Add collateral to a borrower's position
    function internalSupplyCollateral(
        IDahlia.MarketId id,
        IDahlia.Market storage market,
        IDahlia.UserPosition storage ownerPosition,
        uint256 assets,
        address owner
    ) internal {
        ownerPosition.collateral += assets.toUint128();
        market.totalCollateralAssets += assets;

        emit IDahlia.SupplyCollateral(id, msg.sender, owner, assets);
    }

    // Withdraw collateral from a borrower's position
    function internalWithdrawCollateral(
        IDahlia.MarketId id,
        IDahlia.Market storage market,
        IDahlia.UserPosition storage ownerPosition,
        uint256 assets,
        address owner,
        address receiver
    ) internal {
        ownerPosition.collateral -= assets.toUint128(); // Decrease collateral
        market.totalCollateralAssets -= assets;

        // Ensure sufficient collateral for withdrawal
        if (ownerPosition.borrowShares > 0) {
            uint256 borrowedAssets = SharesMathLib.toAssetsUp(ownerPosition.borrowShares, market.totalBorrowAssets, market.totalBorrowShares);
            uint256 collateralPrice = MarketMath.getCollateralPrice(market.oracle);
            uint256 maxBorrowAssets = MarketMath.calcMaxBorrowAssets(collateralPrice, ownerPosition.collateral, market.lltv);
            if (borrowedAssets > maxBorrowAssets) {
                revert Errors.InsufficientCollateral(borrowedAssets, maxBorrowAssets);
            }
        }

        emit IDahlia.WithdrawCollateral(id, msg.sender, owner, receiver, assets);
    }

    // Borrow assets from the market
    function internalBorrow(
        IDahlia.MarketId id,
        IDahlia.Market storage market,
        IDahlia.UserPosition storage ownerPosition,
        uint256 assets,
        address owner,
        address receiver
    ) internal returns (uint256) {
        uint256 totalBorrowAssets = market.totalBorrowAssets;
        uint256 totalLendAssets = market.totalLendAssets;
        uint256 totalBorrowShares = market.totalBorrowShares;
        uint256 shares = assets.toSharesUp(totalBorrowAssets, totalBorrowShares);
        totalBorrowAssets += assets;

        // Ensure sufficient liquidity
        require(totalBorrowAssets <= totalLendAssets, Errors.InsufficientLiquidity(totalBorrowAssets, totalLendAssets));

        totalBorrowShares += shares;
        uint256 ownerBorrowShares = ownerPosition.borrowShares + shares;

        // Ensure user has enough collateral
        uint256 borrowedAssets = SharesMathLib.toAssetsUp(ownerBorrowShares, totalBorrowAssets, totalBorrowShares);
        uint256 collateralPrice = MarketMath.getCollateralPrice(market.oracle);

        uint256 maxBorrowAssets = MarketMath.calcMaxBorrowAssets(collateralPrice, ownerPosition.collateral, market.lltv);
        require(borrowedAssets <= maxBorrowAssets, Errors.InsufficientCollateral(borrowedAssets, maxBorrowAssets));

        // Update borrow values in totals and position
        ownerPosition.borrowShares = ownerBorrowShares.toUint128();
        market.totalBorrowAssets = totalBorrowAssets;
        market.totalBorrowShares = totalBorrowShares;
        emit IDahlia.Borrow(id, msg.sender, owner, receiver, assets, shares);
        return shares;
    }

    // Repay borrowed assets
    function internalRepay(
        IDahlia.MarketId id,
        IDahlia.Market storage market,
        IDahlia.UserPosition storage ownerPosition,
        uint256 assets,
        uint256 shares,
        address owner
    ) internal returns (uint256, uint256) {
        MarketMath.validateExactlyOneZero(assets, shares);
        // Calculate assets or shares
        if (assets > 0) {
            shares = assets.toSharesDown(market.totalBorrowAssets, market.totalBorrowShares);
        } else {
            assets = shares.toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);
        }
        // Update borrow values in totals and position
        ownerPosition.borrowShares -= shares.toUint128();
        market.totalBorrowShares -= shares;
        market.totalBorrowAssets = market.totalBorrowAssets.zeroFloorSub(assets);

        emit IDahlia.Repay(id, msg.sender, owner, assets, shares);
        return (assets, shares);
    }
}
