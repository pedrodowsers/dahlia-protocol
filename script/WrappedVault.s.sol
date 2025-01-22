// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { BaseScript } from "./BaseScript.sol";
import { console } from "@forge-std/console.sol";
import { Dahlia } from "src/core/contracts/Dahlia.sol";
import { DahliaRegistry } from "src/core/contracts/DahliaRegistry.sol";
import { Constants } from "src/core/helpers/Constants.sol";
import { IDahlia, IDahliaOracle, IIrm } from "src/core/interfaces/IDahlia.sol";

contract WrappedVaultScript is BaseScript {
    function run() public {
        Dahlia dahlia = Dahlia(_envAddress(DEPLOYED_DAHLIA));
        IIrm irm = IIrm(_envAddress("MARKET_IRM"));
        Dahlia.MarketConfig memory config = IDahlia.MarketConfig({
            loanToken: _envAddress("MARKET_LOAN"),
            collateralToken: _envAddress("MARKET_COLLATERAL"),
            oracle: IDahliaOracle(_envAddress("MARKET_ORACLE")),
            irm: irm,
            lltv: _envUint("MARKET_LLTV"),
            liquidationBonusRate: _envUint("MARKET_LIQUIDATION_BONUS_RATE"),
            name: _envString("MARKET_NAME"),
            owner: _envAddress(DAHLIA_OWNER)
        });
        DahliaRegistry registry = DahliaRegistry(_envAddress(DEPLOYED_REGISTRY));
        string memory INDEX = _envString(INDEX);

        string memory contractName = string(abi.encodePacked("DEPLOYED_MARKET_", INDEX));
        address marketAddress = _envOr(contractName, address(0));
        if (marketAddress.code.length == 0 && marketAddress == address(0)) {
            vm.startBroadcast(deployer);
            if (registry.getAddress(Constants.ADDRESS_ID_ROYCO_WRAPPED_VAULT_FACTORY) == address(0)) {
                address factory = _envAddress(DEPLOYED_WRAPPED_VAULT_FACTORY);
                console.log("Set ADDRESS_ID_ROYCO_WRAPPED_VAULT_FACTORY in registry", factory);
                registry.setAddress(Constants.ADDRESS_ID_ROYCO_WRAPPED_VAULT_FACTORY, factory);
            }
            if (!dahlia.dahliaRegistry().isIrmAllowed(irm)) {
                dahlia.dahliaRegistry().allowIrm(irm);
            }
            IDahlia.MarketId id = dahlia.deployMarket(config);
            IDahlia.Market memory market = dahlia.getMarket(id);
            console.log("MarketId:", IDahlia.MarketId.unwrap(id));
            _printContract(contractName, address(market.vault));
            vm.stopBroadcast();
        } else {
            console.log(contractName, "already deployed");
        }
    }
}
