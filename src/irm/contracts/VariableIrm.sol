// SPDX-License-Identifier: ISC
pragma solidity ^0.8.27;

// Adapted from https://github.com/FraxFinance/fraxlend/

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { IrmConstants } from "src/irm/helpers/IrmConstants.sol";
import { IIrm } from "src/irm/interfaces/IIrm.sol";

/// @title Variable Interest Rate Model
/// @notice Calculates interest rates based on utilization and time
contract VariableIrm is IIrm {
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;

    /// @notice Emitted when the contract is deployed
    /// @param config Initial config
    event VariableIrmConfig(Config config);

    struct Config {
        /// @notice Min utilization where no rate adjustment happens
        /// @dev Should be less than `targetUtilization`, e.g., 0.75 * Constants.UTILIZATION_100_PERCENT
        uint256 minTargetUtilization;
        /// @notice Max utilization where no rate adjustment happens
        /// @dev Should be more than `targetUtilization`, e.g., 0.80 * Constants.UTILIZATION_100_PERCENT
        uint256 maxTargetUtilization;
        /// @notice Utilization level where IR curve slope increases
        /// e.g., 0.80 * Constants.UTILIZATION_100_PERCENT
        uint256 targetUtilization;
        /// @notice Half-life of interest rate in seconds, affects adjustment speed
        /// At 100% utilization, rates double at this rate; at 0%, they halve
        /// e.g., 172,800 seconds (2 days)
        /// @dev Max value is 194.18 days
        uint256 rateHalfLife;
        // Interest Rate Settings (per second), 365.24 days/year
        /// @notice Min interest rate at 100% utilization
        /// e.g., 1582470460 (~5% yearly), 18 decimals
        uint256 minFullUtilizationRate;
        /// @notice Max interest rate at 100% utilization
        /// e.g., 3_164_940_920_000 (~10000% yearly), 18 decimals
        uint256 maxFullUtilizationRate;
        /// @notice Interest rate at 0% utilization
        /// e.g., 158247046 (~0.5% yearly), 18 decimals
        uint256 zeroUtilizationRate;
        /// @notice Percentage of delta between full and zero utilization rates
        /// e.g., 0.2e18, 18 decimals
        uint256 targetRatePercent;
        /// @notice IRM name
        string name;
    }

    uint256 public immutable minFullUtilizationRate;
    uint256 public immutable maxFullUtilizationRate;
    uint256 public immutable zeroUtilizationRate;
    uint256 public immutable targetRatePercent;
    uint24 public immutable minTargetUtilization; // 3 bytes
    uint24 public immutable maxTargetUtilization; // 3 bytes
    uint24 public immutable targetUtilization; // 3 bytes
    uint24 public immutable rateHalfLife; // 3 bytes
    string public name;

    /// @param _config Config parameters for variable interest rate
    constructor(Config memory _config) {
        minFullUtilizationRate = _config.minFullUtilizationRate;
        maxFullUtilizationRate = _config.maxFullUtilizationRate;
        zeroUtilizationRate = _config.zeroUtilizationRate;
        targetRatePercent = _config.targetRatePercent;
        minTargetUtilization = _config.minTargetUtilization.toUint24();
        maxTargetUtilization = _config.maxTargetUtilization.toUint24();
        targetUtilization = _config.targetUtilization.toUint24();
        rateHalfLife = _config.rateHalfLife.toUint24();
        name = _config.name;
        emit VariableIrmConfig(_config);
    }

    /// @inheritdoc IIrm
    function version() external pure returns (uint256) {
        return 1;
    }

    /// @notice Calculate new max interest rate at 100% utilization
    /// @dev Interest is per second
    /// @param deltaTime Time since last update in seconds
    /// @param utilization Utilization % with 5 decimals precision
    /// @param fullUtilizationRate Interest at 100% utilization, 18 decimals
    /// @return newFullUtilizationRate New max interest rate
    function _getFullUtilizationInterest(uint256 deltaTime, uint256 utilization, uint256 fullUtilizationRate)
        internal
        view
        returns (uint256 newFullUtilizationRate)
    {
        uint256 _minTargetUtilization = minTargetUtilization;
        uint256 _maxTargetUtilization = maxTargetUtilization;
        uint256 _maxFullUtilizationRate = maxFullUtilizationRate;
        uint256 _minFullUtilizationRate = minFullUtilizationRate;

        if (utilization < _minTargetUtilization) {
            uint256 _rateHalfLife = rateHalfLife;
            uint256 _deltaUtilization = _minTargetUtilization - utilization;
            // 36 decimals
            uint256 _decayGrowth = _rateHalfLife + (_deltaUtilization * _deltaUtilization * deltaTime / _minTargetUtilization / _minTargetUtilization);
            // 18 decimals
            newFullUtilizationRate = (fullUtilizationRate * _rateHalfLife) / _decayGrowth;
        } else if (utilization > _maxTargetUtilization) {
            uint256 _rateHalfLife = rateHalfLife;
            uint256 _leftUtilization = IrmConstants.UTILIZATION_100_PERCENT - _maxTargetUtilization;
            uint256 _deltaUtilization = utilization - _maxTargetUtilization;
            // 36 decimals
            uint256 _decayGrowth = _rateHalfLife + (_deltaUtilization * _deltaUtilization * deltaTime) / _leftUtilization / _leftUtilization;
            // 18 decimals
            newFullUtilizationRate = (fullUtilizationRate * _decayGrowth) / _rateHalfLife;
        } else {
            newFullUtilizationRate = fullUtilizationRate;
        }
        return newFullUtilizationRate.min(_maxFullUtilizationRate).max(_minFullUtilizationRate);
    }

    /// @inheritdoc IIrm
    function getNewRate(uint256 deltaTime, uint256 utilization, uint256 oldFullUtilizationRate)
        external
        view
        returns (uint256 newRatePerSec, uint256 newFullUtilizationRate)
    {
        return _getNewRate(deltaTime, utilization, oldFullUtilizationRate);
    }

    function _getNewRate(uint256 deltaTime, uint256 utilization, uint256 oldFullUtilizationRate)
        internal
        view
        returns (uint256 newRatePerSec, uint256 newFullUtilizationRate)
    {
        uint256 _zeroUtilizationRate = zeroUtilizationRate;
        uint256 _targetUtilization = targetUtilization;

        newFullUtilizationRate = _getFullUtilizationInterest(deltaTime, utilization, oldFullUtilizationRate);

        // Calculate target rate as a percentage of the delta between min and max interest
        uint256 _targetRate = _zeroUtilizationRate + FixedPointMathLib.mulWad(newFullUtilizationRate - _zeroUtilizationRate, targetRatePercent);

        if (utilization < _targetUtilization) {
            // For readability, the following formula is equivalent to:
            // slope = ((_targetRate - zeroUtilizationRate) * Constants.UTILIZATION_100_PERCENT) / targetUtilization;
            // newRatePerSec = uint64(zeroUtilizationRate + ((utilization * slope) / Constants.UTILIZATION_100_PERCENT));

            // 18 decimals
            newRatePerSec = _zeroUtilizationRate + (utilization * (_targetRate - _zeroUtilizationRate)) / _targetUtilization;
        } else {
            // For readability, the following formula is equivalent to:
            // slope = (((_newFullUtilizationInterest - _targetRate) * Constants.UTILIZATION_100_PERCENT) / (Constants.UTILIZATION_100_PERCENT -
            // _targetUtilization));
            // newRatePerSec = uint64(_targetRate + (((_utilization - _targetUtilization) * slope) / Constants.UTILIZATION_100_PERCENT));

            // 18 decimals
            newRatePerSec = _targetRate
                + ((utilization - _targetUtilization) * (newFullUtilizationRate - _targetRate)) / (IrmConstants.UTILIZATION_100_PERCENT - _targetUtilization);
        }
    }

    /// @inheritdoc IIrm
    function calculateInterest(uint256 deltaTime, uint256 totalLendAssets, uint256 totalBorrowAssets, uint256 fullUtilizationRate)
        external
        view
        returns (uint256 _interestEarnedAssets, uint256 _newRatePerSec, uint256 _newFullUtilizationRate)
    {
        // Calculate utilization rate
        uint256 _utilizationRate = totalLendAssets == 0 ? 0 : (IrmConstants.UTILIZATION_100_PERCENT * totalBorrowAssets) / totalLendAssets;

        // Get new interest rate and full utilization rate
        (_newRatePerSec, _newFullUtilizationRate) = _getNewRate(deltaTime, _utilizationRate, fullUtilizationRate);

        // Calculate accrued interest
        _interestEarnedAssets = (deltaTime * totalBorrowAssets * _newRatePerSec) / FixedPointMathLib.WAD;
    }
}
