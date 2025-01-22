// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

abstract contract DahliaOracleFactoryBase {
    error ZeroTimelockAddress();

    /// @dev Emitted from constructor timelock address
    event TimelockAddressUpdated(address timelock);

    /// @notice Address of timelock contract.
    address internal immutable _TIMELOCK;

    /// @notice Constructor sets the timelockAddress.
    /// @param timelock The address of the timelock.
    constructor(address timelock) {
        require(timelock != address(0), ZeroTimelockAddress());
        _TIMELOCK = timelock;
        emit TimelockAddressUpdated(timelock);
    }

    function timelockAddress() external view returns (address) {
        return _TIMELOCK;
    }
}
