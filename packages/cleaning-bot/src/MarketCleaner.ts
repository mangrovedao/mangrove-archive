import { logger } from "./util/logger";
import { Market, Offer } from "@giry/mangrove-js/dist/nodejs/market";
import { MgvToken } from "@giry/mangrove-js/dist/nodejs/mgvtoken";
import { Provider } from "@ethersproject/providers";
import { BigNumber, BigNumberish } from "ethers";
import Big from "big.js";

Big.DP = 20; // precision when dividing
Big.RM = Big.roundHalfUp; // round to nearest

type OfferCleaningEstimates = {
  bounty: Big; // wei
  gas: Big;
  gasPrice: Big; // wei
  minerTipPerGas: Big; // wei
  totalCost: Big; // wei
  netResult: Big; // wei
};

// FIXME Move to mangrove.js
export type BA = "bids" | "asks";

// FIXME move to Mangrove.js
const maxWantsOrGives = BigNumber.from(2).pow(96).sub(1);
const maxGasReq = BigNumber.from(2).pow(256).sub(1);

export class MarketCleaner {
  #market: Market;
  #provider: Provider;
  #isCleaning: boolean;

  constructor(market: Market, provider: Provider) {
    this.#market = market;
    this.#provider = provider;

    this.#isCleaning = false;
  }

  public async clean(blockNumber: number): Promise<void> {
    // TODO non-thread safe reentrancy lock - is this is an issue in JS?
    if (this.#isCleaning) {
      logger.debug(
        `Already cleaning so ignoring request to clean at block #${blockNumber}`,
        {
          base: this.#market.base.name,
          quote: this.#market.quote.name,
        }
      );

      return;
    }
    this.#isCleaning = true;

    // FIXME this should be a property/method on Market
    if (!(await this.#isMarketOpen())) {
      logger.warn(
        `Market is closed at block #${blockNumber}. Waiting for next block.`,
        { base: this.#market.base.name, quote: this.#market.quote.name }
      );
      return;
    }

    logger.info(`Cleaning market at block #${blockNumber}`, {
      base: this.#market.base.name,
      quote: this.#market.quote.name,
    });

    // TODO I think this is not quite EIP-1559 terminology - should fix
    const gasPrice = await this.#estimateGasPrice(this.#provider);
    const minerTipPerGas = this.#estimateMinerTipPerGas(this.#provider);

    const { asks, bids } = await this.#market.requestBook();
    logger.info(`Order book retrieved`, {
      base: this.#market.base.name,
      quote: this.#market.quote.name,

      data: {
        asksCount: asks.length,
        bidsCount: bids.length,
      },
    });

    await this.#cleanOfferList(asks, "asks", gasPrice, minerTipPerGas);
    await this.#cleanOfferList(bids, "bids", gasPrice, minerTipPerGas);
    this.#isCleaning = false;
  }

  async #isMarketOpen(): Promise<boolean> {
    // FIXME the naming of the config properties is confusing. Maybe asksLocalConfig or similar?
    const { asks, bids } = await this.#market.config();
    return asks.active && bids.active;
  }

  async #cleanOfferList(
    offerList: Offer[],
    bookSide: BA,
    gasPrice: Big,
    minerTipPerGas: Big
  ): Promise<void> {
    for (const offer of offerList) {
      const willOfferFail = await this.#willOfferFail(offer, bookSide);
      if (!willOfferFail) {
        continue;
      }

      const estimates = await this.#estimateCostsAndGains(
        offer,
        bookSide,
        gasPrice,
        minerTipPerGas
      );
      if (estimates.netResult.gt(0)) {
        logger.info("Identified offer that is profitable to clean", {
          base: this.#market.base.name,
          quote: this.#market.quote.name,
          bookSide: bookSide,
          offer: offer,
          data: { estimates },
        });
        // TODO Do we have the liquidity to do the snipe?
        //    - If we're trading 0 (zero) this is just the gas, right?
        await this.#cleanOffer(offer, bookSide);
      }
    }
  }

  async #estimateCostsAndGains(
    offer: Offer,
    bookSide: BA,
    gasPrice: Big,
    minerTipPerGas: Big
  ): Promise<OfferCleaningEstimates> {
    const bounty = this.#estimateBounty(offer, bookSide);
    const gas = await this.#estimateGas(offer, bookSide);
    const totalCost = gas.mul(gasPrice.plus(minerTipPerGas));
    const netResult = bounty.minus(totalCost);
    return {
      bounty,
      gas,
      gasPrice,
      minerTipPerGas,
      totalCost,
      netResult,
    };
  }

  async #estimateGasPrice(provider: Provider): Promise<Big> {
    const gasPrice = await provider.getGasPrice();
    return Big(gasPrice.toString());
  }

  #estimateMinerTipPerGas(provider: Provider): Big {
    // TODO Implement
    logger.debug(
      "Using hard coded miner tip (1) because #estimateMinerTipPerGas is not implemented",
      { base: this.#market.base.name, quote: this.#market.quote.name }
    );
    return Big(1);
  }

  #estimateBounty(offer: Offer, bookSide: BA): Big {
    // TODO Implement
    logger.debug(
      "Using hard coded bounty estimate because #estimateBounty is not implemented",
      {
        base: this.#market.base.name,
        quote: this.#market.quote.name,
        bookSide: bookSide,
        offer: offer,
      }
    );
    return Big(1e18);
  }

  async #estimateGas(offer: Offer, bookSide: BA): Promise<Big> {
    const gasEstimate =
      await this.#market.mgv.cleanerContract.estimateGas.collect(
        ...this.#createCollectParams(bookSide, offer)
      );
    return Big(gasEstimate.toString());
  }

  async #willOfferFail(offer: Offer, bookSide: BA): Promise<boolean> {
    try {
      // FIXME move to mangrove.js API
      await this.#market.mgv.cleanerContract.callStatic.collect(
        ...this.#createCollectParams(bookSide, offer)
      );
    } catch (e) {
      logger.debug("Static collect of offer failed", {
        base: this.#market.base.name,
        quote: this.#market.quote.name,
        bookSide: bookSide,
        offer: offer,
        data: e,
      });
      return false;
    }
    logger.debug("Static collect of offer succeeded", {
      base: this.#market.base.name,
      quote: this.#market.quote.name,
      bookSide: bookSide,
      offer: offer,
    });

    return true;
  }

  // TODO How do source liquidity for the snipes?
  //  - Can we just trade 0 (zero) ? That's the current approach
  //  - If not, we must implement strategies for sourcing and calculate the costs, incl. gas
  //  - The cleaner contract would have to implement the sourcing strategy
  //  - We don't want to do that in V0.
  async #cleanOffer(offer: Offer, bookSide: BA): Promise<boolean> {
    logger.debug("Cleaning offer", {
      base: this.#market.base.name,
      quote: this.#market.quote.name,
      bookSide: bookSide,
      offer: offer,
    });

    try {
      // FIXME move to mangrove.js API
      const collectTx = await this.#market.mgv.cleanerContract.collect(
        ...this.#createCollectParams(bookSide, offer)
      );
      // TODO Maybe don't want to wait for the transaction to be mined?
      const txReceipt = await collectTx.wait();
    } catch (e) {
      logger.warn("Cleaning of offer failed", {
        base: this.#market.base.name,
        quote: this.#market.quote.name,
        bookSide: bookSide,
        offer: offer,
        data: e,
      });
      return false;
    }
    logger.info("Successfully cleaned offer", {
      base: this.#market.base.name,
      quote: this.#market.quote.name,
      bookSide: bookSide,
      offer: offer,
    });
    return true;
  }

  #createCollectParams(
    bookSide: BA,
    offer: Offer
  ): [
    string,
    string,
    [BigNumberish, BigNumberish, BigNumberish, BigNumberish][],
    boolean
  ] {
    const { inboundToken, outboundToken } = this.#getTokens(bookSide);
    return [
      inboundToken.address,
      outboundToken.address,
      [[offer.id, 0, 0, maxGasReq]], // (offer id, taker wants, taker gives, gas requirement)
      false,
    ];
    // FIXME The following are the result of different strategies per 2021-10-26:
    // WORKS:
    //   inboundToken.address,
    //   outboundToken.address,
    //   [[offer.id, 0, 0, maxGasReq]], // (offer id, taker wants, taker gives, gas requirement)
    //   false,
    //
    // WORKS:
    //   inboundToken.address,
    //   outboundToken.address,
    //   [[offer.id, 0, 0, maxGasReq]], // (offer id, taker wants, taker gives, gas requirement)
    //   true,
    //
    // WORKS: This works, though I think Adrien said the last argument should be `false` ?
    //   inboundToken.address,
    //   outboundToken.address,
    //   [[offer.id, 0, maxWantsOrGives, maxGasReq]], // (offer id, taker wants, taker gives, gas requirement)
    //   true,
    //
    // FAILS: This worked in week 41, but no longer - how come? This is the strategy Adrien recommended
    //   inboundToken.address,
    //   outboundToken.address,
    //   [[offer.id, 0, maxWantsOrGives, maxGasReq]], // (offer id, taker wants, taker gives, gas requirement)
    //   false,
    //
    // WEIRD: The following succeeds in the call to MgvCleaner, but does not remove the offer nor yield any bounty - why is that?
    //   inboundToken.address,
    //   outboundToken.address,
    //   [[offer.id, maxWantsOrGives, 0, maxGasReq]], // (offer id, taker wants, taker gives, gas requirement)
    //   false,
    //
    // WEIRD: The following succeeds in the call to MgvCleaner, but does not remove the offer nor yield any bounty - why is that?
    //   inboundToken.address,
    //   outboundToken.address,
    //   [[offer.id, maxWantsOrGives, 0, maxGasReq]], // (offer id, taker wants, taker gives, gas requirement)
    //   true,
  }

  // FIXME move/integrate into Market API?
  #getTokens(bookSide: BA): {
    inboundToken: MgvToken;
    outboundToken: MgvToken;
  } {
    return {
      inboundToken:
        bookSide === "asks" ? this.#market.base : this.#market.quote,
      outboundToken:
        bookSide === "asks" ? this.#market.quote : this.#market.base,
    };
  }
}
