// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IDahlia } from "src/core/interfaces/IDahlia.sol";

/// @title Errors library
/// @notice Contains error messages for the protocol.
library Errors {
    /// @notice Insufficient liquidity for borrowing, collateral withdrawal, or loan withdrawal.
    error InsufficientLiquidity(uint256 totalBorrowAssets, uint256 totalLendAssets);

    /// @notice Insufficient collateral to borrow.
    error InsufficientCollateral(uint256 borrowedAssets, uint256 maxBorrowAssets);

    /// @notice Cannot liquidate a healthy position.
    error HealthyPositionLiquidation(uint256 ltv, uint256 lltv);

    /// @notice Address not permitted to call function on behalf of another.
    error NotPermitted(address sender);

    /// @notice Input assets are zero.
    error ZeroAssets();

    /// @notice Input address is zero.
    error ZeroAddress();

    /// @notice Market has not been deployed.
    error WrongStatus(IDahlia.MarketStatus status);

    /// @notice Attempting to deploy a market that already exists.
    error MarketAlreadyDeployed();

    /// @notice Assets or shares input is inconsistent.
    error InconsistentAssetsOrSharesInput();

    /// @notice Value has already been set.
    error AlreadySet();

    /// @notice Provided range is not valid.
    error RangeNotValid(uint256, uint256);

    /// @notice Maximum fee has been exceeded.
    error MaxFeeExceeded();

    /// @notice Interest Rate Model is not allowed in the registry.
    error IrmNotAllowed();

    /// @notice Liquidation LTV is not within the allowed range.
    error LltvNotAllowed();

    /// @notice Liquidation bonus rate is not allowed.
    error LiquidationBonusRateNotAllowed();

    /// @notice Oracle price data is stalled.
    error OraclePriceBadData();

    /// @notice Oracle price is not stalled.
    error OraclePriceNotStalled();

    /// @notice Repay period ended.
    error RepayPeriodEnded();

    /// @notice Repay period not ended.
    error RepayPeriodNotEnded();

    /// @notice Signature has expired.
    error SignatureExpired();

    /// @notice Signature is invalid.
    error InvalidSignature();
}
