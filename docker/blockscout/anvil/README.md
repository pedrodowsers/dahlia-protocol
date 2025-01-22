# anvil docker

[see](https://book.getfoundry.sh/tutorials/foundry-docker)

## Setup

Build Docker image

```bash
docker build --platform linux/amd64 . -t anvil
```

Run Docker image

```bash
# !NOTE: Double check no other programs are using that port 8545
docker run -d -p 8545:8545 --platform linux/amd64 --name anvil anvil
```

Verify that container is running

```bash
docker logs --follow anvil
# Should see an output of wallet addresses and private keys
```

Don't forget to delete your container when you're done.

```bash
docker rm -f anvil
```
