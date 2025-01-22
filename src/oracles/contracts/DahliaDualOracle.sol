// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IDahliaOracle } from "src/oracles/interfaces/IDahliaOracle.sol";

/// @title DualOracle
/// @notice Dual oracle where the secondary oracle is used if the primary oracle fails
contract DahliaDualOracle is IDahliaOracle {
    IDahliaOracle public immutable ORACLE_PRIMARY;
    IDahliaOracle public immutable ORACLE_SECONDARY;

    /// @notice Emitted when the contract is deployed
    /// @param primary address of Primary oracle
    /// @param secondary address of Secondary oracle
    event ParamsUpdated(address indexed primary, address indexed secondary);

    /// @notice Initializes the contract
    /// @param primary address of Primary oracle
    /// @param secondary address of Secondary oracle
    constructor(address primary, address secondary) {
        ORACLE_PRIMARY = IDahliaOracle(primary);
        ORACLE_SECONDARY = IDahliaOracle(secondary);
        ORACLE_PRIMARY.getPrice(); // should support getPrice
        ORACLE_SECONDARY.getPrice(); // should support getPrice
        emit ParamsUpdated(primary, secondary);
    }

    /// @inheritdoc IDahliaOracle
    function getPrice() external view returns (uint256, bool) {
        (uint256 price, bool primaryBadPrice) = ORACLE_PRIMARY.getPrice();
        if (primaryBadPrice) {
            return ORACLE_SECONDARY.getPrice();
        }
        return (price, primaryBadPrice);
    }
}
