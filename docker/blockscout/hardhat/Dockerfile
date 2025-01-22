FROM node:20-alpine

WORKDIR /usr/src/app

COPY . .

RUN yarn install --non-interactive --frozen-lockfile

EXPOSE 8545

ENTRYPOINT ["./node_modules/.bin/hardhat", "--config", "hardhat.config.local.js", "node"]
