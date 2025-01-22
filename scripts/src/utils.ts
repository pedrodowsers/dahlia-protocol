import { Command } from "commander";
import { execa } from "execa";
import fs from "fs";
import _ from "lodash";
import fsPromises from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import stripAnsi from "strip-ansi";

import { Config, configDeployedName, load, loadConfigFile, saveConfigFile } from "./config.ts";
import { waitForRpc } from "./waitForRpc.ts";

export enum Network {
  MAINNET = "mainnet",
  SEPOLIA = "sepolia",
  CARTIO = "cartio",
}
export const DEPLOY_NETWORKS: Network[] = [Network.MAINNET, Network.CARTIO];

export interface Params {
  script: string;
  remote: boolean;
}

export async function interceptAllOutput(): Promise<void> {
  const program = new Command();
  program
    .option("-s, --script <path>", "Path to the .s.sol file", "")
    .option("-r, --remote", "Deploy on remote", false)
    .parse(process.argv);
  const args = program.opts<Params>();

  if (_.isUndefined(process.env["PRIVATE_KEY"])) {
    if (args.remote) {
      throw Error("Missing required deployer PRIVATE_KEY environment variable");
    } else {
      process.env["PRIVATE_KEY"] = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";
    }
  }

  if (_.isUndefined(process.env["WALLET_ADDRESS"])) {
    if (args.remote) {
      throw Error("Missing required owner WALLET_ADDRESS environment variable to own all deployed contracts");
    } else {
      process.env["WALLET_ADDRESS"] = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
    }
  }

  const scriptName = path.basename(process.argv[1], path.extname(process.argv[1])); // e.g., "app"
  const currentUnixSeconds = Math.floor(Date.now() / 1000);

  const filePath = `./logs/${scriptName}-${args.script}-${currentUnixSeconds}.log`;
  if (fs.existsSync(filePath)) {
    await fsPromises.unlink(filePath);
  }
  await fsPromises.mkdir(path.dirname(filePath), { recursive: true });
  const logStream = fs.createWriteStream(filePath, { flags: "a" });

  // Save original write methods
  const originalStdoutWrite = process.stdout.write;
  const originalStderrWrite = process.stderr.write;

  const writeToLog = (chunk: any): void => {
    const message = typeof chunk === "string" ? chunk : chunk.toString();
    logStream.write(stripAnsi(message));
  };

  // Monkey-patch process.stdout.write
  process.stdout.write = function (chunk, encoding?: any, callback?: any) {
    writeToLog(chunk);
    return originalStdoutWrite.call(process.stdout, chunk, encoding, callback);
  };

  // Monkey-patch process.stderr.write
  process.stderr.write = function (chunk, encoding?: any, callback?: any) {
    writeToLog(chunk);
    return originalStderrWrite.call(process.stderr, chunk, encoding, callback);
  };
}

const $$ = execa({ extendEnv: true, verbose: "full", stdout: ["pipe", "inherit"], stderr: ["pipe", "inherit"] });

export const recreateDockerOtterscan = async () => {
  for (const network of DEPLOY_NETWORKS) {
    const cfg: Config = load(network, {});
    const env = _.merge(
      _.pickBy(cfg, (value) => typeof value === "string"),
      { COMPOSE_PROJECT_NAME: `dahlia-${network}`, NX_VERBOSE_LOGGING: "true" },
    );
    await $$({ env })`pnpm nx run dahlia:otterscan`;
  }
};

const ANVIL_ACCOUNT_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";

/**
 * Sends money from first anvil hardcoded address with 10000 ETH to specified address
 * https://book.getfoundry.sh/tutorials/forking-mainnet-with-cast-anvil?highlight=anvil_impersonateAccount#transferring-dai
 * @param rpcUrl
 * @param address
 * @param amount
 */
export const sendMoneyToAddressOnAnvil = async (rpcUrl: string, address: string, amount: number) => {
  await waitForRpc(rpcUrl);
  // const last4DigitsOfReceiverAddress = address.slice(-4);
  // const logFilePath = `./logs/send-money-to-address-on-anvil-___${last4DigitsOfReceiverAddress}.log`;
  // const output = { file: logFilePath };
  await $$`cast rpc --rpc-url ${rpcUrl} anvil_impersonateAccount ${ANVIL_ACCOUNT_ADDRESS}`;
  await $$`cast send --rpc-url ${rpcUrl} --from ${ANVIL_ACCOUNT_ADDRESS} ${address} --value ${amount} --unlocked`;
};

async function runScript(
  env: Readonly<Partial<Record<string, string>>>,
  script: string,
  cfg: Config,
  network: Network,
  deployedContracts: Config,
) {
  // console.log("env", env);
  console.log(`network=${network}: Deploying contracts rpcUrl=${cfg.RPC_URL}`);
  const { stdout } = await $$({
    env,
    cwd: "..",
  })`forge script script/${script}.s.sol --rpc-url ${cfg.RPC_URL} --broadcast --private-key ${cfg.DEPLOYER_PRIVATE_KEY}`;

  for (const line of stdout.split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Za-z0-9_]+)=(0x[a-fA-F0-9]+|\d+)\b/);
    if (match) {
      const [, name, address] = match;
      if (deployedContracts[network] === undefined) {
        deployedContracts[network] = {};
      }
      deployedContracts[network][name] = address;
    }
  }
}

export const deployContractsOnNetworks = async (params: Params): Promise<void> => {
  const deployedName = configDeployedName(params.remote);
  const deployedContracts = loadConfigFile(deployedName);
  for (const network of DEPLOY_NETWORKS) {
    const cfg: Config = load(network, deployedContracts[network]);
    if (params.remote) {
      if (!cfg.RPC_URL || !cfg.SCANNER_BASE_URL) {
        throw new Error("Missing RPC_URL or SCANNER_BASE_URL");
      }
    } else {
      if (!cfg.RPC_PORT || !cfg.OTTERSCAN_PORT) {
        throw new Error("Missing RPC_PORT or OTTERSCAN_PORT");
      }
      cfg.RPC_URL = `http://localhost:${cfg.RPC_PORT}`;
      cfg.SCANNER_BASE_URL = `http://localhost:${cfg.OTTERSCAN_PORT}`;
    }
    await waitForRpc(cfg.RPC_URL);
    const env = _.pickBy(cfg, (value) => typeof value === "string");

    // If is an Array iterate each value
    if (_.isArray(cfg[params.script])) {
      for (const [index, value] of cfg[params.script].entries()) {
        const env = {
          ..._.pickBy(cfg, (value) => typeof value === "string"),
          ...value,
          INDEX: index,
        };
        await runScript(env, params.script, cfg, network, deployedContracts);
      }
    } else if (_.isUndefined(cfg[params.script])) {
      // If no value, run always script
      await runScript(env, params.script, cfg, network, deployedContracts);
    } else {
      console.log(`network=${network}: Skipped deployment of ${params.script}`);
    }
  }
  saveConfigFile(deployedName, deployedContracts);
};
