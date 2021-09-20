import { BigNumberish, ContractTransaction } from "ethers";
import { TradeParams, bookReturns, Bigish, localConfig } from "./types";
import type { Mangrove } from './mangrove';
import Big from 'big.js';
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
export declare class Market {
    #private;
    mgv: Mangrove;
    base: string;
    quote: string;
    /**
     * Initialize a new `params.base`:`params.quote` market.
     *
     * `params.mgv` will be used as mangrove instance
     */
    constructor(params: {
        mgv: Mangrove;
        base: string;
        quote: string;
    });
    /**
     * Return config local to a market.
     * Returned object is of the form
     * {bids,asks} where bids and asks are of type `localConfig`
     * Notes:
     * Amounts are converted to plain numbers.
     * density is converted to public token units per gas used
     * fee *remains* in basis points of the token being bought
     */
    config(): Promise<{
        asks: localConfig;
        bids: localConfig;
    }>;
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
    toUnits(bq: "base" | "quote", amount: Bigish): Big;
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
    fromUnits(bq: "base" | "quote", amount: Bigish): Big;
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
    buy(params: TradeParams): Promise<ContractTransaction>;
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
    sell(params: TradeParams): Promise<ContractTransaction>;
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
    book({ maxOffers }?: {
        maxOffers?: BigNumberish;
    }): Promise<{
        asks: {
            id: number;
            prev: number;
            next: number;
            gasprice: number;
            maker: string;
            gasreq: number;
            overhead_gasbase: number;
            offer_gasbase: number;
            gives: Big;
            wants: Big;
            volume: Big;
            price: Big;
        }[];
        bids: {
            id: number;
            prev: number;
            next: number;
            gasprice: number;
            maker: string;
            gasreq: number;
            overhead_gasbase: number;
            offer_gasbase: number;
            gives: Big;
            wants: Big;
            volume: Big;
            price: Big;
        }[];
    }>;
    /**
     * Extend an array of offers returned by the mangrove contract with price/volume info.
     *
     * volume will always be in base token:
     * * if mapping asks, volume is token being bought by taker
     * * if mapping bids, volume is token being sold by taker
     */
    mapBook(ba: ("bids" | "asks"), ids: bookReturns["indices"], offers: bookReturns["offers"], details: bookReturns["details"]): {
        id: number;
        prev: number;
        next: number;
        gasprice: number;
        maker: string;
        gasreq: number;
        overhead_gasbase: number;
        offer_gasbase: number;
        gives: Big;
        wants: Big;
        volume: Big;
        price: Big;
    }[];
}
