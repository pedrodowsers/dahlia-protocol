// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IIrm } from "src/irm/interfaces/IIrm.sol";
import { IDahliaOracle } from "src/oracles/interfaces/IDahliaOracle.sol";
import { IDahliaWrappedVault } from "src/royco/interfaces/IDahliaWrappedVault.sol";

/// @title IDahlia
/// @notice Interface for main Dahlia protocol functions
interface IDahlia {
    type MarketId is uint32;

    enum MarketStatus {
        Uninitialized,
        Active,
        Paused,
        Stalled,
        Deprecated
    }

    struct RateRange {
        uint24 min;
        uint24 max;
    }

    struct Market {
        // --- 24 bytes
        uint24 lltv; // 3 bytes
        MarketStatus status; // 1 byte
        address loanToken; // 20 bytes
        // --- 32 bytes
        address collateralToken; // 20 bytes
        uint48 updatedAt; // 6 bytes
        uint24 protocolFeeRate; // 3 bytes // taken from interest
        uint24 reserveFeeRate; // 3 bytes // taken from interest
        // --- 31 bytes
        IDahliaOracle oracle; // 20 bytes
        uint24 liquidationBonusRate; // 3 bytes
        uint64 fullUtilizationRate; // 8 bytes
        // --- 28 bytes
        IIrm irm; // 20 bytes
        uint64 ratePerSec; // 8 bytes // stores refreshed rate per second
        // --- 26 bytes
        IDahliaWrappedVault vault; // 20 bytes
        uint48 repayPeriodEndTimestamp; // 6 bytes
        // --- having all 256 bytes at the end makes deployment size smaller
        uint256 totalLendAssets; // 32 bytes // principal + interest - bad debt
        uint256 totalLendShares; // 32 bytes
        uint256 totalBorrowAssets; // 32 bytes
        uint256 totalBorrowShares; // 32 bytes
        uint256 totalLendPrincipalAssets; // 32 bytes // stores total principal (initially lent) assets
        uint256 totalCollateralAssets; // 32 bytes
    }

    struct UserPosition {
        uint128 lendShares;
        uint128 lendPrincipalAssets;
        uint128 borrowShares;
        uint128 collateral;
    }

    struct MarketData {
        Market market;
        mapping(address => UserPosition) userPositions;
    }

    /// @dev Emitted when the DahliaRegistry is set.
    /// @param dahliaRegistry Address of the new Dahlia registry.
    event SetDahliaRegistry(address indexed dahliaRegistry);

    /// @dev Emitted when the protocol fee rate is updated.
    /// @param id Market id.
    /// @param newFee The updated fee rate.
    event SetProtocolFeeRate(IDahlia.MarketId indexed id, uint256 newFee);

    /// @dev Emitted when the reserve fee rate is updated.
    /// @param id Market id.
    /// @param newFee The updated fee rate.
    event SetReserveFeeRate(IDahlia.MarketId indexed id, uint256 newFee);

    /// @dev Emitted when the protocol fee recipient is changed.
    /// @param newProtocolFeeRecipient Address of the new fee recipient.
    event SetProtocolFeeRecipient(address indexed newProtocolFeeRecipient);

    /// @dev Emitted when the reserve fee recipient is changed.
    /// @param newReserveFeeRecipient Address of the new reserve fee recipient.
    event SetReserveFeeRecipient(address indexed newReserveFeeRecipient);

    /// @dev Emitted when the flash loan fee rate is updated.
    /// @param newFee The updated flash loan fee rate.
    event SetFlashLoanFeeRate(uint256 newFee);

    /// @dev Emitted when a new LLTV range is set.
    /// @param minLltv Minimum LLTV value.
    /// @param maxLltv Maximum LLTV value.
    event SetLLTVRange(uint256 minLltv, uint256 maxLltv);

    /// @dev Emitted when a new liquidation bonus rate range is set.
    /// @param minLiquidationBonusRate Minimum liquidation bonus rate.
    /// @param maxLiquidationBonusRate Maximum liquidation bonus rate.
    event SetLiquidationBonusRateRange(uint256 minLiquidationBonusRate, uint256 maxLiquidationBonusRate);

    /// @dev Emitted when the market status changes.
    /// @param id Market id.
    /// @param from Previous market status.
    /// @param to New market status.
    event MarketStatusChanged(IDahlia.MarketId indexed id, IDahlia.MarketStatus from, IDahlia.MarketStatus to);

    /// @dev Emitted when the liquidation bonus rate changes.
    /// @param id Market id.
    /// @param liquidationBonusRate The updated liquidation bonus rate.
    event LiquidationBonusRateChanged(IDahlia.MarketId indexed id, uint256 liquidationBonusRate);

    /// @dev Emitted when a new market is deployed.
    /// @param id Market id.
    /// @param vault Address of the Royco WrappedVault associated with the market.
    /// @param marketConfig Configuration parameters for the market.
    event DeployMarket(IDahlia.MarketId indexed id, IDahliaWrappedVault indexed vault, IDahlia.MarketConfig marketConfig);

    /// @dev Emitted when collateral is supplied.
    /// @param id Market id.
    /// @param caller Address of the caller.
    /// @param owner Address of the position owner.
    /// @param assets Amount of assets supplied as collateral.
    event SupplyCollateral(IDahlia.MarketId indexed id, address indexed caller, address indexed owner, uint256 assets);

    /// @dev Emitted when collateral is withdrawn.
    /// @param id Market id.
    /// @param caller Address of the caller.
    /// @param owner Address of the position owner.
    /// @param receiver Address receiving the withdrawn assets.
    /// @param assets Amount of assets withdrawn.
    event WithdrawCollateral(IDahlia.MarketId indexed id, address caller, address indexed owner, address indexed receiver, uint256 assets);

    /// @dev Emitted when assets are supplied.
    /// @param id Market id.
    /// @param caller Address of the caller.
    /// @param owner Address of the position owner.
    /// @param assets Amount of assets supplied.
    /// @param shares Amount of shares minted.
    event Lend(IDahlia.MarketId indexed id, address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    /// @dev Emitted when assets are withdrawn.
    /// @param id Market id.
    /// @param caller Address of the caller.
    /// @param receiver Address receiving the withdrawn assets.
    /// @param owner Address of the position owner.
    /// @param assets Amount of assets withdrawn.
    /// @param shares Amount of shares burned.
    event Withdraw(IDahlia.MarketId indexed id, address caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    /// @dev Emitted when user calls final withdrawal on Stalled market.
    /// @param id Market id.
    /// @param caller Address of the caller.
    /// @param receiver Address receiving the withdrawn assets.
    /// @param owner Address of the position owner.
    /// @param assets Amount of assets withdrawn.
    /// @param collateralAssets Amount of collateral assets withdrawn.
    /// @param shares Amount of shares burned.
    event WithdrawDepositAndClaimCollateral(
        IDahlia.MarketId indexed id, address caller, address indexed receiver, address indexed owner, uint256 assets, uint256 collateralAssets, uint256 shares
    );

    /// @dev Emitted when assets are borrowed.
    /// @param id Market id.
    /// @param caller Address of the caller.
    /// @param owner Address of the position owner.
    /// @param receiver Address receiving the borrowed assets.
    /// @param assets Amount of assets borrowed.
    /// @param shares Amount of shares minted.
    event Borrow(IDahlia.MarketId indexed id, address caller, address indexed owner, address indexed receiver, uint256 assets, uint256 shares);

    /// @dev Emitted when assets are repaid.
    /// @param id Market id.
    /// @param caller Address of the caller.
    /// @param owner Address of the position owner.
    /// @param assets Amount of assets repaid.
    /// @param shares Amount of shares burned.
    event Repay(IDahlia.MarketId indexed id, address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    /// @dev Emitted when a position is liquidated.
    /// @param id Market id.
    /// @param caller Address of the caller.
    /// @param borrower Address of the borrower.
    /// @param repaidAssets Amount of assets repaid.
    /// @param repaidShares Amount of shares burned.
    /// @param seizedCollateral Amount of collateral seized.
    /// @param bonusCollateral Amount of bonus collateral.
    /// @param badDebtAssets Amount of bad debt assets realized.
    /// @param badDebtShares Amount of bad debt shares realized.
    /// @param rescuedAssets Amount of assets rescued from reserve.
    /// @param rescuedShares Amount of shares rescued from reserve.
    /// @param collateralPrice Collateral price.
    event Liquidate(
        IDahlia.MarketId indexed id,
        address indexed caller,
        address indexed borrower,
        uint256 repaidAssets,
        uint256 repaidShares,
        uint256 seizedCollateral,
        uint256 bonusCollateral,
        uint256 badDebtAssets,
        uint256 badDebtShares,
        uint256 rescuedAssets,
        uint256 rescuedShares,
        uint256 collateralPrice
    );

    /// @dev Emitted when interest is accrued.
    /// @param id Market id.
    /// @param newRatePerSec New rate per second.
    /// @param interest Amount of interest accrued.
    /// @param protocolFeeShares Shares minted as protocol fee.
    /// @param reserveFeeShares Shares minted as reserve fee.
    event AccrueInterest(IDahlia.MarketId indexed id, uint256 newRatePerSec, uint256 interest, uint256 protocolFeeShares, uint256 reserveFeeShares);

    /// @dev Emitted when a flash loan is executed.
    /// @param caller Address of the caller.
    /// @param token Address of the token flash loaned.
    /// @param assets Amount of assets flash loaned.
    /// @param fee Fee amount for the flash loan.
    event FlashLoan(address indexed caller, address indexed token, uint256 assets, uint256 fee);

    /// @notice Get user position for a market id and address with accrued interest.
    /// @param id Market id.
    /// @param userAddress User address.
    function getPosition(MarketId id, address userAddress) external view returns (UserPosition memory position);

    /// @notice Get max borrowable assets for a user in a market.
    /// @param id Market id.
    /// @param userAddress User address.
    /// @param additionalCollateral Amount of additional collateral assets.
    /// @return borrowedAssets Amount of borrowed assets.
    /// @return borrowableAssets Amount of borrowable assets.
    /// @return collateralPrice Collateral price.
    function getMaxBorrowableAmount(MarketId id, address userAddress, uint256 additionalCollateral)
        external
        view
        returns (uint256 borrowedAssets, uint256 borrowableAssets, uint256 collateralPrice);

    /// @notice Get user's loan-to-value ratio for a market.
    /// @param id Market id.
    /// @param userAddress User address.
    function getPositionLTV(MarketId id, address userAddress) external view returns (uint256);

    /// @notice Get user's earned interest for a market.
    /// @param id Market id.
    /// @param userAddress User address.
    /// @return assets Number of assets earned as interest.
    /// @return shares Number of shares earned as interest.
    function getPositionInterest(MarketId id, address userAddress) external view returns (uint256 assets, uint256 shares);

    /// @notice Get market parameters.
    /// @param id Market id.
    function getMarket(MarketId id) external view returns (Market memory);

    /// @notice Check if a market is deployed.
    /// @param id Market id.
    function isMarketDeployed(MarketId id) external view returns (bool);

    /// @notice Pause a market.
    /// @param id Market id.
    function pauseMarket(MarketId id) external;

    /// @notice Unpause a market.
    /// @param id Market id.
    function unpauseMarket(MarketId id) external;

    /// @notice Update liquidation bonus rate for the market.
    /// @param id Market id.
    /// @param liquidationBonusRate New liquidation bonus rate, precision: Constants.LLTV_100_PERCENT.
    function updateLiquidationBonusRate(MarketId id, uint256 liquidationBonusRate) external;

    /// @notice Deprecate a market.
    /// @param id Market id.
    function deprecateMarket(MarketId id) external;

    /// @notice Get protocol fee recipient address.
    function protocolFeeRecipient() external view returns (address);

    /// @notice Set LLTV range for market creation.
    /// @param range Min-max range.
    function setLltvRange(RateRange memory range) external;

    /// @notice Set liquidation bonus rate range for market creation.
    /// @param range Min-max range.
    function setLiquidationBonusRateRange(RateRange memory range) external;

    /// @notice Set protocol fee recipient for all markets.
    /// @param newProtocolFeeRecipient New protocol fee recipient address.
    function setProtocolFeeRecipient(address newProtocolFeeRecipient) external;

    /// @notice Set reserve fee recipient for all markets.
    /// @param newReserveFeeRecipient New reserve fee recipient address.
    function setReserveFeeRecipient(address newReserveFeeRecipient) external;

    /// @notice Sets flash loan fee.
    /// @param newFee New flash loan fee.
    function setFlashLoanFeeRate(uint24 newFee) external;

    /// @notice Configuration parameters for deploying a new market.
    /// @param loanToken The address of the loan token.
    /// @param collateralToken The address of the collateral token.
    /// @param oracle The oracle contract for price feeds.
    /// @param irm The interest rate model contract.
    /// @param lltv Liquidation loan-to-value ratio for the market.
    /// @param liquidationBonusRate Bonus rate for liquidations.
    /// @param name Name of the deployed market.
    /// @param owner The owner of the deployed market.
    struct MarketConfig {
        address loanToken;
        address collateralToken;
        IDahliaOracle oracle;
        IIrm irm;
        uint256 lltv;
        uint256 liquidationBonusRate;
        string name;
        address owner;
    }

    /// @notice Deploys a new market with the given parameters and returns its id.
    /// @param marketConfig The parameters of the market.
    function deployMarket(MarketConfig memory marketConfig) external returns (MarketId id);

    /// @notice Set new protocol fee for a market.
    /// @param id Market id.
    /// @param newFee New fee, precision: Constants.FEE_PRECISION.
    function setProtocolFeeRate(MarketId id, uint32 newFee) external;

    /// @notice Set new reserve fee for a market.
    /// @param id Market id.
    /// @param newFee New fee, precision: Constants.FEE_PRECISION.
    function setReserveFeeRate(MarketId id, uint32 newFee) external;

    /// @notice Lend `assets` on behalf of a user, with optional callback.
    /// @dev Should be called via wrapped vault.
    /// @dev Either `assets` or `shares` must be zero.
    /// @param id Market id.
    /// @param assets Amount of assets to lend.
    /// @param owner Owner of the increased lend position.
    /// @return assetsLent Amount of lent assets.
    /// @return sharesMinted Amount of shares minted.
    function lend(MarketId id, uint256 assets, uint256 shares, address owner) external returns (uint256 assetsLent, uint256 sharesMinted);

    /// @notice Withdraw `assets` by `shares` on behalf of a user, sending to a receiver.
    /// @dev Should be invoked through a wrapped vault.
    /// @dev Either `assets` or `shares` must be zero.
    /// @param id Market id.
    /// @param assets Amount of assets to withdraw.
    /// @param shares Amount of shares to withdraw.
    /// @param receiver Address receiving the assets.
    /// @param owner Owner of the lend position.
    /// @return assetsWithdrawn Amount of assets withdrawn.
    /// @return sharesWithdrawn Amount of shares withdrawn.
    function withdraw(MarketId id, uint256 assets, uint256 shares, address receiver, address owner)
        external
        returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn);

    /// @notice Transfer lend shares between two users.
    /// @dev Should be invoked through a wrapped vault.
    /// @param id Market id.
    /// @param owner Address owning the lend shares.
    /// @param receiver Address receiving the lend shares.
    /// @param amount Amount of lend shares to transfer.
    function transferLendShares(MarketId id, address owner, address receiver, uint256 amount) external returns (bool);

    /// @notice Estimates the interest rate after depositing a specified amount of assets.
    /// @dev Should be invoked through a wrapped vault.
    /// @param id Market id.
    /// @param assets The amount of assets intended for deposit.
    /// @return ratePerSec The projected interest rate per second post-deposit.
    function previewLendRateAfterDeposit(MarketId id, uint256 assets) external view returns (uint256 ratePerSec);

    /// @notice Borrow `assets` on behalf of a user, sending to a receiver.
    /// @dev Either `assets` or `shares` must be zero.
    /// @param id Market id.
    /// @param assets Amount of assets to borrow.
    /// @param owner Address owning the increased borrow position.
    /// @param receiver Address receiving the borrowed assets.
    /// @return borrowShares Amount of shares minted.
    function borrow(MarketId id, uint256 assets, address owner, address receiver) external returns (uint256 borrowShares);

    /// @notice Supply `collateralAssets` and borrow `borrowAssets` on behalf of a user, sending borrowed assets to a receiver.
    /// @dev Both `collateralAssets` and `borrowAssets` must not be zero.
    /// @param id Market id.
    /// @param collateralAssets Amount of assets for collateral.
    /// @param borrowAssets Amount of assets to borrow.
    /// @param owner Address owning the increased borrow position.
    /// @param receiver Address receiving the borrowed assets.
    /// @return borrowedShares Amount of shares minted.
    function supplyAndBorrow(MarketId id, uint256 collateralAssets, uint256 borrowAssets, address owner, address receiver)
        external
        returns (uint256 borrowedShares);

    /// @notice Repay borrowed assets or shares on behalf of a user and withdraw collateral to a receiver.
    /// @dev Either `repayAssets` or `repayShares` must be zero.
    /// @param id Market id.
    /// @param collateralAssets Amount of assets for collateral.
    /// @param repayAssets Amount of borrow assets to repay.
    /// @param repayShares Amount of borrow shares to burn.
    /// @param owner Owner of the debt position.
    /// @param receiver Address receiving the withdrawn collateral.
    /// @return repaidAssets Amount of assets repaid.
    /// @return repaidShares Amount of shares burned.
    function repayAndWithdraw(MarketId id, uint256 collateralAssets, uint256 repayAssets, uint256 repayShares, address owner, address receiver)
        external
        returns (uint256 repaidAssets, uint256 repaidShares);

    /// @notice Repay `assets` or `shares` on behalf of a user, with optional callback.
    /// @dev Either `assets` or `shares` must be zero.
    /// @param id Market id.
    /// @param assets Amount of assets to repay.
    /// @param shares Amount of shares to burn.
    /// @param owner Owner of the debt position.
    /// @param callbackData Data for `onDahliaRepay` callback. Empty if not needed.
    /// @return assetsRepaid Amount of assets repaid.
    /// @return sharesRepaid Amount of shares burned.
    function repay(MarketId id, uint256 assets, uint256 shares, address owner, bytes calldata callbackData)
        external
        returns (uint256 assetsRepaid, uint256 sharesRepaid);

    /// @notice Liquidate a debt position by repaying shares or seizing collateral, with optional callback.
    /// @param id Market id.
    /// @param borrower Borrower's address.
    /// @param callbackData Data for `onDahliaLiquidate` callback. Empty if not needed.
    /// @return collateralSeized Amount of collateral seized.
    /// @return assetsRepaid Amount of assets repaid.
    /// @return sharesRepaid Amount of shares repaid.
    function liquidate(MarketId id, address borrower, bytes calldata callbackData)
        external
        returns (uint256 collateralSeized, uint256 assetsRepaid, uint256 sharesRepaid);

    /// @notice Supplies collateral on behalf of a user, with an optional callback.
    /// @param id Market id.
    /// @param assets The amount of collateral to supply.
    /// @param owner The address that will own the increased collateral position.
    /// @param callbackData Arbitrary data to pass to the `onDahliaSupplyCollateral` callback.
    ///        Pass empty data if not needed.
    function supplyCollateral(MarketId id, uint256 assets, address owner, bytes calldata callbackData) external;

    /// @notice Withdraw collateral on behalf of a user, sending to a receiver.
    /// @param id Market id.
    /// @param assets Amount of collateral to withdraw.
    /// @param owner Owner of the debt position.
    /// @param receiver Address receiving the collateral assets.
    function withdrawCollateral(MarketId id, uint256 assets, address owner, address receiver) external;

    /// @notice Final withdrawal by lender from `stalled` market his portion of lending assets and portion of collateral assets based on his lending assets
    /// @param id Market id.
    /// @param owner the owner of the lending deposit
    /// @param receiver - receiver of funds
    /// @return lendAssets - amount of lend assets received
    /// @return collateralAssets - amount of collateral assets received as replacement of missing lend assets
    function withdrawDepositAndClaimCollateral(MarketId id, address owner, address receiver) external returns (uint256 lendAssets, uint256 collateralAssets);

    /// @notice Initiate a flash loan for a specified collateral token.
    /// @param token The address of the token to be borrowed.
    /// @param assets The amount of the token to borrow.
    /// @param data Arbitrary data passed to the `onDahliaFlashLoan` callback.
    function flashLoan(address token, uint256 assets, bytes calldata data) external;

    /// @notice Initiate a flash loan for a specified lending token within a market.
    /// @param id Market id.
    /// @param assets The amount of the lending token to borrow.
    /// @param data Arbitrary data passed to the `onDahliaFlashLoan` callback.
    /// @dev The market id specifies the token to be borrowed.
    function flashLoan(MarketId id, uint256 assets, bytes calldata data) external;

    /// @notice Accrue interest for market parameters.
    /// @param id Market id.
    function accrueMarketInterest(MarketId id) external;
}
