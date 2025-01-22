// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import { IERC20Permit, IERC2612 } from "@openzeppelin/contracts/interfaces/IERC2612.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";
import { EIP712 } from "@solady/utils/EIP712.sol";

/// @notice Modern and gas efficient ERC20 + EIP-2612 implementation.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol), Shivaansh Kapoor, Jack Corddry
/// @author Modified from Uniswap (https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/UniswapV2ERC20.sol)
/// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
abstract contract InitializableERC20 is Initializable, IERC20Errors, IERC2612, EIP712, Nonces {
    bytes32 private constant HASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @dev The permit is invalid.
    error InvalidPermit();

    /// @dev The permit has expired.
    error PermitExpired();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    uint8 public decimals;

    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address => mapping(address => uint256)) public allowance;

    function _initializeERC20(string memory _name, string memory _symbol, uint8 _decimals) internal onlyInitializing {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    /**
     * @notice copied from OpenZeppelin ERC20.sol
     * @dev Updates `from` s allowance for `spender` based on spent `value`.
     *
     * Does not update the allowance value in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Does not emit an {Approval} event.
     */
    function _spendAllowance(address from, uint256 value) internal virtual {
        uint256 currentAllowance = allowance[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= value, ERC20InsufficientAllowance(msg.sender, currentAllowance, value));
            unchecked {
                _approve(from, msg.sender, currentAllowance - value, false);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice copied from OpenZeppelin ERC20.sol
     * @dev Variant of {_approve} with an optional flag to enable or disable the {Approval} event.
     *
     * By default (when calling {_approve}) the flag is set to true. On the other hand, approval changes made by
     * `_spendAllowance` during the `transferFrom` operation set the flag to false. This saves gas by not emitting any
     * `Approval` event during `transferFrom` operations.
     *
     * Anyone who wishes to continue emitting `Approval` events on the`transferFrom` operation can force the flag to
     * true using the following override:
     *
     * ```solidity
     * function _approve(address owner, address spender, uint256 value, bool) internal virtual override {
     *     super._approve(owner, spender, value, true);
     * }
     * ```
     *
     * Requirements are the same as {_approve}.
     */
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual {
        require(owner != address(0), ERC20InvalidApprover(address(0)));
        require(spender != address(0), ERC20InvalidSpender(address(0)));
        allowance[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        _approve(msg.sender, spender, amount, true);
        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool);

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool);

    /*//////////////////////////////////////////////////////////////
                             EIP-2612 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// Helper function to be used to sign a permit
    function hashTypedData(address owner, address spender, uint256 value, uint256 nonce, uint256 deadline) public view returns (bytes32) {
        return _hashTypedData(keccak256(abi.encode(HASH, owner, spender, value, nonce, deadline)));
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public virtual {
        require(deadline >= block.timestamp, PermitExpired());

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            bytes32 digest = hashTypedData(owner, spender, value, _useNonce(owner), deadline);
            address recoveredAddress = ecrecover(digest, v, r, s);

            require(recoveredAddress != address(0) && recoveredAddress == owner, InvalidPermit());

            allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    /*//////////////////////////////////////////////////////////////
                             EIP-712 LOGIC
    //////////////////////////////////////////////////////////////*/
    function _domainNameAndVersion() internal view override returns (string memory, string memory) {
        return (name, "1");
    }

    function _domainNameAndVersionMayChange() internal pure override returns (bool result) {
        return true;
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparator();
    }

    function nonces(address owner) public view override(IERC20Permit, Nonces) returns (uint256) {
        return Nonces.nonces(owner);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 amount) internal virtual {
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        emit Transfer(from, address(0), amount);
    }
}
