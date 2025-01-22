// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";

/// @title LendImpl library
/// @notice Implements protocol lending functions
library LendImpl {
    using SafeCastLib for uint256;
    using SharesMathLib for uint256;

    function internalLend(
        IDahlia.MarketId id,
        IDahlia.Market storage market,
        IDahlia.UserPosition storage ownerPosition,
        uint256 assets,
        uint256 shares,
        address owner
    ) internal returns (uint256, uint256) {
        if (assets == 0) {
            assets = shares.toAssetsUp(market.totalLendAssets, market.totalLendShares);
        } else {
            shares = assets.toSharesDown(market.totalLendAssets, market.totalLendShares);
        }
        ownerPosition.lendShares += shares.toUint128();
        ownerPosition.lendPrincipalAssets += assets.toUint128();
        market.totalLendPrincipalAssets += assets;
        market.totalLendShares += shares;
        market.totalLendAssets += assets;

        emit IDahlia.Lend(id, msg.sender, owner, assets, shares);
        return (assets, shares);
    }

    function internalWithdraw(
        IDahlia.MarketId id,
        IDahlia.Market storage market,
        IDahlia.UserPosition storage ownerPosition,
        uint256 assets,
        uint256 shares,
        address owner,
        address receiver
    ) internal returns (uint256, uint256, uint256) {
        uint256 totalLendAssets = market.totalLendAssets;
        uint256 totalLendShares = market.totalLendShares;
        if (assets == 0) {
            // If the user tries to withdraw a very small number of shares (less than SharesMathLib.SHARES_OFFSET),
            // they might receive 0 assets due to rounding. It is recommended to use the "assets" parameter for
            // partial withdrawals, while the "shares" parameter should be used for withdrawing all available assets (100%).
            assets = shares.toAssetsDown(totalLendAssets, totalLendShares);
        } else {
            shares = assets.toSharesUp(totalLendAssets, totalLendShares);
        }
        totalLendAssets -= assets;
        if (market.totalBorrowAssets > totalLendAssets) {
            revert Errors.InsufficientLiquidity(market.totalBorrowAssets, totalLendAssets);
        }
        uint256 ownerLendShares = ownerPosition.lendShares - shares;
        ownerPosition.lendShares = ownerLendShares.toUint128();
        market.totalLendShares = totalLendShares - shares;
        market.totalLendAssets = totalLendAssets;

        emit IDahlia.Withdraw(id, msg.sender, receiver, owner, assets, shares);
        return (assets, shares, ownerLendShares);
    }

    function internalWithdrawDepositAndClaimCollateral(
        IDahlia.MarketId id,
        IDahlia.Market storage market,
        IDahlia.UserPosition storage ownerPosition,
        address owner,
        address receiver
    ) internal returns (uint256 lendAssets, uint256 collateralAssets) {
        uint256 shares = ownerPosition.lendShares;
        require(shares > 0, Errors.ZeroAssets());
        uint256 totalCollateralAssets = market.totalCollateralAssets;
        uint256 totalLendAssets = market.totalLendAssets;
        uint256 totalLendShares = market.totalLendShares;

        // calculate owner assets based on liquidity in the market
        lendAssets = shares.toAssetsDown(totalLendAssets - market.totalBorrowAssets, totalLendShares);
        // Calculate owed collateral based on lendPrincipalAssets
        collateralAssets = (ownerPosition.lendPrincipalAssets * totalCollateralAssets) / market.totalLendPrincipalAssets;

        market.vault.burnShares(owner, ownerPosition.lendPrincipalAssets);
        ownerPosition.lendShares = 0;
        ownerPosition.lendPrincipalAssets = 0;
        market.totalLendShares = totalLendShares - shares;
        market.totalLendAssets = totalLendAssets - lendAssets;

        emit IDahlia.WithdrawDepositAndClaimCollateral(id, msg.sender, receiver, owner, lendAssets, collateralAssets, shares);
    }
}
