import { logger } from "./util/logger";
import { Market, Offer } from "@giry/mangrove-js/dist/nodejs/market";
import { Provider } from "@ethersproject/providers";
import { Wallet } from "@ethersproject/wallet";
import { BA } from "./mangrove-js-type-aliases";
import Big from "big.js";
import { BigNumber } from "ethers";
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

export class MarketCleaner {
  #market: Market;
  #provider: Provider;
  #wallet: Wallet;
  #isCleaning: boolean;

  constructor(market: Market, provider: Provider, wallet: Wallet) {
    this.#market = market;
    this.#provider = provider;
    this.#wallet = wallet;
    this.#isCleaning = false;
    this.#provider.on("block", async (blockNumber) => this.#clean(blockNumber));
    logger.info("MarketCleaner started", { market: market });
  }

  async #clean(blockNumber: number) {
    // TODO non-thread safe reentrancy lock - is this is an issue in JS?
    if (this.#isCleaning) {
      logger.debug(`Already cleaning so skipping block number ${blockNumber}`, {
        market: this.#market,
      });
      return;
    }
    this.#isCleaning = true;
    const globalConfig = await this.#market.mgv.config();
    // FIXME maybe this should be a property/method on Mangrove.
    if (globalConfig.dead) {
      logger.debug(
        `Mangrove is dead at block number ${blockNumber}. Stopping MarketCleaner`,
        { market: this.#market }
      );
      this.#provider.off("block", this.#clean);
      return;
    }

    // FIXME this should be a property/method on Market
    if (!(await this.#isMarketOpen())) {
      logger.warn(
        `Market is closed at block number ${blockNumber}. Waiting for next block.`,
        { market: this.#market }
      );
      return;
    }

    logger.info(`Cleaning market at block number ${blockNumber}`, {
      market: this.#market,
    });

    // TODO I think this is not quite EIP-1559 terminology - should fix
    const gasPrice = this.#estimateGasPrice(this.#provider);
    const minerTipPerGas = this.#estimateMinerTipPerGas(this.#provider);

    const { asks, bids } = await this.#market.book();
    logger.info(`Order book retrieved`, {
      market: this.#market,
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
    offers: Offer[],
    bookSide: BA,
    gasPrice: Big,
    minerTipPerGas: Big
  ) {
    // TODO Figure out criteria for when to snipe:
    //  - Offer will/is likely to fail
    for (const offer of offers) {
      let willOfferFail = await this.#willOfferFail(offer, bookSide);
      if (!willOfferFail) {
        continue;
      }

      let estimates = this.#estimateProfitability(
        offer,
        bookSide,
        gasPrice,
        minerTipPerGas
      );
      if (estimates.netResult.gt(0)) {
        await this.#snipeOffer(offer, bookSide);
      }
    }
    // const candidateFailingOffers = offers.filter(this.#willOfferFail);
    // logger.debug(
    //   `Identified ${candidateFailingOffers.length} offers that may fail on ${bookSide} side of market`,
    //   { market: this.#market }
    // );
    // //  - What is the potential gross gain, i.e. the bounty ?
    // //  - How much gas will be required for the transaction?
    // //  - How big a tip should we give the miner?
    // //  - What is the net gain, if any?
    // const offersWithCleaningEstimates = candidateFailingOffers.map((o) => ({
    //   offer: o,
    //   estimates: this.#estimateProfitability(o, gasPrice, minerTipPerGas),
    // }));
    // const profitableCleaningOffers = offersWithCleaningEstimates.filter((oe) =>
    //   oe.estimates.netResult.gt(0)
    // );
    // logger.debug(
    //   `Identified ${profitableCleaningOffers.length} offers that will be profitable to clean on ${bookSide} side of market`,
    //   { market: this.#market }
    // );
    // // TODO Do we have the liquidity to do the snipe?
    // //    - If we're trading 0 (zero) this is just the gas, right?
    // // TODO How do source liquidity for the snipes?
    // //  - Can we just trade 0 (zero) ?
    // //  - If not, we must implement strategies for sourcing and calculate the costs, incl. gas
    // //  - The cleaner contract would have to implement the sourcing strategy
    // //  - We don't want to do that in V0.
    // for (const { offer, estimates } of profitableCleaningOffers) {
    //   logger.info(`Cleaning offer ${offer.id} on ${bookSide} side of market`, {
    //     market: this.#market,
    //     data: estimates,
    //   });
    //   await this.#snipeOffer(offer, bookSide);
    // }
  }

  #estimateProfitability(
    offer: Offer,
    bookSide: BA,
    gasPrice: Big,
    minerTipPerGas: Big
  ): OfferCleaningEstimates {
    const bounty = this.#estimateBounty(offer, bookSide);
    const gas = this.#estimateGas(offer, bookSide);
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

  #estimateGasPrice(provider: Provider): Big {
    // TODO Implement
    logger.debug(
      "Using hard coded gas price estimate (1) because #estimateGasPrice is not implemented",
      { market: this.#market }
    );
    return Big(1);
    //return Big((await provider.getGasPrice()).);
  }

  #estimateMinerTipPerGas(provider: Provider): Big {
    // TODO Implement
    logger.debug(
      "Using hard coded miner tip (1) because #estimateMinerTipPerGas is not implemented",
      { market: this.#market }
    );
    return Big(1);
  }

  #estimateBounty(offer: Offer, bookSide: BA): Big {
    // TODO Implement
    logger.debug(
      "Using hard bounty estimate (10) because #estimateBounty is not implemented",
      { market: this.#market, bookSide: bookSide, offer: offer }
    );
    return Big(10);
  }

  #estimateGas(offer: Offer, bookSide: BA): Big {
    // TODO Implement
    logger.debug(
      "Using hard coded gas estimate (1) because #estimateGas is not implemented",
      { market: this.#market, bookSide: bookSide, offer: offer }
    );
    return Big(1);
  }

  async #willOfferFail(offer: Offer, bookSide: BA): Promise<boolean> {
    // TODO This is clunky - can we make a nice abstraction?
    const base = bookSide === "asks" ? this.#market.base : this.#market.quote;
    const quote = bookSide === "asks" ? this.#market.quote : this.#market.base;
    try {
      // FIXME move to mangrove.js API
      await this.#market.mgv.cleanerContract.callStatic.collect(
        base.address,
        quote.address,
        // takerWants = 0 and takerGives = 0 means we trust the offer's price
        [
          [
            offer.id, // offer id
            0, // takerWants
            BigNumber.from(2).pow(256).sub(1), // takerGives
            BigNumber.from(2).pow(256).sub(1), // gasreq
          ],
        ],
        true
      );
    } catch (e) {
      logger.debug("Static touchAndCollect of offer failed", {
        market: this.#market,
        bookSide: bookSide,
        offer: offer,
        data: e,
      });
      return false;
    }
    logger.debug("Static touchAndCollect of offer succeeded", {
      market: this.#market,
      bookSide: bookSide,
      offer: offer,
    });
    return true;
  }

  async #snipeOffer(offer: Offer, bookSide: BA) {
    logger.debug(`Sniping offer ${offer.id} from ${bookSide} on market`, {
      market: this.#market,
      bookSide: bookSide,
      offer: offer,
    });
    // TODO This is clunky - can we make a nice abstraction?
    const base = bookSide === "asks" ? this.#market.base : this.#market.quote;
    const quote = bookSide === "asks" ? this.#market.quote : this.#market.base;
    try {
      // FIXME move to mangrove.js API
      await this.#market.mgv.cleanerContract.collect(
        base.address,
        quote.address,
        [
          [
            offer.id,
            0,
            BigNumber.from(2).pow(256).sub(1), // takerGives
            BigNumber.from(2).pow(256).sub(1), // gasreq
          ],
        ],
        true
      );
    } catch (e) {
      logger.debug("touchAndCollect of offer failed", {
        market: this.#market,
        bookSide: bookSide,
        offer: offer,
        data: e,
      });
      return false;
    }
    logger.info("Successfully cleaned offer", {
      market: this.#market,
      bookSide: bookSide,
      offer: offer,
    });
  }
}
