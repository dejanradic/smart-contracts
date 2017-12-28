import Api from "@parity/api";

const accountSeeds = require("../utils/chain/accountSeeds.json");
const environmentConfig = require("../utils/config/environment.js");

const config = environmentConfig.development;
const provider = new Api.Provider.Http(`http://${config.host}:${config.port}`);
const api = new Api(provider);

async function main() {
  await Promise.all(accountSeeds.map(async (accountSeed, index) => {
    await api.parity.newAccountFromPhrase(accountSeed, "password");
    console.log(`Created account ${index+1} of ${accountSeeds.length}`);
  }));
  process.exit(0);
}

main();
