// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

abstract contract DahliaOracleStaticAddress {
    error ZeroStaticOracleAddress();

    /// @dev Emitted from constructor with static oracle address
    event StaticOracleAddressUpdated(address staticOracleAddress);

    address internal immutable _STATIC_ORACLE_ADDRESS;

    /// @notice Constructor sets the staticOracleAddress.
    constructor(address staticOracleAddress) {
        require(staticOracleAddress != address(0), ZeroStaticOracleAddress());
        _STATIC_ORACLE_ADDRESS = staticOracleAddress;
        emit StaticOracleAddressUpdated(_STATIC_ORACLE_ADDRESS);
    }

    function STATIC_ORACLE_ADDRESS() external view returns (address) {
        return _STATIC_ORACLE_ADDRESS;
    }
}
