// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IPermitted
/// @notice Interface for managing permissions within the protocol
interface IPermitted {
    struct Data {
        address signer;
        address permitted;
        bool isPermitted;
        uint256 nonce;
        uint256 deadline;
    }

    /// @dev Emitted when permissions are updated.
    /// @param sender Address of the sender.
    /// @param owner Address of the owner.
    /// @param permitted Address that is permitted.
    /// @param newIsPermitted New permission status.
    event UpdatePermission(address indexed sender, address indexed owner, address indexed permitted, bool newIsPermitted);

    /// @notice Grant or revoke permission for a specific address.
    /// @param permitted The address to be granted or revoked permission.
    /// @param newIsPermitted `True` to grant permission, `false` to revoke.
    function updatePermission(address permitted, bool newIsPermitted) external;

    /// @notice Grant or revoke permission using an EIP-712 signature.
    /// @dev The function will fail if the signature is reused or invalid.
    /// @param data The details of the permission.
    /// @param signature The EIP-712 signature authorizing the change.
    function updatePermissionWithSig(Data memory data, bytes calldata signature) external;
}
