import { Command } from "commander";
import _ from "lodash";

import { deployContractsOnNetworks, interceptAllOutput } from "./utils.ts";

await interceptAllOutput();

const program = new Command();

program.option("-r, --remote", "Deploy on remote", false).parse(process.argv);

const options = program.opts<{ remote: boolean }>();
const remote = options.remote;

if (!remote) await import("./recreate-docker-otterscan.ts");
if (!remote) await deployContractsOnNetworks({ script: "PointsFactory", remote });
await deployContractsOnNetworks({ script: "ChainlinkWstETHToETH", remote });
await deployContractsOnNetworks({ script: "WrappedVaultImplementation", remote });
await deployContractsOnNetworks({ script: "DahliaRegistry", remote });
await deployContractsOnNetworks({ script: "IrmFactory", remote });
await deployContractsOnNetworks({ script: "VariableIrm", remote });
await deployContractsOnNetworks({ script: "Dahlia", remote });
await deployContractsOnNetworks({ script: "WrappedVaultFactory", remote });
await deployContractsOnNetworks({ script: "Timelock", remote });
await deployContractsOnNetworks({ script: "DahliaPythOracleFactory", remote });
await deployContractsOnNetworks({ script: "DahliaPythOracle", remote });
await deployContractsOnNetworks({ script: "WrappedVault", remote });
await deployContractsOnNetworks({ script: "DahliaRegistryTransfer", remote });
