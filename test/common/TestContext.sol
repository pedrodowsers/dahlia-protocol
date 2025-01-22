// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "@forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { PointsFactory } from "@royco/PointsFactory.sol";
import { Dahlia } from "src/core/contracts/Dahlia.sol";
import { DahliaRegistry, IDahliaRegistry } from "src/core/contracts/DahliaRegistry.sol";
import { Constants } from "src/core/helpers/Constants.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { IDahlia } from "src/core/interfaces/IDahlia.sol";
import { IrmFactory } from "src/irm/contracts/IrmFactory.sol";
import { VariableIrm } from "src/irm/contracts/VariableIrm.sol";
import { IrmConstants } from "src/irm/helpers/IrmConstants.sol";
import { IIrm } from "src/irm/interfaces/IIrm.sol";
import { DahliaChainlinkOracleFactory } from "src/oracles/contracts/DahliaChainlinkOracleFactory.sol";
import { DahliaDualOracleFactory } from "src/oracles/contracts/DahliaDualOracleFactory.sol";
import { DahliaPythOracleFactory } from "src/oracles/contracts/DahliaPythOracleFactory.sol";
import { DahliaUniswapV3OracleFactory } from "src/oracles/contracts/DahliaUniswapV3OracleFactory.sol";
import { Timelock } from "src/oracles/contracts/Timelock.sol";
import { IDahliaOracle } from "src/oracles/interfaces/IDahliaOracle.sol";
import { WrappedVault } from "src/royco/contracts/WrappedVault.sol";
import { WrappedVaultFactory } from "src/royco/contracts/WrappedVaultFactory.sol";
import { BoundUtils } from "test/common/BoundUtils.sol";
import { TestConstants } from "test/common/TestConstants.sol";
import { ERC20Mock, IERC20 } from "test/common/mocks/ERC20Mock.sol";
import { OracleMock } from "test/common/mocks/OracleMock.sol";
import { Mainnet } from "test/oracles/Constants.sol";

interface IERC20Mint is IERC20 {
    function mint(address account, uint256 value) external returns (bool);
}

contract DahliaExt is Dahlia {
    constructor(address _owner, address addressRegistry) Dahlia(_owner, addressRegistry) { }

    function getActualMarketState(IDahlia.MarketId marketId) external view returns (IDahlia.Market memory) {
        return markets[marketId].market;
    }
}

contract TestContext {
    struct MarketContext {
        Dahlia.MarketConfig marketConfig;
        IDahlia.MarketId marketId;
        DahliaExt dahlia;
        IDahliaRegistry dahliaRegistry;
        address alice;
        address bob;
        address carol;
        address maria;
        address protocolFeeRecipient;
        address reserveFeeRecipient;
        address marketAdmin;
        address royco;
        address owner;
        address[] permitted;
        OracleMock oracle;
        VariableIrm irm;
        ERC20Mock loanToken;
        ERC20Mock collateralToken;
        WrappedVault vault;
    }

    Vm public vm;

    mapping(string => address) public wallets;
    mapping(string => address) public contracts;
    mapping(string => uint8) public defaultTokenDecimals;
    address public immutable OWNER;
    address public immutable ALICE;

    constructor(Vm vm_) {
        defaultTokenDecimals["USDC"] = 6;
        defaultTokenDecimals["USDE"] = 18;
        defaultTokenDecimals["WETH"] = 18;
        defaultTokenDecimals["WBTC"] = 8;
        vm = vm_;
        OWNER = createWallet("OWNER");
        ALICE = createWallet("ALICE");
    }

    function bootstrapMarket(string memory loanTokenName, string memory collateralTokenName, uint256 lltv, address owner)
        public
        returns (MarketContext memory)
    {
        Dahlia.MarketConfig memory config = createMarketConfig(loanTokenName, collateralTokenName, lltv);
        config.owner = owner;
        return bootstrapMarket(config);
    }

    function bootstrapMarket(string memory loanTokenName, string memory collateralTokenName, uint256 lltv) public returns (MarketContext memory) {
        return bootstrapMarket(createMarketConfig(loanTokenName, collateralTokenName, lltv));
    }

    function bootstrapMarket(Dahlia.MarketConfig memory marketConfig) public returns (MarketContext memory v) {
        vm.pauseGasMetering();
        v.alice = createWallet("ALICE");
        v.bob = createWallet("BOB");
        v.carol = createWallet("CAROL");
        v.maria = createWallet("MARIA");
        v.owner = createWallet("OWNER");
        v.marketAdmin = createWallet("MARKET_ADMIN");
        v.royco = createWallet("ROYCO");
        v.protocolFeeRecipient = createWallet("PROTOCOL_FEE_RECIPIENT");
        v.reserveFeeRecipient = createWallet("RESERVE_FEE_RECIPIENT");
        v.permitted = new address[](2);
        v.permitted[0] = v.owner;
        v.permitted[1] = v.marketAdmin;
        v.dahlia = createDahlia();
        v.dahliaRegistry = v.dahlia.dahliaRegistry();
        createRoycoWrappedVaultFactory(
            v.dahlia,
            createWallet("ROYCO_OWNER"),
            createWallet("ROYCO_REE_RECIPIENT"),
            TestConstants.ROYCO_ERC4626I_FACTORY_PROTOCOL_FEE,
            TestConstants.ROYCO_ERC4626I_FACTORY_MIN_FRONTEND_FEE
        );

        v.marketConfig = marketConfig;
        v.marketId = deployDahliaMarket(v.marketConfig);
        v.vault = WrappedVault(address(v.dahlia.getMarket(v.marketId).vault));
        vm.label(address(v.vault), "[  VAULT  ]");
        v.oracle = OracleMock(address(marketConfig.oracle));
        v.loanToken = ERC20Mock(marketConfig.loanToken);
        v.collateralToken = ERC20Mock(marketConfig.collateralToken);

        vm.resumeGasMetering();
    }

    function setContractAddress(string memory name, address addr) public {
        contracts[name] = addr;
    }

    function setWalletAddress(string memory name, address addr) public {
        wallets[name] = addr;
    }

    function createERC20Token(string memory name) public virtual returns (ERC20Mock token) {
        return createERC20Token(name, defaultTokenDecimals[name]);
    }

    function createERC20Token(string memory name, uint8 decimals) public virtual returns (ERC20Mock token) {
        if (contracts[name] != address(0)) {
            return ERC20Mock(contracts[name]);
        }
        token = new ERC20Mock(name, name, decimals);
        vm.label(address(token), string.concat("[  ", name, "  ]"));
        contracts[name] = address(token);
    }

    function createWallet(string memory name) public virtual returns (address wallet) {
        if (wallets[name] != address(0)) {
            return wallets[name];
        }
        uint256 privateKey = uint256(bytes32(bytes(name)));
        wallet = vm.addr(privateKey);
        vm.label(wallet, string.concat("[ ", name, " ]"));
        wallets[name] = wallet;
    }

    function mint(string memory tokenName, string memory walletName, uint256 amount) public virtual returns (address wallet) {
        wallet = createWallet(walletName);
        ERC20Mock token = createERC20Token(tokenName);
        vm.prank(wallet);
        token.mint(wallet, amount);
        return wallet;
    }

    function setWalletBalance(string memory tokenName, string memory walletName, uint256 amount) public virtual returns (address wallet) {
        wallet = createWallet(walletName);
        ERC20Mock token = createERC20Token(tokenName);
        ERC20Mock(token).setBalance(wallet, amount);
    }

    function createTestOracle(uint256 price) public virtual returns (IDahliaOracle) {
        OracleMock oracle = new OracleMock();
        oracle.setPrice(price);
        return oracle;
    }

    function createTestIrm() public virtual returns (IIrm irm) {
        if (contracts["Irm"] != address(0)) {
            return IIrm(contracts["Irm"]);
        }
        if (contracts["IrmFactory"] == address(0)) {
            contracts["IrmFactory"] = address(new IrmFactory());
        }
        irm = IIrm(
            IrmFactory(contracts["IrmFactory"]).createVariableIrm(
                VariableIrm.Config({
                    minTargetUtilization: 75 * IrmConstants.UTILIZATION_100_PERCENT / 100,
                    maxTargetUtilization: 85 * IrmConstants.UTILIZATION_100_PERCENT / 100,
                    targetUtilization: 85 * IrmConstants.UTILIZATION_100_PERCENT / 100,
                    minFullUtilizationRate: 1_582_470_460,
                    maxFullUtilizationRate: 3_164_940_920_000,
                    zeroUtilizationRate: 158_247_046,
                    rateHalfLife: 172_800,
                    targetRatePercent: 0.2e18,
                    name: "Variable IRM_20"
                })
            )
        );
        contracts["Irm"] = address(irm);
    }

    function createDahliaRegistry(address owner) public returns (address dahliaRegistry) {
        if (contracts["dahliaRegistry"] != address(0)) {
            return contracts["dahliaRegistry"];
        }
        dahliaRegistry = address(new DahliaRegistry(owner));
        vm.prank(owner);
        DahliaRegistry(dahliaRegistry).allowIrm(IIrm(address(0)));
        vm.label(dahliaRegistry, "[ DAHLIA_REGISTRY ]");
        contracts["dahliaRegistry"] = dahliaRegistry;
    }

    function createDahlia() public returns (DahliaExt dahlia) {
        if (contracts["dahlia"] != address(0)) {
            return DahliaExt(contracts["dahlia"]);
        }
        address owner = createWallet("OWNER");
        address dahliaRegistry = createDahliaRegistry(owner);
        vm.startPrank(owner);

        dahlia = new DahliaExt(owner, dahliaRegistry);
        vm.label(address(dahlia), "[ DAHLIA ]");
        dahlia.setProtocolFeeRecipient(createWallet("PROTOCOL_FEE_RECIPIENT"));

        vm.stopPrank();
        contracts["dahlia"] = address(dahlia);
    }

    function createMarketConfig(string memory loanToken, string memory collateralToken, uint256 lltv) public returns (Dahlia.MarketConfig memory) {
        return createMarketConfig(address(createERC20Token(loanToken)), address(createERC20Token(collateralToken)), lltv);
    }

    function createMarketConfig(address loanToken, address collateralToken, uint256 lltv) public returns (Dahlia.MarketConfig memory marketConfig) {
        address admin = createWallet("MARKET_ADMIN");
        string memory loanTokenSymbol = IERC20Metadata(loanToken).symbol();
        string memory name = string.concat(loanTokenSymbol, "/", IERC20Metadata(collateralToken).symbol(), " (", BoundUtils.toPercentString(lltv), "% LLTV)");
        marketConfig = IDahlia.MarketConfig({
            loanToken: loanToken,
            collateralToken: collateralToken,
            oracle: createTestOracle(Constants.ORACLE_PRICE_SCALE),
            irm: createTestIrm(),
            lltv: lltv,
            liquidationBonusRate: BoundUtils.randomLiquidationBonusRate(vm, lltv),
            name: name,
            owner: admin
        });
    }

    function copyMarketConfig(Dahlia.MarketConfig memory config, uint256 lltv) public returns (Dahlia.MarketConfig memory marketConfig) {
        marketConfig = IDahlia.MarketConfig({
            loanToken: config.loanToken,
            collateralToken: config.collateralToken,
            oracle: config.oracle,
            irm: config.irm,
            name: config.name,
            owner: config.owner,
            lltv: lltv,
            liquidationBonusRate: BoundUtils.randomLiquidationBonusRate(vm, lltv)
        });
    }

    function deployDahliaMarket(Dahlia.MarketConfig memory marketConfig) public returns (IDahlia.MarketId id) {
        Dahlia dahlia = createDahlia();
        vm.startPrank(OWNER);
        if (!dahlia.dahliaRegistry().isIrmAllowed(marketConfig.irm)) {
            dahlia.dahliaRegistry().allowIrm(marketConfig.irm);
        }
        vm.stopPrank();

        vm.prank(createWallet("MARKET_DEPLOYER"));
        id = dahlia.deployMarket(marketConfig);
        vm.prank(OWNER);
        dahlia.setProtocolFeeRate(id, 0); // reset protocol fee rate for testing
    }

    function createRoycoWrappedVaultFactory(Dahlia dahlia, address roycoOwner, address protocolFeeRecipient, uint256 protocolFee, uint256 minimumFrontendFee)
        public
        virtual
        returns (WrappedVaultFactory wrappedVaultFactory)
    {
        address dahliaOwner = createWallet("OWNER");
        address dahliaRegistry = createDahliaRegistry(dahliaOwner);
        // skip if factory already created
        address existed = DahliaRegistry(dahliaRegistry).getAddress(Constants.ADDRESS_ID_ROYCO_WRAPPED_VAULT_FACTORY);
        if (existed != address(0)) {
            return WrappedVaultFactory(existed);
        }

        address pointsFactory = address(new PointsFactory(roycoOwner));
        address wrappedVault = address(new WrappedVault());

        vm.expectEmit(true, true, true, true);
        emit Ownable.OwnershipTransferred(address(0), roycoOwner);

        vm.expectEmit(true, true, true, true);
        emit WrappedVaultFactory.WrappedVaultImplementationUpdated(wrappedVault);

        vm.expectEmit(true, true, true, true);
        emit WrappedVaultFactory.ProtocolFeeUpdated(protocolFee);

        vm.expectEmit(true, true, true, true);
        emit WrappedVaultFactory.ProtocolFeeRecipientUpdated(protocolFeeRecipient);

        vm.expectEmit(true, true, true, true);
        emit WrappedVaultFactory.ReferralFeeUpdated(minimumFrontendFee);

        vm.expectEmit(true, true, true, true);
        emit WrappedVaultFactory.DahliaUpdated(address(dahlia));

        vm.expectEmit(true, true, true, true);
        emit WrappedVaultFactory.PointsFactoryUpdated(pointsFactory);

        wrappedVaultFactory =
            new WrappedVaultFactory(wrappedVault, protocolFeeRecipient, protocolFee, minimumFrontendFee, roycoOwner, pointsFactory, address(dahlia));

        vm.startPrank(dahliaOwner);
        DahliaRegistry(dahliaRegistry).setAddress(Constants.ADDRESS_ID_ROYCO_WRAPPED_VAULT_FACTORY, address(wrappedVaultFactory));
        vm.stopPrank();
    }

    function createTimelock() public returns (address timelock) {
        string memory index = "Timelock";
        if (contracts[index] != address(0)) {
            return contracts[index];
        }
        timelock = address(new Timelock(OWNER, TestConstants.TIMELOCK_DELAY));
        contracts[index] = timelock;
    }

    function createPythOracleFactory() public returns (DahliaPythOracleFactory factory) {
        string memory index = "DahliaPythOracleFactory";
        if (contracts[index] != address(0)) {
            return DahliaPythOracleFactory(contracts[index]);
        }
        address timelock = createTimelock();
        factory = new DahliaPythOracleFactory(timelock, Mainnet.PYTH_STATIC_ORACLE_ADDRESS);
        contracts[index] = address(factory);
    }

    function createUniswapOracleFactory() public returns (DahliaUniswapV3OracleFactory factory) {
        string memory index = "UniswapOracleFactory";
        if (contracts[index] != address(0)) {
            return DahliaUniswapV3OracleFactory(contracts[index]);
        }
        factory = new DahliaUniswapV3OracleFactory(OWNER, Mainnet.UNISWAP_STATIC_ORACLE_ADDRESS);
        contracts[index] = address(factory);
    }

    function createDualOracleFactory() public returns (DahliaDualOracleFactory factory) {
        string memory index = "DualOracleFactory";
        if (contracts[index] != address(0)) {
            return DahliaDualOracleFactory(contracts[index]);
        }
        factory = new DahliaDualOracleFactory();
        contracts[index] = address(factory);
    }

    function createChainlinkOracleFactory() public returns (DahliaChainlinkOracleFactory factory) {
        string memory index = "DahliaChainlinkOracleFactory";
        if (contracts[index] != address(0)) {
            return DahliaChainlinkOracleFactory(contracts[index]);
        }
        factory = new DahliaChainlinkOracleFactory(OWNER);
        contracts[index] = address(factory);
    }
}
