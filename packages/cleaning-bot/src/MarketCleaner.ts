import { logger } from "./util/logger";
import { Market, Offer } from "@giry/mangrove-js/dist/nodejs/market";
import { MgvToken } from "@giry/mangrove-js/dist/nodejs/mgvtoken";
import { Provider } from "@ethersproject/providers";
import { Signer, BigNumber, BigNumberish } from "ethers";
import { BookSide } from "./mangrove-js-type-aliases";
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

// FIXME move to Mangrove.js
const maxWants = BigNumber.from(2).pow(96).sub(1);
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

  public async clean(blockNumber: number) {
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
    bookSide: BookSide,
    gasPrice: Big,
    minerTipPerGas: Big
  ) {
    for (const offer of offerList) {
      let willOfferFail = await this.#willOfferFail(offer, bookSide);
      if (!willOfferFail) {
        continue;
      }

      let estimates = await this.#estimateCostsAndGains(
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
    bookSide: BookSide,
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

  #estimateBounty(offer: Offer, bookSide: BookSide): Big {
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

  async #estimateGas(offer: Offer, bookSide: BookSide): Promise<Big> {
    const { inboundToken, outboundToken } = this.#getTokens(bookSide);
    const gasEstimate =
      await this.#market.mgv.cleanerContract.estimateGas.collect(
        inboundToken.address,
        outboundToken.address,
        [this.#createTargetForCollect(offer)],
        true
      );
    return Big(gasEstimate.toString());
  }

  async #willOfferFail(offer: Offer, bookSide: BookSide): Promise<boolean> {
    const { inboundToken, outboundToken } = this.#getTokens(bookSide);
    try {
      // FIXME move to mangrove.js API
      await this.#market.mgv.cleanerContract.callStatic.collect(
        inboundToken.address,
        outboundToken.address,
        [this.#createTargetForCollect(offer)],
        true
      );
    } catch (e) {
      logger.debug("Static touchAndCollect of offer failed", {
        base: this.#market.base.name,
        quote: this.#market.quote.name,
        bookSide: bookSide,
        offer: offer,
        data: e,
      });
      return false;
    }
    logger.debug("Static touchAndCollect of offer succeeded", {
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
  async #cleanOffer(offer: Offer, bookSide: BookSide) {
    logger.debug("Cleaning offer", {
      base: this.#market.base.name,
      quote: this.#market.quote.name,
      bookSide: bookSide,
      offer: offer,
    });
    const { inboundToken, outboundToken } = this.#getTokens(bookSide);
    try {
      // FIXME move to mangrove.js API
      const collectTx = await this.#market.mgv.cleanerContract.collect(
        inboundToken.address,
        outboundToken.address,
        [this.#createTargetForCollect(offer)],
        true
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

  // FIXME move/integrate into Market API?
  #getTokens(bookSide: BookSide): {
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

  #createTargetForCollect(
    offer: Offer
  ): [BigNumberish, BigNumberish, BigNumberish, BigNumberish] {
    return [offer.id, 0, maxWants, maxGasReq];
  }
}
