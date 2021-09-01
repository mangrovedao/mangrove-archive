import { BigNumber, BigNumberish, ContractTransaction } from "ethers";
import { TradeParams, bookReturns,Bigish } from "./types";
import type { Mangrove } from './mangrove';

/* Note on big.js:
ethers.js's BigNumber (actually BN.js) only handles integers
big.js handles arbitrary precision decimals, which is what we want
for more on big.js vs decimals.js vs. bignumber.js (which is *not* ethers's BigNumber):
  github.com/MikeMcl/big.js/issues/45#issuecomment-104211175
*/
import Big from 'big.js';
Big.DP = 20; // precision when dividing
Big.RM = Big.roundHalfUp; // round to nearest

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
  base: string;
  quote: string;

  /** 
   * Initialize a new `params.base`:`params.quote` market.
   * 
   * `params.mgv` will be used as mangrove instance
   */
  constructor(params:{mgv:Mangrove,base:string,quote:string}) {
    this.mgv = params.mgv;
    this.base = params.base;
    this.quote = params.quote;
  }

  /** 
   * Return config local to a market.
   */
  // eslint-disable-next-line @typescript-eslint/explicit-module-boundary-types
  async config() {
    const config = await this.mgv.contract.getConfig(this.mgv.getAddress(this.base), this.mgv.getAddress(this.quote));
    return config.local;
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
  toUnits(bq:"base"|"quote", amount: Bigish):Big {
    return this.mgv.toUnits(this[bq],amount);
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
  fromUnits(bq:"base"|"quote", amount: Bigish):Big {
    return this.mgv.fromUnits(this[bq],amount);
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
  buy(params: TradeParams) : Promise<ContractTransaction>{
    let wants = 'price' in params ? Big(params.volume) : Big(params.wants);
    let gives = 'price' in params ? wants.mul(params.price) : Big(params.gives);

    wants = this.toUnits("base", wants);
    gives = this.toUnits("quote", gives);

    return this.#marketOrder({ gives, wants, orderType:"buy"});
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
  sell(params: TradeParams) : Promise<ContractTransaction> {
    let gives = 'price' in params ? Big(params.volume) : Big(params.gives);
    let wants = 'price' in params ? gives.div(params.price) : Big(params.wants);

    gives = this.toUnits("base",gives);
    wants = this.toUnits("quote", wants);

    return this.#marketOrder({ wants, gives, orderType:"sell"});
  }

  /**
   * Low level Mangrove market order.
   * If `orderType` is `"buy"`, the base/quote market will be used,
   * with contract function argument `fillWants` set to true.
   * 
   * If `orderType` is `"sell"`, the quote/base market will be used, 
   * with contract function argument `fillWants` set to false.
   */
  #marketOrder(params: { wants: Big, gives: Big, orderType: "buy" | "sell" }) : Promise<ContractTransaction> {
    const [onchainBase, onchainQuote, fillWants] =
      params.orderType === "buy" ?
        [this.base, this.quote, true] :
        [this.quote, this.base, false];

    return this.mgv.contract.marketOrder(
      this.mgv.getAddress(onchainBase),
      this.mgv.getAddress(onchainQuote),
      BigNumber.from(params.wants.toFixed(0)),
      BigNumber.from(params.gives.toFixed(0)),
      fillWants
    )
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
   */
  // eslint-disable-next-line @typescript-eslint/explicit-module-boundary-types
  async book({ maxOffers = 50 }: { maxOffers?: BigNumberish } = { maxOffers: 50 }) {
    const _book = this.mgv.readerContract.book;
    const _base = this.mgv.getAddress(this.base);
    const _quote = this.mgv.getAddress(this.quote);
    return {
      asks: this.mapBook("asks", ... await _book(_base, _quote, maxOffers)),
      bids: this.mapBook("bids", ... await _book(_quote, _base, maxOffers))
    }
  }

  /**
   * Extend an array of offers returned by the mangrove contract with price/volume info.
   * 
   * volume will always be in base token:
   * * if mapping asks, volume is token being bought by taker
   * * if mapping bids, volume is token being sold by taker
   */
  // eslint-disable-next-line @typescript-eslint/explicit-module-boundary-types
  mapBook(ba: ("bids" | "asks"), ids:bookReturns["indices"],offers:bookReturns["offers"],details:bookReturns["details"]) {
    return ids.filter(id => !id.eq(0)).map((offerId, index) => {
      const gives= this.fromUnits("base",offers[index].gives.toString());
      const wants = this.fromUnits("quote",offers[index].wants.toString());

      const [baseVolume, quoteVolume] = ba === "asks" ? [gives,wants] : [wants,gives];

      return {
        id: offerId.toNumber(),
        prev: offers[index].prev.toNumber(),
        next: offers[index].next.toNumber(),
        gasprice: offers[index].gasprice.toNumber(),
        maker: details[index].maker,
        gasreq: details[index].gasreq.toNumber(),
        overhead_gasbase: details[index].overhead_gasbase.toNumber(),
        offer_gasbase: details[index].offer_gasbase.toNumber(),
        gives: gives,
        wants: wants,
        volume: baseVolume,
        price: quoteVolume.div(baseVolume)
      };
    });
  }
}
