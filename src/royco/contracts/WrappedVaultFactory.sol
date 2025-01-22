// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { LibClone } from "@solady/utils/LibClone.sol";
import { LibString } from "@solady/utils/LibString.sol";
import { ERC4626 } from "@solmate/tokens/ERC4626.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { WrappedVault } from "src/royco/contracts/WrappedVault.sol";

/// @title WrappedVaultFactory
/// @author CopyPaste, Jack Corddry, Shivaansh Kapoor
/// @dev A factory for deploying wrapped vaults, and managing protocol or other fees
contract WrappedVaultFactory is Ownable2Step {
    using LibClone for address;

    // Address of the Wrapped Vault's implementation contract
    address public wrappedVaultImplementation;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address _wrappedVaultImplementation,
        address _protocolFeeRecipient,
        uint256 _protocolFee,
        uint256 _minimumFrontendFee,
        address _owner,
        address _pointsFactory,
        address _dahlia
    ) payable Ownable(_owner) {
        _setWrappedVaultImplementation(_wrappedVaultImplementation);
        _setProtocolFee(_protocolFee);
        _setProtocolFeeRecipient(_protocolFeeRecipient);
        _setMinimumReferralFee(_minimumFrontendFee);
        dahlia = _dahlia;
        emit DahliaUpdated(_dahlia);
        pointsFactory = _pointsFactory;
        emit PointsFactoryUpdated(_pointsFactory);
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_PROTOCOL_FEE = 0.3e18;
    uint256 public constant MAX_MIN_REFERRAL_FEE = 0.3e18;

    address public immutable pointsFactory;

    address public protocolFeeRecipient;

    /// @dev The protocolFee for all incentivized vaults
    uint256 public protocolFee;
    /// @dev The default minimumFrontendFee to initialize incentivized vaults with
    uint256 public minimumFrontendFee;

    /// @dev All incentivized vaults deployed by this factory
    address[] public incentivizedVaults;
    mapping(address => bool) public isVault;
    address public immutable dahlia;

    /*//////////////////////////////////////////////////////////////
                               INTERFACE
    //////////////////////////////////////////////////////////////*/
    error InvalidWrappedVaultImplementation();
    error ProtocolFeeTooHigh();
    error ReferralFeeTooHigh();
    error PermittedOnlyDahlia(address caller, address expectedCaller);

    event WrappedVaultImplementationUpdated(address newWrappedVaultImplementation);
    event ProtocolFeeUpdated(uint256 newProtocolFee);
    event ReferralFeeUpdated(uint256 newReferralFee);
    event ProtocolFeeRecipientUpdated(address newRecipient);
    event PointsFactoryUpdated(address newPointsFactory);
    event DahliaUpdated(address newDahlia);
    event WrappedVaultCreated(
        ERC4626 indexed underlyingVaultAddress,
        WrappedVault indexed incentivizedVaultAddress,
        address owner,
        address inputToken,
        uint256 frontendFee,
        string name,
        string vaultSymbol
    );

    /*//////////////////////////////////////////////////////////////
                             OWNER CONTROLS
    //////////////////////////////////////////////////////////////*/

    /// @param newWrappedVaultImplementation The new address of the Wrapped Vault implementation.
    function updateWrappedVaultImplementation(address newWrappedVaultImplementation) external payable onlyOwner {
        _setWrappedVaultImplementation(newWrappedVaultImplementation);
    }

    function _setWrappedVaultImplementation(address newWrappedVaultImplementation) internal {
        if (newWrappedVaultImplementation.code.length == 0) revert InvalidWrappedVaultImplementation();
        wrappedVaultImplementation = newWrappedVaultImplementation;
        emit WrappedVaultImplementationUpdated(newWrappedVaultImplementation);
    }

    /// @param newProtocolFee The new protocol fee to set for a given vault, must be less than MAX_PROTOCOL_FEE
    function updateProtocolFee(uint256 newProtocolFee) external payable onlyOwner {
        _setProtocolFee(newProtocolFee);
    }

    function _setProtocolFee(uint256 newProtocolFee) internal {
        if (newProtocolFee > MAX_PROTOCOL_FEE) revert ProtocolFeeTooHigh();
        protocolFee = newProtocolFee;
        emit ProtocolFeeUpdated(newProtocolFee);
    }

    /// @param newMinimumReferralFee The new minimum referral fee to set for all incentivized vaults, must be less than MAX_MIN_REFERRAL_FEE
    function updateMinimumReferralFee(uint256 newMinimumReferralFee) external payable onlyOwner {
        _setMinimumReferralFee(newMinimumReferralFee);
    }

    function _setMinimumReferralFee(uint256 newMinimumReferralFee) internal {
        if (newMinimumReferralFee > MAX_MIN_REFERRAL_FEE) revert ReferralFeeTooHigh();
        minimumFrontendFee = newMinimumReferralFee;
        emit ReferralFeeUpdated(newMinimumReferralFee);
    }

    /// @param newRecipient The new protocol fee recipient to set for all incentivized vaults
    function updateProtocolFeeRecipient(address newRecipient) external payable onlyOwner {
        _setProtocolFeeRecipient(newRecipient);
    }

    function _setProtocolFeeRecipient(address newRecipient) internal {
        protocolFeeRecipient = newRecipient;
        emit ProtocolFeeRecipientUpdated(newRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                             VAULT CREATION
    //////////////////////////////////////////////////////////////*/

    /// @param id Dahlia market id
    /// @param loanToken The address of the loan token
    /// @param owner The address of the wrapped vault owner
    /// @param name The name of the wrapped vault
    /// @param initialFrontendFee The initial frontend fee for the wrapped vault ()
    function wrapVault(IDahlia.MarketId id, address loanToken, address owner, string calldata name, uint256 initialFrontendFee)
        external
        returns (WrappedVault wrappedVault)
    {
        require(msg.sender == dahlia, PermittedOnlyDahlia(msg.sender, dahlia));
        string memory newSymbol = string.concat("ROY-DAH-", LibString.toString(IDahlia.MarketId.unwrap(id)));
        bytes32 salt = keccak256(abi.encodePacked(id, owner, name, initialFrontendFee));
        wrappedVault = WrappedVault(wrappedVaultImplementation.cloneDeterministic(salt));
        uint8 decimals = IERC20Metadata(loanToken).decimals() + SharesMathLib.VIRTUAL_SHARES_DECIMALS;
        wrappedVault.initialize(owner, name, newSymbol, dahlia, decimals, id, loanToken, initialFrontendFee, pointsFactory);

        incentivizedVaults.push(address(wrappedVault));
        isVault[address(wrappedVault)] = true;

        // Emit wrapped vault address as both `underlyingVaultAddress` and `incentivizedVaultAddress`
        emit WrappedVaultCreated(ERC4626(address(wrappedVault)), wrappedVault, owner, address(wrappedVault.asset()), initialFrontendFee, name, newSymbol);
    }
}
