import { load } from "./config.ts";
import { DEPLOY_NETWORKS, interceptAllOutput, recreateDockerOtterscan, sendMoneyToAddressOnAnvil } from "./utils.ts";

await interceptAllOutput();

await recreateDockerOtterscan();

for (const network of DEPLOY_NETWORKS) {
  const cfg = load(network);
  const rpcUrl = `http://localhost:${cfg.RPC_PORT}`;
  await sendMoneyToAddressOnAnvil(rpcUrl, cfg.DAHLIA_OWNER, 10000000000000000000);
}
