import type { GetBlockNumberReturnType } from "viem";
import { createPublicClient, http } from "viem";
import { mainnet } from "viem/chains";

export const waitForRpc = async (rpcUrl: string): Promise<GetBlockNumberReturnType> => {
  const client = createPublicClient({ chain: mainnet, transport: http(rpcUrl) });

  while (true) {
    let currentBlockNumber = undefined;
    try {
      currentBlockNumber = await client.getBlockNumber();
    } catch (err) {}
    if (currentBlockNumber !== undefined) {
      return currentBlockNumber;
    }
    console.log("RPC is not ready yet, retrying...");
    await new Promise((resolve) => setTimeout(resolve, 1000)); // Sleep for 1 second
  }
};
