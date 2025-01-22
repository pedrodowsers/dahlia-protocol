import { execa } from "execa";

const env = { ...process.env, NX_VERBOSE_LOGGING: "true" };
const $$ = execa({ env, verbose: "full" });
const $ = execa({ env, verbose: "short" });

const checkCommand = async (commandName: string): Promise<void> => {
  try {
    await $$`which ${commandName}`;
  } catch (err) {
    console.error(`Command [${commandName}] is not available. Please install it.`);
    process.exit(1);
  }
};

async function prepareSubmodules() {
  await $`git submodule update --init`;
  // await $({ cwd: "../lib/royco" })`git submodule deinit lib/solmate`;
  // await $({ cwd: "../lib/royco" })`git submodule deinit lib/solady`;
  // await $({ cwd: "../lib/royco" })`git submodule deinit lib/openzeppelin-contracts`;
  await $({ cwd: "../" })`forge clean`;
}
const command = process.argv[2] ?? "setup";
if (command === "submodules") {
  await prepareSubmodules();
} else {
  console.log("Running setup...");
  // Verify environment
  await checkCommand("forge");
  await $`pnpm husky`;
  await $`forge install`;
  // await $`pip3 install slither-analyzer`;
  await prepareSubmodules();

  console.log("Setup complete!");
}
