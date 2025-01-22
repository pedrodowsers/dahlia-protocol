// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title Interest Rate Model Interface
/// @notice Interface for the interest rate model.
interface IIrm {
    /// @notice Get the current zero utilization rate.
    /// @dev Use this to set the initial interest rate in the constructor.
    function zeroUtilizationRate() external view returns (uint256);

    /// @notice Get the rate when the market is fully utilized.
    /// @dev Use this to set the initial interest rate at 100% utilization.
    function minFullUtilizationRate() external view returns (uint256);

    /// @notice Get the name of the Interest Rate Model.
    function name() external view returns (string memory);

    /// @notice Get the version of the Interest Rate Model.
    /// @dev It's a single-digit number.
    function version() external view returns (uint256);

    /// @notice Calculate new interest rates based on utilization.
    /// @param deltaTime Time since the last update in seconds.
    /// @param utilization Utilization percentage with 5 decimal precision.
    /// @param oldFullUtilizationRate Interest rate at 100% utilization, 18 decimals.
    /// @return newRatePerSec New interest rate per second, 18 decimals.
    /// @return newFullUtilizationRate New max interest rate, 18 decimals.
    function getNewRate(uint256 deltaTime, uint256 utilization, uint256 oldFullUtilizationRate)
        external
        view
        returns (uint256 newRatePerSec, uint256 newFullUtilizationRate);

    /// @notice Calculate interest based on elapsed time and utilization.
    /// @param deltaTime Time elapsed in seconds.
    /// @param totalLendAssets Total assets lent.
    /// @param totalBorrowAssets Total assets borrowed.
    /// @param oldFullUtilizationRate Previous full utilization rate.
    /// @return interestEarnedAssets Interest earned in assets.
    /// @return newRatePerSec New interest rate per second.
    /// @return newFullUtilizationRate New max interest rate.
    function calculateInterest(uint256 deltaTime, uint256 totalLendAssets, uint256 totalBorrowAssets, uint256 oldFullUtilizationRate)
        external
        view
        returns (uint256 interestEarnedAssets, uint256 newRatePerSec, uint256 newFullUtilizationRate);
}
