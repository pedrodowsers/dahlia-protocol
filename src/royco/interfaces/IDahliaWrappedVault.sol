/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IWrappedVault } from "@royco/interfaces/IWrappedVault.sol";

interface IDahliaWrappedVault is IWrappedVault {
    /// @return The address of the vault owner
    function owner() external view returns (address);

    /// @param account The address to get the principal balance of
    /// @return The principal balance of the given account
    function principal(address account) external view returns (uint256);

    /// @return The total principal of all accounts
    function totalPrincipal() external view returns (uint256);

    /// @param shares The amount of shares to mint
    /// @param receiver The address to mint the fees for
    /// @dev Can be called only by the Dahlia contract, used only to emit transfer event
    function mintFees(uint256 shares, address receiver) external;

    /// @param from The address to burn the shares for
    /// @param shares The amount of shares to burn
    /// @dev Can be called only by the Dahlia contract, used only to emit transfer event
    function burnShares(address from, uint256 shares) external;

    /// @param to The address to send the rewards to
    /// @param reward The reward token / points program to claim rewards from
    function claim(address to, address reward) external payable;
}
