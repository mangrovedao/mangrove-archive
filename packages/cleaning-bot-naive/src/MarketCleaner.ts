import { logger } from "@giry/commonlib-js/src/logger";
import { Market, Offer } from "@giry/mangrove-js/dist/nodejs/market";
import { Provider } from "@ethersproject/providers";
import { Wallet } from "@ethersproject/wallet";
import { BA } from "./mangrove-js-type-aliases";
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

export class MarketCleaner {
  #market: Market;
  #provider: Provider;
  #wallet: Wallet;

  constructor(market: Market, provider: Provider, wallet: Wallet) {
    this.#market = market;
    this.#provider = provider;
    this.#wallet = wallet;
    this.#provider.on("block", async (blockNumber) => this._clean(blockNumber));
    logger.info("MarketCleaner started", { market: market });
  }

  private async _clean(blockNumber: number) {
    const globalConfig = await this.#market.mgv.config();
    // FIXME maybe this should be a property/method on Mangrove.
    if (globalConfig.dead) {
      logger.debug(
        `Mangrove is dead at block number ${blockNumber}. Stopping MarketCleaner`,
        { market: this.#market }
      );
      this.#provider.off("block", this._clean);
      return;
    }

    // FIXME this should be a property/method on Market
    if (!(await this._isMarketOpen())) {
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
    const gasPrice = this._estimateGasPrice(this.#provider);
    const minerTipPerGas = this._estimateMinerTipPerGas(this.#provider);

    const { asks, bids } = await this.#market.book();
    logger.info(`Order book for retrieved`, {
      market: this.#market,
      data: {
        asksCount: asks.length,
        bidsCount: bids.length,
      },
    });

    await this._cleanOfferList(asks, "asks", gasPrice, minerTipPerGas);
    await this._cleanOfferList(bids, "bids", gasPrice, minerTipPerGas);
  }

  private async _isMarketOpen(): Promise<boolean> {
    // FIXME the naming of the config properties is confusing. Maybe asksLocalConfig or similar?
    const { asks, bids } = await this.#market.config();
    return asks.active && bids.active;
  }

  private async _cleanOfferList(
    offers: Offer[],
    ba: BA,
    gasPrice: Big,
    minerTipPerGas: Big
  ) {
    // TODO Figure out criteria for when to snipe:
    //  - Offer will/is likely to fail
    const candidateFailingOffers = offers.filter(this._willOfferFail);
    logger.debug(
      `Identified ${candidateFailingOffers.length} offers that may fail on ${ba} side of market`,
      { market: this.#market }
    );
    //  - What is the potential gross gain, i.e. the bounty ?
    //  - How much gas will be required for the transaction?
    //  - How big a tip should we give the miner?
    //  - What is the net gain, if any?
    const offersWithCleaningEstimates = candidateFailingOffers.map((o) => ({
      offer: o,
      estimates: this._estimateProfitability(o, gasPrice, minerTipPerGas),
    }));
    const profitableCleaningOffers = offersWithCleaningEstimates.filter((oe) =>
      oe.estimates.netResult.gt(0)
    );
    logger.debug(
      `Identified ${profitableCleaningOffers.length} offers that will be profitable to clean on ${ba} side of market`,
      { market: this.#market }
    );
    // TODO Do we have the liquidity to do the snipe?
    //    - If we're trading 0 (zero) this is just the gas, right?
    // TODO How do source liquidity for the snipes?
    //  - Can we just trade 0 (zero) ?
    //  - If not, we must implement strategies for sourcing and calculate the costs, incl. gas
    //  - The cleaner contract would have to implement the sourcing strategy
    //  - We don't want to do that in V0.
    for (const { offer, estimates } of profitableCleaningOffers) {
      logger.info(`Cleaning offer ${offer.id} on ${ba} side of market`, {
        market: this.#market,
        data: estimates,
      });
      await this._snipeOffer(offer, ba);
    }
  }

  private _willOfferFail(offer: Offer): boolean {
    // TODO Identify offers that will/are likely to fail - HOW TO DETERMINE THIS?
    //    - I guess it depends on the offer's strategy, so we should have a way to idenfify that. Maybe just by contract address?
    //    - Maybe a heuristic for determining candidates and then a local simulation of the transaction to confirm?
    return true;
  }

  private _estimateProfitability(
    offer: Offer,
    gasPrice: Big,
    minerTipPerGas: Big
  ): OfferCleaningEstimates {
    const bounty = this._estimateBounty(offer);
    const gas = this._estimateGas(offer);
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

  private _estimateGasPrice(provider: Provider): Big {
    // TODO Implement
    logger.debug(
      "Using hard coded gas price estimate (1) because _estimateGasPrice is not implemented",
      { market: this.#market }
    );
    return Big(1);
    //return Big((await provider.getGasPrice()).);
  }

  private _estimateMinerTipPerGas(provider: Provider): Big {
    // TODO Implement
    logger.debug(
      "Using hard coded miner tip (1) because _estimateMinerTipPerGas is not implemented",
      { market: this.#market }
    );
    return Big(1);
  }

  private _estimateBounty(offer: Offer): Big {
    // TODO Implement
    logger.debug(
      "Using hard bounty estimate (10) because _estimateBounty is not implemented",
      { market: this.#market }
    );
    return Big(10);
  }

  private _estimateGas(offer: Offer): Big {
    // TODO Implement
    logger.debug(
      "Using hard coded gas estimate (1) because _estimateGas is not implemented",
      { market: this.#market }
    );
    return Big(1);
  }

  private async _snipeOffer(offer: Offer, ba: BA) {
    logger.debug(`Sniping offer ${offer.id} from ${ba} on market`, {
      market: this.#market,
    });
    // TODO Call my snipe contract
  }
}
