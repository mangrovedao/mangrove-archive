import { utils as ethersUtils, BigNumber, ContractTransaction } from "ethers";
import {
  TradeParams,
  BookReturns,
  Bigish,
  internalConfig,
  localConfig,
  bookSubscriptionEvent,
} from "./types";
import { Mangrove } from "./mangrove";

const DEFAULT_MAX_OFFERS = 50;

/* Note on big.js:
ethers.js's BigNumber (actually BN.js) only handles integers
big.js handles arbitrary precision decimals, which is what we want
for more on big.js vs decimals.js vs. bignumber.js (which is *not* ethers's BigNumber):
  github.com/MikeMcl/big.js/issues/45#issuecomment-104211175
*/
import Big from "big.js";
Big.DP = 20; // precision when dividing
Big.RM = Big.roundHalfUp; // round to nearest

//TODO Implement maxVolume?:number
type bookOpts = { fromId: number; maxOffers: number; chunkSize?: number };
const bookOptsDefault: bookOpts = { fromId: 0, maxOffers: DEFAULT_MAX_OFFERS };
type semibookMap = { offers: { [key: string]: Offer }; best: number };
export type Offer = {
  id: number;
  prev: number;
  next: number;
  gasprice: number;
  maker: string;
  gasreq: number;
  overhead_gasbase: number;
  offer_gasbase: number;
  wants: Big;
  gives: Big;
  volume: Big;
  price: Big;
};

type OfferData = {
  id: number | BigNumber;
  prev: number | BigNumber;
  next: number | BigNumber;
  gasprice: number | BigNumber;
  maker: string;
  gasreq: number | BigNumber;
  overhead_gasbase: number | BigNumber;
  offer_gasbase: number | BigNumber;
  wants: BigNumber;
  gives: BigNumber;
};

type semibook = {
  ba: "bids" | "asks";
  gasbase: { offer_gasbase: number; overhead_gasbase: number };
  offers: { [key: string]: Offer };
  best: number;
};

type bookSubscriptionCbArgument = { ba: "asks" | "bids"; offer: Offer } & (
  | { type: "OfferWrite" }
  | {
      type: "OfferFail";
      taker: string;
      takerWants: Big;
      takerGives: Big;
      statusCode: string;
      makerData: string;
    }
  | { type: "OfferSuccess"; taker: string; takerWants: Big; takerGives: Big }
  | { type: "OfferRetract" }
);

/**
 * The Market class focuses on a mangrove market.
 * Onchain, market are implemented as two orderbooks,
 * one for the pair (base,quote), the other for the pair (quote,base).
 *
 * Market initialization needs to store the network name, so you cannot
 * directly use the constructor. Instead `new Market(...)`, do
 *
 * `await Market.connect(...)`
 */
export class Market {
  mgv: Mangrove;
  base: { name: string; address: string };
  quote: { name: string; address: string };

  subscriptions: { asksCallback?: any; bidsCallback?: any };

  /**
   * Initialize a new `params.base`:`params.quote` market.
   *
   * `params.mgv` will be used as mangrove instance
   */
  constructor(params: { mgv: Mangrove; base: string; quote: string }) {
    this.subscriptions = {};
    this.mgv = params.mgv;
    this.base = {
      name: params.base,
      address: this.mgv.getAddress(params.base),
    };

    this.quote = {
      name: params.quote,
      address: this.mgv.getAddress(params.quote),
    };
  }

  createBookEventCallback<T>(
    semibook: semibook,
    cb: (a: bookSubscriptionCbArgument, utils?: T) => void,
    utils: T
  ): (...args: any[]) => any {
    return (_evt) => {
      const evt: bookSubscriptionEvent = this.mgv.events.interface.parseLog(
        _evt
      ) as any;

      // declare const evt: EventTypes.OfferWriteEvent;
      let next;
      let offer;
      switch (evt.name) {
        case "OfferWrite":
          removeOffer(semibook, evt.args.id.toNumber());

          try {
            next = BigNumber.from(getNext(semibook, evt.args.prev.toNumber()));
          } catch (e) {
            // next was not found, we are outside local OB copy. skip.
          }

          offer = this.toOfferObject(semibook.ba, {
            ...evt.args,
            ...semibook.gasbase,
            next,
          });

          insertOffer(semibook, evt.args.id.toNumber(), offer);

          cb(
            {
              type: evt.name,
              offer: offer,
              ba: semibook.ba,
            },
            utils
          );
          break;

        case "OfferFail":
          cb(
            {
              type: evt.name,
              ba: semibook.ba,
              taker: evt.args.taker,
              offer: removeOffer(semibook, evt.args.id.toNumber()),
              takerWants: this.fromUnits(
                semibook.ba === "asks" ? "base" : "quote",
                evt.args.takerWants.toString()
              ),
              takerGives: this.fromUnits(
                semibook.ba === "asks" ? "quote" : "base",
                evt.args.takerGives.toString()
              ),
              statusCode: evt.args.statusCode,
              makerData: evt.args.makerData,
            },
            utils
          );
          break;

        case "OfferSuccess":
          cb(
            {
              type: evt.name,
              ba: semibook.ba,
              taker: evt.args.taker,
              offer: removeOffer(semibook, evt.args.id.toNumber()),
              takerWants: this.fromUnits(
                semibook.ba === "asks" ? "base" : "quote",
                evt.args.takerWants.toString()
              ),
              takerGives: this.fromUnits(
                semibook.ba === "asks" ? "quote" : "base",
                evt.args.takerGives.toString()
              ),
            },
            utils
          );
          break;

        case "OfferRetract":
          cb(
            {
              type: evt.name,
              ba: semibook.ba,
              offer: removeOffer(semibook, evt.args.id.toNumber()),
            },
            utils
          );
          break;

        case "SetGasbase":
          semibook.gasbase.overhead_gasbase =
            evt.args.overhead_gasbase.toNumber();
          semibook.gasbase.offer_gasbase = evt.args.offer_gasbase.toNumber();
          break;
        default:
          throw Error(`Unknown event ${evt}`);
      }
    };
  }

  subscribed(): boolean {
    return Object.keys(this.subscriptions).length > 0;
  }

  unsubscribe(): void {
    if (!this.subscribed()) throw Error("Not subscribed");
    const { asksFilter, bidsFilter } = this.#bookFilter();
    const { asksCallback, bidsCallback } = this.subscriptions;
    this.mgv.events.off(asksFilter, asksCallback);
    this.mgv.events.off(bidsFilter, bidsCallback);
  }

  /* eslint-disable-next-line @typescript-eslint/explicit-module-boundary-types */
  #bookFilter() {
    /* Disjunction of possible event names */
    const topics0 = [
      "OfferSuccess",
      "OfferFail",
      "OfferWrite",
      "OfferRetract",
      "SetGasbase",
    ].map((e) =>
      this.mgv.events.interface.getEventTopic(
        this.mgv.events.interface.getEvent(e as any)
      )
    );

    const base_padded = ethersUtils.hexZeroPad(this.base.address, 32);
    const quote_padded = ethersUtils.hexZeroPad(this.quote.address, 32);

    const asksFilter = {
      address: this.mgv._address,
      topics: [topics0, base_padded, quote_padded],
    };

    const bidsFilter = {
      address: this.mgv._address,
      topics: [topics0, quote_padded, base_padded],
    };

    return { asksFilter, bidsFilter };
  }

  /* warning! you should await this otherwise you'll *think* you're reading the book when you're not */
  async subscribe(
    cb: (x: any) => void,
    opts: bookOpts = bookOptsDefault
  ): Promise<void> {
    if (this.subscribed()) throw Error("Already subscribed.");

    if (opts.fromId !== 0) {
      throw Error(
        "Cannot subscribe to order book without reading it from the start."
      );
    }

    const config = await this.config();

    const { asksFilter, bidsFilter } = this.#bookFilter();

    const rawAsks = await this.rawBook(
      this.base.address,
      this.quote.address,
      opts
    );
    const rawBids = await this.rawBook(
      this.quote.address,
      this.base.address,
      opts
    );

    const asks = {
      ba: "asks" as const,
      gasbase: {
        overhead_gasbase: config.asks.overhead_gasbase,
        offer_gasbase: config.asks.offer_gasbase,
      },
      ...this.rawToMap("asks", ...rawAsks),
    };

    const bids = {
      ba: "bids" as const,
      gasbase: {
        overhead_gasbase: config.bids.overhead_gasbase,
        offer_gasbase: config.bids.offer_gasbase,
      },
      ...this.rawToMap("bids", ...rawBids),
    };

    const utils = {
      book: () => {
        return {
          asks: mapToArray(asks.best, asks.offers),
          bids: mapToArray(bids.best, bids.offers),
        };
      },
    };

    const asksCallback = this.createBookEventCallback(asks, cb, utils);
    const bidsCallback = this.createBookEventCallback(bids, cb, utils);

    this.subscriptions = { asksCallback, bidsCallback };

    this.mgv.events.on(asksFilter, asksCallback);
    this.mgv.events.on(bidsFilter, bidsCallback);
  }

  #mapConfig(ba: "bids" | "asks", cfg: internalConfig): localConfig {
    const bq = ba === "asks" ? "base" : "quote";
    return {
      active: cfg.local.active,
      fee: cfg.local.fee.toNumber(),
      density: this.fromUnits(bq, cfg.local.density.toString()).toNumber(),
      overhead_gasbase: cfg.local.overhead_gasbase.toNumber(),
      offer_gasbase: cfg.local.offer_gasbase.toNumber(),
      lock: cfg.local.lock,
      best: cfg.local.best.toNumber(),
      last: cfg.local.last.toNumber(),
    };
  }

  /**
   * Return config local to a market.
   * Returned object is of the form
   * {bids,asks} where bids and asks are of type `localConfig`
   * Notes:
   * Amounts are converted to plain numbers.
   * density is converted to public token units per gas used
   * fee *remains* in basis points of the token being bought
   */
  async config(): Promise<{ asks: localConfig; bids: localConfig }> {
    const rawAskConfig = await this.mgv.contract.config(
      this.base.address,
      this.quote.address
    );
    const rawBidsConfig = await this.mgv.contract.config(
      this.quote.address,
      this.base.address
    );
    return {
      asks: this.#mapConfig("asks", rawAskConfig),
      bids: this.#mapConfig("bids", rawBidsConfig),
    };
  }

  /**
   * Convert base/quote from public amount to internal contract amount.
   * Uses each token's `decimals` parameter.
   *
   * If `bq` is `"base"`, will convert the base, the quote otherwise.
   *
   * @example
   * ```
   * const market = await mgv.market({base:"USDC",quote:"DAI"}
   * market.toUnits("base",10) // 10e6
   * market.toUnits("quote",100) //10e19
   * ```
   */
  toUnits(bq: "base" | "quote", amount: Bigish): Big {
    return this.mgv.toUnits(this[bq].name, amount);
  }

  /**
   * Convert base/quote from internal amount to public amount.
   * Uses each token's `decimals` parameter.
   *
   * If `bq` is `"base"`, will convert the base, the quote otherwise.
   *
   * @example
   * ```
   * const market = await mgv.market({base:"USDC",quote:"DAI"}
   * market.fromUnits("base","1e7") // 10
   * market.fromUnits("quote",1e18) // 1
   * ```
   */
  fromUnits(bq: "base" | "quote", amount: Bigish): Big {
    return this.mgv.fromUnits(this[bq].name, amount);
  }

  /**
   * Market buy order. Will attempt to buy base token using quote tokens.
   * Params can be of the form:
   * - `{volume,price}`: buy `wants` tokens for a max average price of `price`, or
   * - `{wants,gives}`: accept implicit max average price of `gives/wants`
   *
   * Will stop if
   * - book is empty, or
   * - price no longer good, or
   * - `wants` tokens have been bought.
   *
   * @example
   * ```
   * const market = await mgv.market({base:"USDC",quote:"DAI"}
   * market.buy({volume: 100, price: '1.01'}) //use strings to be exact
   * ```
   */
  buy(params: TradeParams): Promise<ContractTransaction> {
    let wants = "price" in params ? Big(params.volume) : Big(params.wants);
    let gives = "price" in params ? wants.mul(params.price) : Big(params.gives);

    wants = this.toUnits("base", wants);
    gives = this.toUnits("quote", gives);

    return this.#marketOrder({ gives, wants, orderType: "buy" });
  }

  /**
   * Market sell order. Will attempt to sell base token for quote tokens.
   * Params can be of the form:
   * - `{volume,price}`: sell `gives` tokens for a min average of `price`
   * - `{wants,gives}`: accept implicit min average price of `gives/wants`.
   *
   * Will stop if
   * - book is empty, or
   * - price no longer good, or
   * -`gives` tokens have been sold.
   *
   * @example
   * ```
   * const market = await mgv.market({base:"USDC",quote:"DAI"}
   * market.sell({volume: 100, price: 1})
   * ```
   */
  sell(params: TradeParams): Promise<ContractTransaction> {
    let gives = "price" in params ? Big(params.volume) : Big(params.gives);
    let wants = "price" in params ? gives.div(params.price) : Big(params.wants);

    gives = this.toUnits("base", gives);
    wants = this.toUnits("quote", wants);

    return this.#marketOrder({ wants, gives, orderType: "sell" });
  }

  /**
   * Low level Mangrove market order.
   * If `orderType` is `"buy"`, the base/quote market will be used,
   * with contract function argument `fillWants` set to true.
   *
   * If `orderType` is `"sell"`, the quote/base market will be used,
   * with contract function argument `fillWants` set to false.
   */
  #marketOrder(params: {
    wants: Big;
    gives: Big;
    orderType: "buy" | "sell";
  }): Promise<ContractTransaction> {
    const [onchainBase, onchainQuote, fillWants] =
      params.orderType === "buy"
        ? [this.base, this.quote, true]
        : [this.quote, this.base, false];

    return this.mgv.contract.marketOrder(
      onchainBase.address,
      onchainQuote.address,
      BigNumber.from(params.wants.toFixed(0)),
      BigNumber.from(params.gives.toFixed(0)),
      fillWants
    );
  }

  async rawBook(
    base_a: string,
    quote_a: string,
    opts: bookOpts = bookOptsDefault
  ): Promise<[BookReturns.indices, BookReturns.offers, BookReturns.details]> {
    opts = { ...bookOptsDefault, ...opts };
    // by default chunk size is number of offers desired
    const chunkSize =
      typeof opts.chunkSize === "undefined" ? opts.maxOffers : opts.chunkSize;
    // save total number of offers we want
    let maxOffersLeft = opts.maxOffers;

    let nextId = opts.fromId; // fromId == 0 means "start from best"
    let offerIds = [],
      offers = [],
      details = [];
    await this.mgv.contract.config(this.mgv._address, this.mgv._address);
    do {
      const [_nextId, _offerIds, _offers, _details] =
        await this.mgv.readerContract.book(
          base_a,
          quote_a,
          opts.fromId,
          chunkSize
        );
      offerIds = offerIds.concat(_offerIds);
      offers = offers.concat(_offers);
      details = details.concat(_details);
      nextId = _nextId.toNumber();
      maxOffersLeft = maxOffersLeft - chunkSize;
    } while (maxOffersLeft > 0 && nextId !== 0);

    //clean end of arrays (remove null-offers)
    let lastIndex = offerIds.findIndex((e) => e.eq(0));
    lastIndex = lastIndex < 0 ? opts.maxOffers : lastIndex;
    return [
      offerIds.slice(0, lastIndex),
      offers.slice(0, lastIndex),
      details.slice(0, lastIndex),
    ];
  }

  /**
   * Return current book state of the form
   * @example
   * ```
   * {
   *   asks: [
   *     {id: 3, price: 3700, volume: 4, ...},
   *     {id: 56, price: 3701, volume: 7.12, ...}
   *   ],
   *   bids: [
   *     {id: 811, price: 3600, volume: 1.23, ...},
   *     {id: 80, price: 3550, volume: 1.11, ...}
   *   ]
   * }
   * ```
   *  Asks are standing offers to sell base and buy quote.
   *  Bids are standing offers to buy base and sell quote.
   *  All prices are in quote/base, all volumes are in base.
   *  Order is from best to worse from taker perspective.
   */
  // eslint-disable-next-line @typescript-eslint/explicit-module-boundary-types
  async book(opts: bookOpts = bookOptsDefault) {
    const rawAsks = await this.rawBook(
      this.base.address,
      this.quote.address,
      opts
    );
    const rawBids = await this.rawBook(
      this.quote.address,
      this.base.address,
      opts
    );
    return {
      asks: this.rawToArray("asks", ...rawAsks),
      bids: this.rawToArray("bids", ...rawBids),
    };
  }

  rawToMap(
    ba: "bids" | "asks",
    ids: BookReturns.indices,
    offers: BookReturns.offers,
    details: BookReturns.details
  ): semibookMap {
    const data: semibookMap = {
      offers: {},
      best: 0,
    };

    for (const [index, offerId] of ids.entries()) {
      if (offerId.eq(0)) {
        break;
      }

      if (index === 0) {
        data.best = ids[0].toNumber();
      }

      data.offers[offerId.toNumber()] = this.toOfferObject(ba, {
        id: ids[index],
        ...offers[index],
        ...details[index],
      });
    }

    return data;
  }

  /**
   * Extend an array of offers returned by the mangrove contract with price/volume info.
   *
   * volume will always be in base token:
   * * if mapping asks, volume is token being bought by taker
   * * if mapping bids, volume is token being sold by taker
   */
  // eslint-disable-next-line @typescript-eslint/explicit-module-boundary-types
  rawToArray(
    ba: "bids" | "asks",
    ids: BookReturns.indices,
    offers: BookReturns.offers,
    details: BookReturns.details
  ) {
    return ids.map((offerId, index) => {
      return this.toOfferObject(ba, {
        id: ids[index],
        ...offers[index],
        ...details[index],
      });
    });
  }

  toOfferObject(ba: "bids" | "asks", raw: OfferData): Offer {
    const _gives = this.fromUnits(
      ba === "asks" ? "base" : "quote",
      raw.gives.toString()
    );
    const _wants = this.fromUnits(
      ba === "asks" ? "quote" : "base",
      raw.wants.toString()
    );

    const [baseVolume, quoteVolume] =
      ba === "asks" ? [_gives, _wants] : [_wants, _gives];

    if (baseVolume.eq(0)) {
      throw Error("baseVolume is 0 (not allowed)");
    }

    const toNum = (i: number | BigNumber): number =>
      typeof i === "number" ? i : i.toNumber();

    return {
      id: toNum(raw.id),
      prev: toNum(raw.prev),
      next: toNum(raw.next),
      gasprice: toNum(raw.gasprice),
      maker: raw.maker,
      gasreq: toNum(raw.gasreq),
      overhead_gasbase: toNum(raw.overhead_gasbase),
      offer_gasbase: toNum(raw.offer_gasbase),
      gives: _gives,
      wants: _wants,
      volume: baseVolume,
      price: quoteVolume.div(baseVolume),
    };
  }
}

const removeOffer = (semibook, id) => {
  const ofr = semibook.offers[id];
  if (ofr) {
    if (ofr.prev === 0) {
      semibook.best = ofr.next;
    } else {
      semibook.offers[ofr.prev].next = ofr.next;
    }

    if (ofr.next !== 0) {
      semibook.offers[ofr.next].prev = ofr.prev;
    }

    delete semibook.offers[id];
    return ofr;
  } else {
    return null;
  }
};

// Assumes ofr.prev and ofr.next are present in local OB copy.
// Assumes id is not already in book;
const insertOffer = (semibook, id, ofr) => {
  semibook.offers[id] = ofr;
  if (ofr.prev === 0) {
    semibook.best = ofr.id;
  } else {
    semibook.offers[ofr.prev].next = id;
  }

  if (ofr.next !== 0) {
    semibook.offers[ofr.next].prev = id;
  }
};

const getNext = ({ offers, best }: semibook, prev) => {
  if (prev === 0) {
    return best;
  } else {
    if (!offers[prev]) {
      throw Error(
        "Trying to get next of an offer absent from local orderbook copy"
      );
    } else {
      return offers[prev].next;
    }
  }
};

// May stop before endofbook if we only have a prefix
const mapToArray = (best: number, offers: any) => {
  const ary = [];

  if (best !== 0) {
    let latest = offers[best];
    do {
      ary.push(latest);
      latest = offers[latest.next];
    } while (typeof offers[latest] !== "undefined");
  }

  return ary;
};
