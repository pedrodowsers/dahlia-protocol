// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { Permitted } from "src/core/abstracts/Permitted.sol";
import { Constants } from "src/core/helpers/Constants.sol";
import { Errors } from "src/core/helpers/Errors.sol";
import { MarketMath } from "src/core/helpers/MarketMath.sol";
import { SharesMathLib } from "src/core/helpers/SharesMathLib.sol";
import { BorrowImpl } from "src/core/impl/BorrowImpl.sol";
import { InterestImpl } from "src/core/impl/InterestImpl.sol";
import { LendImpl } from "src/core/impl/LendImpl.sol";
import { LiquidationImpl } from "src/core/impl/LiquidationImpl.sol";
import { ManageMarketImpl } from "src/core/impl/ManageMarketImpl.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import {
    IDahliaFlashLoanCallback, IDahliaLiquidateCallback, IDahliaRepayCallback, IDahliaSupplyCollateralCallback
} from "src/core/interfaces/IDahliaCallbacks.sol";
import { IDahliaRegistry } from "src/core/interfaces/IDahliaRegistry.sol";
import { IIrm } from "src/irm/interfaces/IIrm.sol";
import { WrappedVaultFactory } from "src/royco/contracts/WrappedVaultFactory.sol";
import { IDahliaWrappedVault } from "src/royco/interfaces/IDahliaWrappedVault.sol";

/// @title Dahlia
/// @notice The Dahlia contract.
contract Dahlia is Permitted, Ownable2Step, IDahlia, ReentrancyGuard {
    using SafeTransferLib for address;
    using SharesMathLib for *;
    using SafeCastLib for uint256;
    using FixedPointMathLib for uint256;

    uint32 internal marketSequence; // 4 bytes
    IDahliaRegistry public dahliaRegistry; // 20 bytes
    RateRange public lltvRange; // 6 bytes
    RateRange public liquidationBonusRateRange; // 6 bytes

    address public protocolFeeRecipient; // 20 bytes
    address public reserveFeeRecipient; // 20 bytes
    uint24 public flashLoanFeeRate; // 3 bytes
    mapping(MarketId => MarketData) internal markets;

    /// @dev The owner is used by the governance controller to manage the execution of each `onlyOwner` function.
    constructor(address _owner, address addressRegistry) Ownable(_owner) {
        require(addressRegistry != address(0), Errors.ZeroAddress());
        dahliaRegistry = IDahliaRegistry(addressRegistry);
        emit SetDahliaRegistry(addressRegistry);

        _setProtocolFeeRecipient(_owner);
        _setLltvRange(RateRange(Constants.DEFAULT_MIN_LLTV, Constants.DEFAULT_MAX_LLTV));
        _setLiquidationBonusRateRange(RateRange(Constants.DEFAULT_MIN_LIQUIDATION_BONUS_RATE, Constants.DEFAULT_MAX_LIQUIDATION_BONUS_RATE));
    }

    function _setLltvRange(RateRange memory range) internal {
        lltvRange = range;
        emit SetLLTVRange(range.min, range.max);
    }

    /// @inheritdoc IDahlia
    function setLltvRange(RateRange memory range) external onlyOwner {
        // The percentage must always be between 0 and 100%, and min LTV should be <= max LTV.
        require(range.min > 0 && range.max < Constants.LLTV_100_PERCENT && range.min <= range.max, Errors.RangeNotValid(range.min, range.max));
        _setLltvRange(range);
    }

    function _setLiquidationBonusRateRange(RateRange memory range) internal {
        liquidationBonusRateRange = range;
        emit SetLiquidationBonusRateRange(range.min, range.max);
    }

    /// @inheritdoc IDahlia
    function setLiquidationBonusRateRange(RateRange memory range) external onlyOwner {
        require(
            range.min >= Constants.DEFAULT_MIN_LIQUIDATION_BONUS_RATE && range.max <= Constants.DEFAULT_MAX_LIQUIDATION_BONUS_RATE && range.min <= range.max,
            Errors.RangeNotValid(range.min, range.max)
        );
        _setLiquidationBonusRateRange(range);
    }

    /// @inheritdoc IDahlia
    function setProtocolFeeRate(MarketId id, uint32 newFeeRate) external onlyOwner {
        MarketData storage marketData = markets[id];
        Market storage market = marketData.market;
        _validateMarketIsActive(market.status);
        require(newFeeRate != market.protocolFeeRate, Errors.AlreadySet());

        _accrueMarketInterest(id, marketData.userPositions, market);

        ManageMarketImpl.setProtocolFeeRate(id, market, newFeeRate);
    }

    /// @inheritdoc IDahlia
    function setReserveFeeRate(MarketId id, uint32 newFeeRate) external onlyOwner {
        require(reserveFeeRecipient != address(0), Errors.ZeroAddress());
        MarketData storage marketData = markets[id];
        Market storage market = marketData.market;
        _validateMarketIsActive(market.status);
        _accrueMarketInterest(id, marketData.userPositions, market);

        ManageMarketImpl.setReserveFeeRate(id, market, newFeeRate);
    }

    function _setProtocolFeeRecipient(address newProtocolFeeRecipient) internal {
        protocolFeeRecipient = newProtocolFeeRecipient;
        emit SetProtocolFeeRecipient(newProtocolFeeRecipient);
    }

    /// @inheritdoc IDahlia
    function setProtocolFeeRecipient(address newProtocolFeeRecipient) external onlyOwner {
        require(newProtocolFeeRecipient != address(0), Errors.ZeroAddress());
        require(newProtocolFeeRecipient != protocolFeeRecipient, Errors.AlreadySet());
        _setProtocolFeeRecipient(newProtocolFeeRecipient);
    }

    /// @inheritdoc IDahlia
    function setReserveFeeRecipient(address newReserveFeeRecipient) external onlyOwner {
        require(newReserveFeeRecipient != address(0), Errors.ZeroAddress());
        require(newReserveFeeRecipient != reserveFeeRecipient, Errors.AlreadySet());
        reserveFeeRecipient = newReserveFeeRecipient;
        emit SetReserveFeeRecipient(newReserveFeeRecipient);
    }

    /// @inheritdoc IDahlia
    function setFlashLoanFeeRate(uint24 newFlashLoanFeeRate) external onlyOwner {
        require(newFlashLoanFeeRate <= Constants.MAX_FLASH_LOAN_FEE_RATE, Errors.MaxFeeExceeded());
        flashLoanFeeRate = newFlashLoanFeeRate;
        emit SetFlashLoanFeeRate(newFlashLoanFeeRate);
    }

    /// @notice Validates the liquidation bonus rate, ensuring it is within acceptable limits based on the market's LLTV.
    /// @param liquidationBonusRate The liquidation bonus rate to validate.
    /// @param lltv Liquidation loan-to-value for the market.
    function _validateLiquidationBonusRate(uint256 liquidationBonusRate, uint256 lltv) internal view {
        require(
            liquidationBonusRate >= liquidationBonusRateRange.min && liquidationBonusRate <= liquidationBonusRateRange.max
                && liquidationBonusRate <= MarketMath.getMaxLiquidationBonusRate(lltv),
            Errors.LiquidationBonusRateNotAllowed()
        );
    }

    /// @inheritdoc IDahlia
    function deployMarket(MarketConfig memory marketConfig) external returns (MarketId id) {
        require(dahliaRegistry.isIrmAllowed(marketConfig.irm), Errors.IrmNotAllowed());
        require(marketConfig.lltv >= lltvRange.min && marketConfig.lltv <= lltvRange.max, Errors.LltvNotAllowed());
        MarketMath.getCollateralPrice(marketConfig.oracle); // validate oracle
        _validateLiquidationBonusRate(marketConfig.liquidationBonusRate, marketConfig.lltv);

        id = MarketId.wrap(marketSequence);

        uint256 fee = dahliaRegistry.getValue(Constants.VALUE_ID_ROYCO_WRAPPED_VAULT_MIN_INITIAL_FRONTEND_FEE);
        uint256 dahliaFee = dahliaRegistry.getValue(Constants.VALUE_ID_DAHLIA_MARKET_INITIAL_PROTOCOL_FEE);
        address owner = marketConfig.owner == address(0) ? msg.sender : marketConfig.owner;
        IDahliaWrappedVault wrappedVault = WrappedVaultFactory(dahliaRegistry.getAddress(Constants.ADDRESS_ID_ROYCO_WRAPPED_VAULT_FACTORY)).wrapVault(
            id, marketConfig.loanToken, owner, marketConfig.name, fee
        );
        ManageMarketImpl.deployMarket(markets, id, marketConfig, wrappedVault, dahliaFee);
        marketSequence++;
    }

    /// @inheritdoc IDahlia
    function lend(MarketId id, uint256 assets, uint256 shares, address owner) external returns (uint256, uint256) {
        require(owner != address(0), Errors.ZeroAddress());
        MarketData storage marketData = markets[id];
        Market storage market = marketData.market;
        IDahliaWrappedVault vault = market.vault;
        _permittedByWrappedVault(vault);
        _validateMarketIsActive(market.status);
        mapping(address => UserPosition) storage positions = marketData.userPositions;
        _accrueMarketInterest(id, positions, market);

        return LendImpl.internalLend(id, market, positions[owner], assets, shares, owner);
    }

    /// @inheritdoc IDahlia
    function withdraw(MarketId id, uint256 assets, uint256 shares, address receiver, address owner) external nonReentrant returns (uint256, uint256) {
        require(receiver != address(0), Errors.ZeroAddress());
        MarketData storage marketData = markets[id];
        Market storage market = marketData.market;
        IDahliaWrappedVault vault = market.vault;
        _permittedByWrappedVault(vault);
        _validateMarketIsActiveOrPausedOrDeprecated(market.status);
        mapping(address => UserPosition) storage positions = marketData.userPositions;
        _accrueMarketInterest(id, positions, market);
        UserPosition storage ownerPosition = positions[owner];

        (uint256 _assets, uint256 _shares, uint256 ownerLendShares) = LendImpl.internalWithdraw(id, market, ownerPosition, assets, shares, owner, receiver);

        // User lend assets should be 0 if no shares are left (rounding issue)
        uint256 userLendAssets = ownerPosition.lendPrincipalAssets;
        if (ownerLendShares == 0) {
            ownerPosition.lendPrincipalAssets = 0;
            market.totalLendPrincipalAssets -= userLendAssets;
        } else {
            uint256 userLendAssetsDown = FixedPointMathLib.min(_assets, userLendAssets);
            ownerPosition.lendPrincipalAssets = (userLendAssets - userLendAssetsDown).toUint128();
            market.totalLendPrincipalAssets -= userLendAssetsDown;
        }

        return (_assets, _shares);
    }

    function transferLendShares(MarketId id, address owner, address receiver, uint256 shares) public returns (bool) {
        require(receiver != address(0), Errors.ZeroAddress());
        MarketData storage marketData = markets[id];
        Market storage market = marketData.market;
        IDahliaWrappedVault vault = market.vault;
        _permittedByWrappedVault(vault);
        mapping(address => UserPosition) storage positions = marketData.userPositions;
        UserPosition storage ownerPosition = positions[owner];
        UserPosition storage receiverPosition = positions[receiver];
        uint256 assets = shares.toAssetsDown(market.totalLendAssets, market.totalLendShares);
        uint256 newOwnerLendShares = ownerPosition.lendShares - shares;

        uint256 ownerLendPrincipalAssets = ownerPosition.lendPrincipalAssets;
        if (newOwnerLendShares == 0) {
            receiverPosition.lendPrincipalAssets += ownerLendPrincipalAssets.toUint128(); // Transfer all if no shares left
            ownerPosition.lendPrincipalAssets = 0;
        } else {
            uint256 ownerLendPrincipalAssetsDown = FixedPointMathLib.min(assets, ownerLendPrincipalAssets);
            ownerPosition.lendPrincipalAssets = (ownerLendPrincipalAssets - ownerLendPrincipalAssetsDown).toUint128();
            receiverPosition.lendPrincipalAssets += ownerLendPrincipalAssetsDown.toUint128();
        }
        ownerPosition.lendShares = newOwnerLendShares.toUint128();
        receiverPosition.lendShares += shares.toUint128();

        return true;
    }

    /// @param id The market id.
    /// @param lendAssets The amount of assets to deposit into the market.
    /// @return rate The expected rate after depositing `lendAssets` into the market.
    function previewLendRateAfterDeposit(MarketId id, uint256 lendAssets) external view returns (uint256 rate) {
        Market memory market = InterestImpl.getLatestMarketState(markets[id].market);
        if (lendAssets > 0) {
            market.totalLendAssets += lendAssets;
            (, uint256 newRatePerSec,) = IIrm(market.irm).calculateInterest(0, market.totalLendAssets, market.totalBorrowAssets, market.fullUtilizationRate);
            market.ratePerSec = newRatePerSec.toUint64();
        }
        return (market.totalLendAssets != 0) ? market.totalBorrowAssets.mulDiv(market.ratePerSec, market.totalLendAssets) : 0;
    }

    /// @inheritdoc IDahlia
    function borrow(MarketId id, uint256 assets, address owner, address receiver) external isSenderPermitted(owner) returns (uint256 borrowShares) {
        require(receiver != address(0), Errors.ZeroAddress());
        MarketData storage marketData = markets[id];
        Market storage market = marketData.market;
        _validateMarketIsActive(market.status);
        mapping(address => UserPosition) storage positions = marketData.userPositions;
        _accrueMarketInterest(id, positions, market);

        borrowShares = BorrowImpl.internalBorrow(id, market, positions[owner], assets, owner, receiver);

        market.loanToken.safeTransferFrom(address(market.vault), receiver, assets);
    }

    // @inheritdoc IDahlia
    function supplyAndBorrow(MarketId id, uint256 collateralAssets, uint256 borrowAssets, address owner, address receiver)
        external
        isSenderPermitted(owner)
        returns (uint256 borrowedShares)
    {
        require(collateralAssets > 0 && borrowAssets > 0, Errors.ZeroAssets());
        require(receiver != address(0), Errors.ZeroAddress());
        MarketData storage marketData = markets[id];
        Market storage market = marketData.market;
        _validateMarketIsActive(market.status);
        mapping(address => UserPosition) storage positions = marketData.userPositions;
        _accrueMarketInterest(id, positions, market);
        UserPosition storage ownerPosition = positions[owner];
        BorrowImpl.internalSupplyCollateral(id, market, ownerPosition, collateralAssets, owner);

        borrowedShares = BorrowImpl.internalBorrow(id, market, ownerPosition, borrowAssets, owner, receiver);

        market.collateralToken.safeTransferFrom(owner, address(this), collateralAssets);
        market.loanToken.safeTransferFrom(address(market.vault), receiver, borrowAssets);
    }

    // @inheritdoc IDahlia
    function repayAndWithdraw(MarketId id, uint256 collateralAssets, uint256 repayAssets, uint256 repayShares, address owner, address receiver)
        external
        nonReentrant
        isSenderPermitted(owner)
        returns (uint256 repaidAssets, uint256 repaidShares)
    {
        require(collateralAssets > 0, Errors.ZeroAssets());
        require(receiver != address(0), Errors.ZeroAddress());
        MarketData storage marketData = markets[id];
        Market storage market = marketData.market;
        _validateMarketIsActiveOrPausedOrDeprecatedOrStalledPeriod(market);
        mapping(address => UserPosition) storage positions = marketData.userPositions;
        _accrueMarketInterest(id, positions, market);
        UserPosition storage ownerPosition = positions[owner];
        (repaidAssets, repaidShares) = BorrowImpl.internalRepay(id, market, ownerPosition, repayAssets, repayShares, owner);
        market.loanToken.safeTransferFrom(owner, address(market.vault), repaidAssets);

        BorrowImpl.internalWithdrawCollateral(id, market, ownerPosition, collateralAssets, owner, receiver);
        market.collateralToken.safeTransfer(receiver, collateralAssets);
    }

    /// @inheritdoc IDahlia
    function repay(MarketId id, uint256 assets, uint256 shares, address owner, bytes calldata callbackData) external returns (uint256, uint256) {
        require(owner != address(0), Errors.ZeroAddress());
        MarketData storage marketData = markets[id];
        Market storage market = marketData.market;
        _validateMarketIsActiveOrPausedOrDeprecatedOrStalledPeriod(market);
        mapping(address => UserPosition) storage positions = marketData.userPositions;
        _accrueMarketInterest(id, positions, market);

        (assets, shares) = BorrowImpl.internalRepay(id, market, positions[owner], assets, shares, owner);
        if (callbackData.length > 0 && address(msg.sender).code.length > 0) {
            IDahliaRepayCallback(msg.sender).onDahliaRepay(assets, callbackData);
        }

        market.loanToken.safeTransferFrom(msg.sender, address(market.vault), assets);
        return (assets, shares);
    }

    /// @inheritdoc IDahlia
    function liquidate(MarketId id, address borrower, bytes calldata callbackData)
        external
        returns (uint256 repaidAssets, uint256 repaidShares, uint256 seizedCollateral)
    {
        require(borrower != address(0), Errors.ZeroAddress());
        MarketData storage marketData = markets[id];
        Market storage market = marketData.market;
        _validateMarketIsActiveOrPausedOrDeprecated(market.status);
        mapping(address => UserPosition) storage positions = marketData.userPositions;
        _accrueMarketInterest(id, positions, market);

        (repaidAssets, repaidShares, seizedCollateral) =
            LiquidationImpl.internalLiquidate(id, market, positions[borrower], positions[reserveFeeRecipient], borrower);

        // Transfer seized collateral from Dahlia to the liquidator's wallet.
        market.collateralToken.safeTransfer(msg.sender, seizedCollateral);

        // This callback allows a smart contract to receive the repaid amount before approving in collateral token.
        if (callbackData.length > 0 && address(msg.sender).code.length > 0) {
            IDahliaLiquidateCallback(msg.sender).onDahliaLiquidate(repaidAssets, callbackData);
        }

        // Transfer repaid assets from the liquidator's wallet to Dahlia.
        market.loanToken.safeTransferFrom(msg.sender, address(market.vault), repaidAssets);
    }

    /// @inheritdoc IDahlia
    function supplyCollateral(MarketId id, uint256 assets, address owner, bytes calldata callbackData) external {
        require(assets > 0, Errors.ZeroAssets());
        require(owner != address(0), Errors.ZeroAddress());
        MarketData storage marketData = markets[id];
        Market storage market = marketData.market;
        _validateMarketIsActive(market.status);
        /// @dev accrueInterest is not needed here.

        BorrowImpl.internalSupplyCollateral(id, market, marketData.userPositions[owner], assets, owner);

        if (callbackData.length > 0 && address(msg.sender).code.length > 0) {
            IDahliaSupplyCollateralCallback(msg.sender).onDahliaSupplyCollateral(assets, callbackData);
        }

        market.collateralToken.safeTransferFrom(msg.sender, address(this), assets);
    }

    /// @inheritdoc IDahlia
    function withdrawCollateral(MarketId id, uint256 assets, address owner, address receiver) external isSenderPermitted(owner) {
        require(assets > 0, Errors.ZeroAssets());
        require(receiver != address(0), Errors.ZeroAddress());

        MarketData storage marketData = markets[id];
        Market storage market = marketData.market;
        _validateMarketIsActiveOrPausedOrDeprecatedOrStalledPeriod(market);
        mapping(address => UserPosition) storage positions = marketData.userPositions;
        _accrueMarketInterest(id, positions, market);

        BorrowImpl.internalWithdrawCollateral(id, market, positions[owner], assets, owner, receiver);

        market.collateralToken.safeTransfer(receiver, assets);
    }

    /// @inheritdoc IDahlia
    function withdrawDepositAndClaimCollateral(MarketId id, address owner, address receiver)
        external
        isSenderPermitted(owner)
        nonReentrant
        returns (uint256 lendAssets, uint256 collateralAssets)
    {
        require(receiver != address(0), Errors.ZeroAddress());
        MarketData storage marketData = markets[id];
        Market storage market = markets[id].market;
        MarketStatus status = market.status;
        require(status == MarketStatus.Stalled, Errors.WrongStatus(status));
        require(block.timestamp >= market.repayPeriodEndTimestamp, Errors.RepayPeriodNotEnded());

        mapping(address => UserPosition) storage positions = marketData.userPositions;
        UserPosition storage ownerPosition = positions[owner];

        (lendAssets, collateralAssets) = LendImpl.internalWithdrawDepositAndClaimCollateral(id, market, ownerPosition, owner, receiver);

        market.loanToken.safeTransferFrom(address(market.vault), receiver, lendAssets);
        market.collateralToken.safeTransfer(receiver, collateralAssets);
    }

    function _flashLoan(address location, address token, uint256 assets, bytes calldata callbackData) internal {
        uint256 fee = MarketMath.mulPercentUp(assets, flashLoanFeeRate);

        IDahliaFlashLoanCallback(msg.sender).onDahliaFlashLoan(assets, fee, callbackData);

        token.safeTransferFrom(msg.sender, location, assets);
        if (fee > 0) {
            token.safeTransferFrom(msg.sender, protocolFeeRecipient, fee);
        }

        emit FlashLoan(msg.sender, token, assets, fee);
    }

    /// @inheritdoc IDahlia
    function flashLoan(MarketId id, uint256 assets, bytes calldata callbackData) external {
        require(assets != 0, Errors.ZeroAssets());
        Market storage market = markets[id].market;
        _validateMarketIsActive(market.status);
        address token = market.loanToken;
        address vault = address(market.vault);
        token.safeTransferFrom(vault, msg.sender, assets);
        _flashLoan(vault, token, assets, callbackData);
    }

    /// @inheritdoc IDahlia
    function flashLoan(address token, uint256 assets, bytes calldata callbackData) external {
        require(assets != 0, Errors.ZeroAssets());
        token.safeTransfer(msg.sender, assets);
        _flashLoan(address(this), token, assets, callbackData);
    }

    /// @inheritdoc IDahlia
    function accrueMarketInterest(MarketId id) external {
        MarketData storage marketData = markets[id];
        Market storage market = marketData.market;
        _validateMarketIsActive(market.status);
        _accrueMarketInterest(id, marketData.userPositions, market);
    }

    function _accrueMarketInterest(MarketId id, mapping(address => UserPosition) storage positions, Market storage market) private {
        InterestImpl.executeMarketAccrueInterest(id, market, positions, protocolFeeRecipient, reserveFeeRecipient);
    }

    /// @notice Checks if the sender is the market or the wrapped vault owner.
    /// @param vault The wrapped vault associated with the market.
    function _checkDahliaOwnerOrVaultOwner(IDahliaWrappedVault vault) internal view {
        address sender = _msgSender();
        require(sender == owner() || sender == vault.owner(), Errors.NotPermitted(sender));
    }

    /// @inheritdoc IDahlia
    function getMarket(MarketId id) external view returns (Market memory) {
        return InterestImpl.getLatestMarketState(markets[id].market);
    }

    /// @inheritdoc IDahlia
    function getPosition(MarketId id, address userAddress) external view returns (UserPosition memory) {
        return markets[id].userPositions[userAddress];
    }

    /// @inheritdoc IDahlia
    function getMaxBorrowableAmount(MarketId id, address userAddress, uint256 additionalCollateral)
        external
        view
        returns (uint256 borrowedAssets, uint256 borrowableAssets, uint256 collateralPrice)
    {
        MarketData storage marketData = markets[id];
        Market memory market = InterestImpl.getLatestMarketState(marketData.market);
        collateralPrice = MarketMath.getCollateralPrice(market.oracle);
        UserPosition memory position = marketData.userPositions[userAddress];
        borrowedAssets = position.borrowShares.toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);
        uint256 positionCapacity = MarketMath.calcMaxBorrowAssets(collateralPrice, position.collateral + additionalCollateral, market.lltv);
        uint256 leftToBorrow = positionCapacity > borrowedAssets ? positionCapacity - borrowedAssets : 0;
        uint256 availableLendAssets = market.totalLendAssets - market.totalBorrowAssets;
        borrowableAssets = availableLendAssets.min(leftToBorrow);
    }

    /// @inheritdoc IDahlia
    function getPositionLTV(MarketId id, address userAddress) external view returns (uint256 ltv) {
        MarketData storage marketData = markets[id];
        Market memory market = InterestImpl.getLatestMarketState(marketData.market);
        uint256 collateralPrice = MarketMath.getCollateralPrice(market.oracle);
        UserPosition storage position = marketData.userPositions[userAddress];
        uint256 borrowedAssets = position.borrowShares.toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);
        return MarketMath.getLTV(borrowedAssets, position.collateral, collateralPrice);
    }

    /// @inheritdoc IDahlia
    function getPositionInterest(MarketId id, address userAddress) external view returns (uint256 assets, uint256 shares) {
        MarketData storage marketData = markets[id];
        UserPosition memory position = marketData.userPositions[userAddress];
        Market memory state = InterestImpl.getLatestMarketState(marketData.market);
        uint256 lendShares = position.lendPrincipalAssets.toSharesDown(state.totalLendAssets, state.totalLendShares);
        shares = position.lendShares - lendShares;
        assets = shares.toAssetsDown(state.totalLendAssets, state.totalLendShares);
    }

    /// @inheritdoc IDahlia
    function isMarketDeployed(MarketId id) external view returns (bool) {
        return markets[id].market.status != MarketStatus.Uninitialized;
    }

    function _setStatus(Market storage market, MarketId id, MarketStatus oldStatus, MarketStatus newStatus) internal {
        market.status = newStatus;
        emit MarketStatusChanged(id, oldStatus, newStatus);
    }

    /// @inheritdoc IDahlia
    function pauseMarket(MarketId id) external {
        Market storage market = markets[id].market;
        _checkDahliaOwnerOrVaultOwner(market.vault);
        MarketStatus status = market.status;
        _validateMarketIsActive(status);
        _setStatus(market, id, status, MarketStatus.Paused);
    }

    /// @inheritdoc IDahlia
    function unpauseMarket(MarketId id) external {
        Market storage market = markets[id].market;
        _checkDahliaOwnerOrVaultOwner(market.vault);
        MarketStatus status = market.status;
        require(status == MarketStatus.Paused, Errors.WrongStatus(status));
        _setStatus(market, id, status, MarketStatus.Active);
    }

    function staleMarket(MarketId id) external onlyOwner {
        Market storage market = markets[id].market;
        MarketStatus status = market.status;
        _validateMarketIsActiveOrPaused(status);
        // Check if the price is stalled
        try market.oracle.getPrice() returns (uint256 price, bool isBadData) {
            require(isBadData || price == 0, Errors.OraclePriceNotStalled());
        } catch {
            // Do nothing if the price is not available to allow stale the market
        }
        market.repayPeriodEndTimestamp = uint48(block.timestamp + dahliaRegistry.getValue(Constants.VALUE_ID_REPAY_PERIOD));
        _setStatus(market, id, status, MarketStatus.Stalled);
    }

    /// @inheritdoc IDahlia
    function deprecateMarket(MarketId id) external onlyOwner {
        Market storage market = markets[id].market;
        MarketStatus status = market.status;
        _validateMarketIsActiveOrPaused(status);
        _setStatus(market, id, status, MarketStatus.Deprecated);
    }

    /// @inheritdoc IDahlia
    function updateLiquidationBonusRate(MarketId id, uint256 liquidationBonusRate) external {
        Market storage market = markets[id].market;
        _checkDahliaOwnerOrVaultOwner(market.vault);
        _validateLiquidationBonusRate(liquidationBonusRate, market.lltv);
        emit LiquidationBonusRateChanged(id, liquidationBonusRate);
        market.liquidationBonusRate = liquidationBonusRate.toUint24();
    }

    /// @notice Validates the current market status is Active Or Paused Or Deprecated Or Stalled and the repay period has not ended.
    /// @param market The current market.
    function _validateMarketIsActiveOrPausedOrDeprecatedOrStalledPeriod(Market storage market) internal view {
        MarketStatus status = market.status;
        if (status == MarketStatus.Stalled) {
            require(block.timestamp < market.repayPeriodEndTimestamp, Errors.RepayPeriodEnded());
        } else {
            _validateMarketIsActiveOrPausedOrDeprecated(status);
        }
    }

    /// @notice Validates the current market status is Active Or Paused.
    /// @param status The current market status.
    function _validateMarketIsActiveOrPaused(MarketStatus status) internal pure {
        require(status == MarketStatus.Active || status == MarketStatus.Paused, Errors.WrongStatus(status));
    }

    /// @notice Validates the current market status is Active Or Paused Or Deprecated.
    /// @param status The current market status.
    function _validateMarketIsActiveOrPausedOrDeprecated(MarketStatus status) internal pure {
        require(status == MarketStatus.Active || status == MarketStatus.Paused || status == MarketStatus.Deprecated, Errors.WrongStatus(status));
    }

    /// @notice Validates the current market status is active.
    /// @param status The current market status.
    function _validateMarketIsActive(MarketStatus status) internal pure {
        require(status == MarketStatus.Active, Errors.WrongStatus(status));
    }

    /// @notice Validates if the current sender is the WrappedVault contract.
    /// @param vault WrappedVault contract address
    function _permittedByWrappedVault(IDahliaWrappedVault vault) internal view {
        require(msg.sender == address(vault), Errors.NotPermitted(msg.sender));
    }
}
