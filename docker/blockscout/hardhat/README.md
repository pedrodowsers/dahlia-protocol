# hardhat docker

[see](https://github.com/statechannels/hardhat-docker.git)

TODO: I was thinking to add start of hardhat node as part of blockscout run
At this moment this is just finished

[see](https://github.com/statechannels/go-nitro/blob/64c4ee9a17f38939b393c647fb771313e7749043/packages/nitro-protocol/contracts/deploy/Create2Deployer.sol#L8)

## Setup

Build Docker image

```bash
docker build . -t hardhat
```

Run Docker image

```bash
# !NOTE: Double check no other programs are using that port 8545
docker run -it -d -p 8545:8545 --name hardhat hardhat
```

Verify that container is running

```bash
docker logs --follow hardhat
# Should see an output of wallet addresses and private keys
```

Voilà!

Don't forget to delete your container when you're done.

```bash
docker rm -f hardhat
```
