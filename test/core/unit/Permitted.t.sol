// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";
import { Test, Vm } from "forge-std/Test.sol";
import { Permitted } from "src/core/abstracts/Permitted.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";

contract PermittedContract is Permitted { }

contract PermittedTest is Test {
    using BoundUtils for Vm;

    PermittedContract internal permitted;

    function setUp() public {
        permitted = new PermittedContract();
    }

    function test_Permitted_updatePermission(address addressFuzz, address addressNotPermitted) public {
        vm.assume(addressFuzz != address(this));
        vm.assume(addressFuzz != addressNotPermitted);

        permitted.updatePermission(addressFuzz, true);

        assertTrue(permitted.isPermitted(address(this), addressFuzz));

        permitted.updatePermission(addressFuzz, false);

        assertFalse(permitted.isPermitted(address(this), addressFuzz));
        assertFalse(permitted.isPermitted(addressNotPermitted, addressFuzz));
    }

    function test_Permitted_alreadySet(address addressFuzz) public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadySet.selector));
        permitted.updatePermission(addressFuzz, false);

        permitted.updatePermission(addressFuzz, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadySet.selector));
        permitted.updatePermission(addressFuzz, true);
    }

    function test_Permitted_withSignatureDeadlineOutdated(Permitted.Data memory data, uint256 privateKey, uint256 blocks) public {
        data.isPermitted = true;
        blocks = vm.boundBlocks(blocks);
        data.deadline = block.timestamp - 1;

        // Private key must be less than the secp256k1 curve order.
        privateKey = bound(privateKey, 1, type(uint32).max);
        data.nonce = 0;
        data.signer = vm.addr(privateKey);

        bytes32 digest = permitted.hashTypedData(data);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.forward(blocks);

        vm.expectRevert(abi.encodeWithSelector(Errors.SignatureExpired.selector));
        permitted.updatePermissionWithSig(data, sig);
    }

    function test_Permitted_withSigWrongPK(Permitted.Data memory data, uint256 privateKey) public {
        data.isPermitted = true;
        data.deadline = bound(data.deadline, block.timestamp, type(uint256).max);

        // Private key must be less than the secp256k1 curve order.
        privateKey = bound(privateKey, 1, type(uint32).max);
        data.nonce = 0;

        bytes32 digest = permitted.hashTypedData(data);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidSignature.selector));
        permitted.updatePermissionWithSig(data, sig);
    }

    function test_Permitted_withSigWrongNonce(Permitted.Data memory data, uint256 privateKey) public {
        data.isPermitted = true;
        data.deadline = bound(data.deadline, block.timestamp, type(uint256).max);
        data.nonce = bound(data.nonce, 1, type(uint256).max);

        // Private key must be less than the secp256k1 curve order.
        privateKey = bound(privateKey, 1, type(uint32).max);
        data.signer = vm.addr(privateKey);

        bytes32 digest = permitted.hashTypedData(data);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(Nonces.InvalidAccountNonce.selector, data.signer, 0));
        permitted.updatePermissionWithSig(data, sig);
    }

    function test_Permitted_withSigSuccess(Permitted.Data memory data, uint256 privateKey) public {
        data.isPermitted = true;
        data.deadline = bound(data.deadline, block.timestamp, type(uint256).max);

        // Private key must be less than the secp256k1 curve order.
        privateKey = bound(privateKey, 1, type(uint32).max);
        data.nonce = 0;
        data.signer = vm.addr(privateKey);

        bytes32 digest = permitted.hashTypedData(data);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        permitted.updatePermissionWithSig(data, sig);

        assertEq(permitted.isPermitted(data.signer, data.permitted), true);
        assertEq(permitted.nonces(data.signer), 1);
    }

    function test_Permitted_withReusedSig(Permitted.Data memory data, uint256 privateKey) public {
        data.isPermitted = true;
        data.deadline = bound(data.deadline, block.timestamp, type(uint256).max);

        // Private key must be less than the secp256k1 curve order.
        privateKey = bound(privateKey, 1, type(uint32).max);
        data.nonce = 0;
        data.signer = vm.addr(privateKey);

        bytes32 digest = permitted.hashTypedData(data);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        permitted.updatePermissionWithSig(data, sig);

        vm.expectRevert(abi.encodeWithSelector(Nonces.InvalidAccountNonce.selector, data.signer, 1));
        permitted.updatePermissionWithSig(data, sig);
    }
}
