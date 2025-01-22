// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

/// @title SharesMathLib
/// @dev Math utilities for converting between assets and shares, inspired by Solady and Uniswap.
/// See lib/solady/src/tokens/ERC4626.sol and
/// https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/FullMath.sol for reference.
library SharesMathLib {
    using FixedPointMathLib for uint256;

    uint8 internal constant VIRTUAL_SHARES_DECIMALS = 6;
    uint256 internal constant SHARES_OFFSET = 1e6; // Offset to prevent division by zero

    function toSharesDown(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return assets.mulDiv(totalShares + SHARES_OFFSET, totalAssets + 1);
    }

    function toAssetsDown(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.mulDiv(totalAssets + 1, totalShares + SHARES_OFFSET);
    }

    function toSharesUp(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return assets.mulDivUp(totalShares + SHARES_OFFSET, totalAssets + 1);
    }

    function toAssetsUp(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.mulDivUp(totalAssets + 1, totalShares + SHARES_OFFSET);
    }
}
