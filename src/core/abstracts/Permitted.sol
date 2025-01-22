// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";
import { ECDSA } from "@solady/utils/ECDSA.sol";
import { EIP712 } from "@solady/utils/EIP712.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { IPermitted } from "src/core/interfaces/IPermitted.sol";

/// @title Permitted
/// @notice Handles permission management using signatures and nonces.
abstract contract Permitted is IPermitted, EIP712, Nonces {
    mapping(address => mapping(address => bool)) public isPermitted;

    bytes32 private constant HASH = keccak256("Permit(address signer,address permitted,bool isPermitted,uint256 nonce,uint256 deadline)");

    function hashTypedData(Data memory data) public view returns (bytes32) {
        return _hashTypedData(keccak256(abi.encode(HASH, data)));
    }

    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        return ("Dahlia", "1");
    }

    modifier isSenderPermitted(address permitted) {
        address sender = msg.sender;
        require(_isSenderPermitted(permitted), Errors.NotPermitted(sender));
        _;
    }

    /// @inheritdoc IPermitted
    function updatePermission(address permitted, bool newIsPermitted) external {
        if (newIsPermitted == isPermitted[msg.sender][permitted]) {
            revert Errors.AlreadySet();
        }
        isPermitted[msg.sender][permitted] = newIsPermitted;

        emit UpdatePermission(msg.sender, msg.sender, permitted, newIsPermitted);
    }

    /// @inheritdoc IPermitted
    function updatePermissionWithSig(Data memory data, bytes calldata signature) external {
        require(block.timestamp <= data.deadline, Errors.SignatureExpired());
        bytes32 digest = hashTypedData(data);
        address recoveredSigner = ECDSA.recover(digest, signature);
        require(data.signer == recoveredSigner, Errors.InvalidSignature());
        _useCheckedNonce(recoveredSigner, data.nonce);

        isPermitted[data.signer][data.permitted] = data.isPermitted;

        emit UpdatePermission(msg.sender, recoveredSigner, data.permitted, data.isPermitted);
    }

    /// @notice Checks if the sender is allowed to manage the positions of `permitted`.
    /// @param permitted The address to check permission for.
    /// @return True if permitted, false otherwise.
    function _isSenderPermitted(address permitted) internal view returns (bool) {
        address sender = msg.sender;
        return sender == permitted || isPermitted[permitted][sender];
    }
}
