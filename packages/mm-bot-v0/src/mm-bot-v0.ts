/* TODO: Use hardhat temporarily to get signer */
const hre = require("hardhat");
const ethers = hre.ethers;
/* --- */

import dotenvFlow from "dotenv-flow";

dotenvFlow.config();
if (!process.env["NODE_CONFIG_DIR"]) {
  process.env["NODE_CONFIG_DIR"] = __dirname + "/config/";
}
import config from "config";

import Mangrove from "../../../mangrove.js/src/index";
import { Market } from "../../../mangrove.js/src/market";

/*
* Task:
* Write the simplest market-maker bot, possible
* using the mangrove.js lib
* No solidity code.
* Fully provisioned offer.
* 
* Bot assumes that a contract with funds has been deployed (before run), 
* which adheres to Mangroves offer interface contract.
* 
* 
* Do:
  * Post simple offer
  * Every time offer is take, repost same offer
  * If the offer is not taken [when?] fail
  * 
  *
*/

/* --- TODO temp using hardhat to get a signer 
   ---      should get signer externally */

const mnemonic = hre.network.config.accounts.mnemonic;
const addresses = [];
const privateKeys = [];
for (let i = 0; i < 20; i++) {
  const wallet = new ethers.Wallet.fromMnemonic(
    mnemonic,
    `m/44'/60'/0'/0/${i}`
  );
  addresses.push(wallet.address);
  privateKeys.push(wallet._signingKey().privateKey);
}

/* --- */

const toWei = (v, u = "ether") => ethers.utils.parseUnits(v.toString(), u);

async function printOrderBook(market: Market){
  console.log(`...Attempting to get mgv book for market ${market}:`);
  const book = await market.book();
  console.dir(book);
}

async function printMarketConfig(market: Market){
  console.log(`...Attempting to get mgv config for market ${market.config.name}:`);

  const marketConfig = await market.config();
  console.dir(marketConfig);
  console.log();  
}

const main = async () => {
  const mgv = await Mangrove.connect(
    "http://127.0.0.1:8545"
    ,
    {
      privateKey: privateKeys[0],
    }    
    );

  const baseTokenName = "TokenA";
  const quoteTokenName = "TokenB";

  const addrA = mgv.getAddress(baseTokenName);
  const addrB = mgv.getAddress(quoteTokenName);

  await mgv.cacheDecimals(baseTokenName);
  await mgv.cacheDecimals(quoteTokenName);

  const A_B_market = await mgv.market({base: baseTokenName, quote: quoteTokenName});

  await printMarketConfig(A_B_market);

  await printOrderBook(A_B_market);

  console.log();

  console.log("...Attempting to post new offer on A B market");

  await mgv.contract.newOffer(
    addrA, 
    addrB, 
    toWei(1),
    toWei(1), 
    10_000, 
    1, 
    0 );

  await printOrderBook(A_B_market);    
}

main();