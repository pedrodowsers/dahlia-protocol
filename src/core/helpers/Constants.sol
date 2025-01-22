// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title Constants Library
/// @dev Contains various constant values used across the Dahlia protocol
library Constants {
    /// @dev Represents 100% for LLTV values, using 5 decimal precision.
    /// Examples: 100% = 100_000, 10% = 10_000, etc.
    uint256 internal constant LLTV_100_PERCENT = 1e5;

    /// @dev Precision factor for fees, using 5 decimal precision.
    uint256 internal constant FEE_PRECISION = 1e5;

    /// @dev The maximum fee rate for a market, set at 30% of FEE_PRECISION.
    uint256 internal constant MAX_FEE_RATE = 0.3e5;

    /// @dev The initial Dahlia protol fee, set at 5% of FEE_PRECISION.
    uint256 internal constant DAHLIA_MARKET_INITIAL_PROTOCOL_FEE = 0.05e5; // 5%

    /// @dev The maximum fee rate for flash loans, capped at 3% of FEE_PRECISION.
    uint256 internal constant MAX_FLASH_LOAN_FEE_RATE = 0.03e5;

    /// @dev Scale factor for oracle prices, using 36 decimal precision to handle large price values.
    uint256 internal constant ORACLE_PRICE_SCALE = 1e36;

    /// @dev Default minimum LLTV value, set at 30%.
    uint24 internal constant DEFAULT_MIN_LLTV = uint24(30 * Constants.LLTV_100_PERCENT / 100);

    /// @dev Default maximum LLTV value, set at 99%.
    uint24 internal constant DEFAULT_MAX_LLTV = uint24(99 * Constants.LLTV_100_PERCENT / 100);

    /// @dev Minimum liquidation bonus rate, set to 0.001% as the default.
    uint24 internal constant DEFAULT_MIN_LIQUIDATION_BONUS_RATE = uint24(1);

    /// @dev Maximum liquidation bonus rate, set to 15%.
    uint24 internal constant DEFAULT_MAX_LIQUIDATION_BONUS_RATE = uint24(15 * Constants.LLTV_100_PERCENT / 100);

    // Contract address IDs in DahliaRegistry
    /// @notice Address ID for the `Dahlia` contract in the registry.
    uint256 internal constant ADDRESS_ID_DAHLIA = 1;

    /// @notice Address ID for the `DahliaOracleFactory` contract in the registry.
    uint256 internal constant ADDRESS_ID_ORACLE_FACTORY = 4;

    /// @notice Address ID for the `IRMFactory` contract in the registry.
    uint256 internal constant ADDRESS_ID_IRM_FACTORY = 5;

    /// @notice Address ID for the Royco `WrappedVaultFactory` contract in the registry.
    uint256 internal constant ADDRESS_ID_ROYCO_WRAPPED_VAULT_FACTORY = 10;

    // Value IDs in DahliaRegistry
    /// @notice Initial frontend fee value for Royco's wrapped vaults.
    uint256 internal constant VALUE_ID_ROYCO_WRAPPED_VAULT_MIN_INITIAL_FRONTEND_FEE = 10;

    /// @notice Repay period duration.
    uint256 internal constant VALUE_ID_REPAY_PERIOD = 11;

    /// @notice Initial Dahlia initial protocol fee rate index
    uint256 internal constant VALUE_ID_DAHLIA_MARKET_INITIAL_PROTOCOL_FEE = 12;
}
