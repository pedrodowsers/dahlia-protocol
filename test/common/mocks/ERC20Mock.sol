// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { MockERC20 } from "forge-std/mocks/MockERC20.sol";

contract ERC20Mock is IERC20, MockERC20 {
    event SetBalance(address account, uint256 amount);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        initialize(_name, _symbol, _decimals);
    }

    function mint(address to, uint256 value) public virtual {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public virtual {
        _burn(from, value);
    }

    function setBalance(address account, uint256 amount) public virtual {
        if (amount > _balanceOf[account]) {
            _totalSupply += amount - _balanceOf[account];
        } else {
            _totalSupply -= _balanceOf[account] - amount;
        }
        _balanceOf[account] = amount;
        emit SetBalance(account, _balanceOf[account]);
    }
}
