import test from "ava";
import api from "../../../utils/lib/api";
import { deployContract } from "../../../utils/lib/contracts";
import deployEnvironment from "../../../utils/deploy/contracts";
import createStakingFeed from "../../../utils/lib/createStakingFeed";

const environmentConfig = require("../../../utils/config/environment.js");
const BigNumber = require("bignumber.js");

const environment = "development";
const config = environmentConfig[environment];
BigNumber.config({ DECIMAL_PLACES: 18 });

// hoisted variables
let eurToken;
let mlnToken;
let accounts;
let opts;
let deployed;
let canonicalPriceFeed;
let pricefeeds;
let txid;

// mock data
const mockIpfs = "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG";
const mockBytes =
  "0x86b5eed81db5f691c36cc83eb58cb5205bd2090bf3763a19f0c5bf2f074dd84b";
const mockBreakIn = "0x0360E6384FEa0791e18151c531fe70da23c55fa2";
const mockBreakOut = "0xc6Eb2A235627Ac97EAbc6452F98Ce296a1EF3984";
const eurName = "Euro Token";
const eurSymbol = "EUR-T";
const eurDecimals = 12; // For different decimal test
const eurUrl = "europa.eu";
const mlnDecimals = 18;
const defaultMlnPrice = 10 ** 18;

const inputGas = 6000000;
const initialEurPrice = new BigNumber(10 ** 10);
const modifiedEurPrice1 = new BigNumber(2 * 10 ** 10);
const modifiedEurPrice2 = new BigNumber(3 * 10 ** 10);
const interval = 15;
const validity = 15;
const preEpochUpdatePeriod = 5;
const postEpochInterventionDelay = 5;
const minimumUpdates = 1;


// TODO: place in lib
function medianize(pricesArray) {
  let prices = pricesArray.filter(e => {
    if (e === 0) { return false; }
    return true;
  });
  prices = prices.sort();
  const len = prices.length;
  if (len % 2 === 0) {
    return prices[len / 2].add(prices[len / 2 - 1]).div(2);
  }
  return prices[(len - 1) / 2];
}

// get timestamp for a tx in seconds
async function txidToTimestamp(txid) {
  const receipt = await api.eth.getTransactionReceipt(txid);
  const timestamp = (await api.eth.getBlockByHash(receipt.blockHash)).timestamp;
  return Math.round(new Date(timestamp).getTime()/1000);
}

// get latest timestamp in seconds
async function getBlockTimestamp() {
  const timestamp = (await api.eth.getBlockByNumber('latest')).timestamp;
  return Math.round(new Date(timestamp).getTime()/1000);
}

async function mineToTime(timestamp) {
  while (await getBlockTimestamp() < timestamp) {
    await sleep (500);
    await api.eth.sendTransaction();
  }
}

async function mineSeconds(seconds) {
  for (let i = 0; i < seconds; i++) {
    await sleep(1000);
    await api.eth.sendTransaction();
  }
}

// TODO: remove this in future (when parity devchain implements fast-forwarding blockchain time)
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

test.before(async t => {
  deployed = await deployEnvironment(environment);
  accounts = await api.eth.accounts();
  opts = { from: accounts[0], gas: config.gas };
  eurToken = await deployed.EurToken;
  mlnToken = await deployed.MlnToken;

  canonicalPriceFeed = await deployContract(
    "pricefeeds/CanonicalPriceFeed", opts,
    [
      mlnToken.address,
      mlnToken.address,
      "Melon Token",
      "MLN-T",
      mlnDecimals,
      "melonport.com",
      mockBytes,
      [mockBreakIn, mockBreakOut],
      [],
      [],
      [interval, validity, preEpochUpdatePeriod, minimumUpdates, postEpochInterventionDelay],
      [config.protocol.staking.minimumAmount, config.protocol.staking.numOperators],
      accounts[0]
    ], () => {}, true
  );

  pricefeeds = [];
  for (let i = 0; i < 2; i++) {
    const stakingFeed = await createStakingFeed(opts, canonicalPriceFeed);
    await mlnToken.instance.approve.postTransaction(
      {from: accounts[0]}, [stakingFeed.address, config.protocol.staking.minimumAmount]
    );
    await stakingFeed.instance.depositStake.postTransaction(
      {from: accounts[0]}, [config.protocol.staking.minimumAmount, ""]
    );
    pricefeeds.push(stakingFeed);
  }

  await canonicalPriceFeed.instance.registerAsset.postTransaction(opts, [
    eurToken.address,
    eurName,
    eurSymbol,
    eurDecimals,
    eurUrl,
    mockIpfs,
    [mockBreakIn, mockBreakOut],
    [],
    []
  ]);
});

test.serial("update occurs automatically within update period", async t => {
  const nextEpochTime0 = await canonicalPriceFeed.instance.getNextEpochTime.call();
  await mineToTime(Number(nextEpochTime0)); // start a fresh epoch
  const nextEpochTime1 = await canonicalPriceFeed.instance.getNextEpochTime.call();
  await mineToTime(Number(nextEpochTime1) - preEpochUpdatePeriod); // mine past delay

  txid = await pricefeeds[0].instance.update.postTransaction(
    { from: accounts[0], gas: inputGas},
    [[mlnToken.address, eurToken.address], [defaultMlnPrice, initialEurPrice]]
  );    // set first epoch time

  const update1Time = await txidToTimestamp(txid)
  await mineToTime(Number(nextEpochTime1) + postEpochInterventionDelay + 1); // mine past delay

  const [eurPriceUpdate1, ] = await canonicalPriceFeed.instance.getPrice.call(
    {}, [eurToken.address]
  );
  const timeAtPriceFetch1 = await getBlockTimestamp();

  t.true(update1Time < nextEpochTime1); // update1 before next epoch
  t.true(update1Time >= nextEpochTime1 - preEpochUpdatePeriod); // within preEpoch period
  t.true(timeAtPriceFetch1 > Number(nextEpochTime1) + postEpochInterventionDelay);
  t.is(Number(eurPriceUpdate1), Number(initialEurPrice));
});

test.serial("update issued before interval is rejected", async t => {
  txid = await pricefeeds[0].instance.update.postTransaction(
    { from: accounts[0], gas: inputGas},
    [[mlnToken.address, eurToken.address], [defaultMlnPrice, modifiedEurPrice1]]
  );    // expected to fail, since it is before update time
  const update2Time = await txidToTimestamp(txid)
  const gasUsedPrematureUpdate = (await api.eth.getTransactionReceipt(txid)).gasUsed;
  const [eurPricePrematureUpdate, ] = await canonicalPriceFeed.instance.getPrice.call(
    {}, [eurToken.address]
  );
  const lastEpochTime2 = await canonicalPriceFeed.instance.getLastEpochTime.call();
  const nextEpochTime2 = await canonicalPriceFeed.instance.getNextEpochTime.call();

  t.true(update2Time > Number(lastEpochTime2));
  t.true(update2Time < Number(nextEpochTime2) - preEpochUpdatePeriod); // 2nd update premature
  t.is(Number(gasUsedPrematureUpdate), inputGas);   // expect a thrown tx (all gas consumed)
  t.is(Number(eurPricePrematureUpdate), Number(initialEurPrice)); // price did not update
});

test.serial("canonical price is only updated after intervention delay", async t => {
  const nextEpochTime3 = await canonicalPriceFeed.instance.getNextEpochTime.call();
  await mineToTime(Number(nextEpochTime3) - preEpochUpdatePeriod + 1); // mine to update period

  txid = await pricefeeds[0].instance.update.postTransaction(
    { from: accounts[0], gas: inputGas},
    [[mlnToken.address, eurToken.address], [defaultMlnPrice, modifiedEurPrice1]]
  );
  const update3Time = await txidToTimestamp(txid)
  const [eurPriceAfterUpdate3, ] = await canonicalPriceFeed.instance.getPrice.call(
    {}, [eurToken.address]
  );
  txid = await pricefeeds[1].instance.update.postTransaction(
    { from: accounts[0], gas: inputGas},
    [[mlnToken.address, eurToken.address], [defaultMlnPrice, modifiedEurPrice2]]
  );
  const update4Time = await txidToTimestamp(txid)
  const [eurPriceAfterUpdate4, ] = await canonicalPriceFeed.instance.getPrice.call(
    {}, [eurToken.address]
  );

  await mineToTime(Number(nextEpochTime3) + postEpochInterventionDelay + 1); // mine past delay

  const [eurPriceAfterEpoch3Delay, ] = await canonicalPriceFeed.instance.getPrice.call(
    {}, [eurToken.address]
  );

  // updates occurred in designated update interval
  t.true(update3Time < Number(nextEpochTime3));
  t.true(update3Time > Number(nextEpochTime3) - preEpochUpdatePeriod);
  t.true(update4Time < Number(nextEpochTime3));
  t.true(update4Time > Number(nextEpochTime3) - preEpochUpdatePeriod);
  // price did not update before delay
  t.is(Number(eurPriceAfterUpdate3), Number(initialEurPrice));
  t.is(Number(eurPriceAfterUpdate4), Number(initialEurPrice));
  // price updated after delay
  t.is(Number(eurPriceAfterEpoch3Delay), Number(medianize([modifiedEurPrice1, modifiedEurPrice2])));
});

test.serial("intervention causes feed to use previous price, and prevents updates", async t => {
  const nextEpochTime4 = await canonicalPriceFeed.instance.getNextEpochTime.call();
  await mineToTime(Number(nextEpochTime4) - preEpochUpdatePeriod + 1); // mine to update period

  const [eurPriceBeforeIntervention, ] = await canonicalPriceFeed.instance.getPrice.call(
    {}, [eurToken.address]
  );
  txid = await pricefeeds[0].instance.update.postTransaction(
    { from: accounts[0], gas: inputGas},
    [[mlnToken.address, eurToken.address], [defaultMlnPrice, modifiedEurPrice2]]
  );

  await mineToTime(Number(nextEpochTime4)); // mine to delay

  txid = await canonicalPriceFeed.instance.interruptUpdating.postTransaction({from: accounts[0]});

  await mineToTime(Number(nextEpochTime4) + postEpochInterventionDelay + 1); // mine past delay

  const [eurPriceAfterIntervention, ] = await canonicalPriceFeed.instance.getPrice.call(
    {}, [eurToken.address]
  );

  t.is(Number(eurPriceAfterIntervention), Number(eurPriceBeforeIntervention));

  const nextEpochTime5 = await canonicalPriceFeed.instance.getNextEpochTime.call();
  await mineToTime(Number(nextEpochTime5 - preEpochUpdatePeriod)); // mine to update period

  txid = await pricefeeds[0].instance.update.postTransaction(
    {from: accounts[0], gas: inputGas},
    [[mlnToken.address, eurToken.address], [defaultMlnPrice, modifiedEurPrice1]]
  );
  const gasUsedUpdate = (await api.eth.getTransactionReceipt(txid)).gasUsed;

  t.is(Number(gasUsedUpdate), inputGas);    // expect it to use all gas (throw)
});

test.serial("updating can be resumed by authority", async t => {
  await canonicalPriceFeed.instance.resumeUpdating.postTransaction();
  const nextEpochTime5 = await canonicalPriceFeed.instance.getNextEpochTime.call();
  await mineToTime(Number(nextEpochTime5) - preEpochUpdatePeriod); // mine to update period

  txid = await pricefeeds[0].instance.update.postTransaction(
    { from: accounts[0], gas: inputGas},
    [[mlnToken.address, eurToken.address], [defaultMlnPrice, modifiedEurPrice1]]
  );

  await mineToTime(Number(nextEpochTime5) + postEpochInterventionDelay + 1); // mine past delay

  const [eurPriceAfterResume, ] = await canonicalPriceFeed.instance.getPrice.call(
    {}, [eurToken.address]
  );

  t.is(Number(eurPriceAfterResume), Number(modifiedEurPrice1));
});
