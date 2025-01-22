// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IDahliaLiquidateCallback
/// @notice Interface for contracts that need to receive a callback after a liquidation occurs.
/// @dev The callback is triggered only if the `data` parameter in the `liquidate` function is not empty.
interface IDahliaLiquidateCallback {
    /// @notice Function to be called when a liquidation occurs.
    /// @param repaidAssets The amount of assets repaid during the liquidation.
    /// @param data Arbitrary data passed to the `liquidate` function.
    function onDahliaLiquidate(uint256 repaidAssets, bytes calldata data) external;
}

/// @title IDahliaRepayCallback
/// @notice Interface for contracts that need to receive a callback after a repayment occurs.
/// @dev The callback is triggered only if the `data` parameter in the `repay` function is not empty.
interface IDahliaRepayCallback {
    /// @notice Function to be called when a repayment occurs.
    /// @param assets The amount of assets repaid.
    /// @param data Arbitrary data passed to the `repay` function.
    function onDahliaRepay(uint256 assets, bytes calldata data) external;
}

/// @title IDahliaSupplyCollateralCallback
/// @notice Interface for contracts that need to receive a callback after collateral is supplied.
/// @dev The callback is triggered only if the `data` parameter in the `supplyCollateral` function is not empty.
interface IDahliaSupplyCollateralCallback {
    /// @notice Function to be called when collateral is supplied.
    /// @param assets The amount of collateral supplied.
    /// @param data Arbitrary data passed to the `supplyCollateral` function.
    function onDahliaSupplyCollateral(uint256 assets, bytes calldata data) external;
}

/// @title IDahliaFlashLoanCallback
/// @notice Interface for contracts that need to receive a callback after a flash loan occurs.
/// @dev The callback is triggered only if the `data` parameter in the `flashLoan` function is not empty.
interface IDahliaFlashLoanCallback {
    /// @notice Function to be called when a flash loan occurs.
    /// @param assets The amount of assets flash loaned.
    /// @param fee The fee amount.
    /// @param data Arbitrary data passed to the `flashLoan` function.
    function onDahliaFlashLoan(uint256 assets, uint256 fee, bytes calldata data) external;
}
