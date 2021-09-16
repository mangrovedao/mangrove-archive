import { ethers } from 'ethers';

import { getSigner } from "./getsigner"

import dotenvFlow from "dotenv-flow";

dotenvFlow.config();
if (!process.env["NODE_CONFIG_DIR"]) {
  process.env["NODE_CONFIG_DIR"] = __dirname + "/config/";
}
import config from "config";

import Mangrove from "../../../mangrove.js/src/index";
import { Market } from "../../../mangrove.js/src/market";

const toWei = (v : number, u = "ether") => ethers.utils.parseUnits(v.toString(), u);

const main = async () => {
  const mgv = await Mangrove.connect(
    "http://127.0.0.1:8545"
    ,
    {
      privateKey: getSigner(),
    }
    );

  const baseTokenName = "TokenA";
  const quoteTokenName = "TokenB";

  // const addrA = mgv.getAddress(baseTokenName);
  // const addrB = mgv.getAddress(quoteTokenName);

  await mgv.cacheDecimals(baseTokenName);
  await mgv.cacheDecimals(quoteTokenName);

  const A_B_market = await mgv.market({base: baseTokenName, quote: quoteTokenName});

  /*
  * the following snipe works, while the buy fails. As for the mm-bot-v0, the offer is posted on behalf of the signer indicated by the privateKey used to sign the connection - an EOA.
  * 
  * For takers, this may very well make sense.
  */


    /* This currently fails with an mgv taker failure, but may be related to how the offerbook looks? */

  const rec = await A_B_market.buy({volume: 500, price: 10000000000000});
  
    // console.log("...Attempting to snipe an order on A B market");
    // console.log();  
    // const rec = await mgv.contract.snipe(
    //  addrA, 
    //  addrB,
    //  0,
    //  toWei(0),
    //  toWei(1),
    //  ethers.constants.MaxUint256,
    //  true
    //  );
    console.dir(rec);
  }

main();