# src

## Folder structure

```text
.
|-- core
|   |-- contracts
|   |   |-- Dahlia.sol
|   |   |   - The main contract of the Dahlia lending protocol
|   |   `-- DahliaRegistry.sol
|   |       - Registry for external addresses and global parameters
|   `-- (Purpose: Core contracts and interfaces for the Dahlia protocol)
|
|-- irm
|   |-- contracts
|   |   |-- IrmFactory.sol
|   |   |   - Factory contract used to create interest rate model (IRM) instances
|   |   `-- VariableIrm.sol
|   |       - Variable IRM contract used to compute and update interest rates
|   `-- (Purpose: Contracts related to the Interest Rate Model (IRM))
|
|-- oracles
|   |-- contracts
|   |   |-- ChainlinkWstETHToETH.sol
|   |   |   - Provides Chainlink compatible WSTETH-to-ETH price feed using Lido's WSTETH-STETH conversion rate and Chainlink STETH-to-ETH price feed
|   |   |-- DahliaChainlinkOracle.sol
|   |   |   - Dahlia Oracle leveraging Chainlink price feeds
|   |   |-- DahliaChainlinkOracleFactory.sol
|   |   |   - Factory to create and configure DahliaChainlinkOracle contracts
|   |   |-- DahliaDualOracle.sol
|   |   |   - Dahlia Oracle using multiple (dual) underlying Dahlia oracle sources
|   |   |-- DahliaDualOracleFactory.sol
|   |   |   - Factory to create and configure DahliaDualOracle contracts
|   |   |-- DahliaPythOracle.sol
|   |   |   - Dahlia Oracle leveraging Pyth price feeds
|   |   |-- DahliaPythOracleFactory.sol
|   |   |   - Factory to create and configure DahliaPythOracle contracts
|   |   |-- DahliaUniswapV3Oracle.sol
|   |   |   - Dahlia Oracle using Uniswap V3 price data
|   |   |-- DahliaUniswapV3OracleFactory.sol
|   |   |   - Factory to create and configure DahliaUniswapV3Oracle contracts
|   |   `-- Timelock.sol
|   |       - Timelock mechanism for delay parameter updates in oracles
|   `-- (Purpose: Contracts for interacting with external data feeds and price oracles)
|
`-- royco
    |-- contracts
    |   |-- WrappedVault.sol
    |   |   - Copied from `@royco/WrappedVault.sol` with Dahlia lending support
    |   `-- WrappedVaultFactory.sol
    |       - Copied from `@royco/WrappedVaultFactory.sol` and modified for Dahlia lending support
    |-- interfaces
    |   `-- IDahliaWrappedVault.sol
    |       - Copied from `@royco/interfaces/IWrappedVault.sol` and extended
    |-- periphery
    |   `-- InitializableERC20.sol
    |       - Copied from `@royco/periphery/InitializableERC20.sol`
    `-- (Purpose: Royco contracts adapted for supporting Dahlia lending protocol)
```

## Design Highlights

The Dahlia protocol is designed to extend the functionality of the Royco protocol by enhancing lending rewards and seamlessly integrating them into Royco rewards.

### WrappedVault.sol

To achieve this, we adapted three key contracts from ROYCO, improving the logic of the WrappedVault. Key enhancements include:

- Preserved ABI Compatibility: The contract maintains 100% ABI compatibility with the original Royco `WrappedVault` contracts.
- Controlled Asset Management: The `Dahlia` contract has full control over the assets in the `WrappedVault`, ensuring strict security by preventing unauthorized withdrawals to arbitrary addresses.
- Connection to Dahlia Market: The `WrappedVault` integrates with the Dahlia market by passing the `Dahlia` contract address and a market ID.
- Enhanced Functions:
  - `rewardsToInterval`: Extended to include accrued lending interest as additional Royco rewards.
  - `previewRateAfterDeposit`: Calculates the impact of lending interest within Dahlia and integrates it into reward computations.
  - `balanceOf`: Retrieves issued shares directly from Dahlia, eliminating the need for `WrappedVault` to track them.
  - `principal`: Accurately accounts for deposited assets to ensure rewards are distributed only to users providing liquidity through Royco.

The modified WrappedVault adheres to the ERC-4626 standard, maintaining compatibility while incorporating these improvements.

### WrappedVaultFactory.sol

The `wrapVault()` function can only be invoked by `Dahlia.sol`, diverging from Royco's implementation.

### IDahliaWrappedVault.sol

Extends `IWrappedVault.sol` to add access to additional functions.

### Dahlia.sol

The Dahlia contract introduces several new features and capabilities:

- Market Creation: New markets can only be created by the `Dahlia.sol` contract, accessible by any user.
- Market Configuration: Each market has its own IRM, oracle, borrowing/lending tokens, and LLTV parameters (see `MarketConfig` struct).
- Restricted Functionality:
- `lend()` and `withdraw()` can only be invoked through the `WrappedVault`.
- Collateral can be supplied by any user, including non-Royco users, who can borrow lending tokens from Royco lenders.

Administrative Controls:

- Pause Market: Dahlia DAO (Guardian Multisig) and market admins can pause a market, restricting new deposits and borrows. Users can only repay loans and withdraw collateral or lending tokens.
- Deprecate Market: Only Dahlia DAO (Guardian Multisig) can mark a market as deprecated. This state is similar to a pause but is irreversible.
- Stall Market: Dahlia DAO (Guardian Multisig) can mark a market as stalled in case of critical issues (e.g., oracle failure). In this mode:
  - Borrowers can repay loans and withdraw collateral during a fixed period (VALUE_ID_REPAY_PERIOD, default is 2 weeks).
  - Lenders must wait until the end of the repayment period to withdraw their portion of lending and collateral assets if lending assets are insufficient.

### VariableIrm.sol

- Provides mathematical calculations for determining interest rates based on total lending and borrowing activity.
