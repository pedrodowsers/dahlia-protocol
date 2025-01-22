// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IIrm } from "src/irm/interfaces/IIrm.sol";

/// @title IDahliaRegistry
/// @notice Interface for managing addresses and values associated with specific IDs.

interface IDahliaRegistry {
    /// @notice Emitted when an IRM is added to the registry.
    /// @param irm The IRM that was added.
    event AllowIrm(IIrm indexed irm);

    /// @notice Emitted when an IRM is removed from the registry.
    /// @param irm The IRM that was removed.
    event DisallowIrm(IIrm indexed irm);

    /// @notice Emitted when an address is set for an ID.
    /// @param id The ID associated with the new address.
    /// @param newAddress The new address.
    event SetAddress(uint256 indexed id, address newAddress);

    /// @notice Emitted when a value is set for an ID.
    /// @param id The ID associated with the new value.
    /// @param newValue The new value.
    event SetValue(uint256 indexed id, uint256 newValue);

    /// @notice Retrieve the address associated with an ID.
    /// @param id The ID to query.
    /// @return address The associated address.
    function getAddress(uint256 id) external view returns (address);

    /// @notice Assign a new address to an ID.
    /// @param id The ID to update.
    /// @param _addr The new address.
    function setAddress(uint256 id, address _addr) external;

    /// @notice Assign a new value to an ID.
    /// @param id The ID to update.
    /// @param _val The new value.
    function setValue(uint256 id, uint256 _val) external;

    /// @notice Retrieve the value associated with an ID, or a default if not set.
    /// @param id The ID to query.
    /// @param _def Default value if none is set.
    /// @return The associated value or default.
    function getValue(uint256 id, uint256 _def) external view returns (uint256);

    /// @notice Retrieve the value associated with an ID.
    /// @param id The ID to query.
    /// @return The associated value.
    function getValue(uint256 id) external view returns (uint256);

    /// @notice Add an IRM address to the registry.
    /// @param irm The IRM address to add.
    function allowIrm(IIrm irm) external;

    /// @notice Remove an IRM address from the registry.
    /// @param irm The IRM address to remove.
    function disallowIrm(IIrm irm) external;

    /// @notice Verify if an IRM address is allowed for market deployment.
    /// @param irm The IRM address to check.
    /// @return True if allowed, false otherwise.
    function isIrmAllowed(IIrm irm) external view returns (bool);
}
