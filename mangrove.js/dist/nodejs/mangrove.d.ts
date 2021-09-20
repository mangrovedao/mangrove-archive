import { Market } from './market';
import { ConnectOptions, Provider, ProviderNetwork, Bigish } from "./types";
import { Mangrove as MangroveContract, MgvReader as MgvReaderContract } from './types/typechain';
import Big from 'big.js';
export declare class Mangrove {
    _provider: Provider;
    _network: ProviderNetwork;
    contract: MangroveContract;
    readerContract: MgvReaderContract;
    /**
     * Creates an instance of the Mangrove Typescript object
     *
     * @param {Provider | string} [provider] Optional Ethereum network provider.
     *     Defaults to Ethers.js fallback mainnet provider.
     * @param {object} [options] Optional provider options.
     *
     * @example
     * ```
     * const mgv = await require('mangrove.js').connect(<arg>); // web browser
     * ```
     *
     * If arg is falsy, use options.provider.
     * If a non-url string is provided, it's interpreted as the network name (eg `connect('ropsten')`).
     * Otherwise arg may be `window.ethereum` (web browser), or `127.0.0.1:8545` (HTTP provider)
     * const mgv = await require('mangrove.js').connect('http://127.0.0.1:8545'); // HTTP provider
     *
     * Options:
     * * privateKey: `0x...`
     * * mnemonic: `horse battery ...`
     * * provider: overriden by first provider object
     *
     * @returns {Mangrove} Returns an instance mangrove.js
     */
    static connect(provider?: Provider | string, options?: ConnectOptions): Promise<Mangrove>;
    constructor(params: {
        provider: Provider;
        network: ProviderNetwork;
        contract: MangroveContract;
        readerContract: MgvReaderContract;
    });
    /************** */
    market(params: {
        base: string;
        quote: string;
    }): Promise<Market>;
    /**
     * Read a contract address on the current network.
     */
    getAddress(name: string): string;
    /**
     * Set a contract address on the current network.
     */
    setAddress(name: string, address: string): void;
    /**
     * Read decimals for `tokenName`.
     * To read decimals off the chain, use `cacheDecimals`.
     */
    getDecimals(tokenName: string): number;
    /**
     * Set decimals for `tokenName`.
     */
    setDecimals(tokenName: string, decimals: number): void;
    /**
     * Read chain for decimals of `tokenName` on current network and save them.
     */
    cacheDecimals(tokenName: string): Promise<number>;
    /** Convert public token amount to internal token representation
     *
     *  @example
     *  ```
     *  mgv.toUnits("USDC",10) // 10e6
     *  ```
     */
    toUnits(tokenName: string, amount: Bigish): Big;
    /** Convert internal token amount to public token representation
     *
     *  @example
     *  ```
     *  mgv.toUnits("DAI","1e19") // 10
     *  ```
     */
    fromUnits(tokenName: string, amount: Bigish): Big;
    /**
     * Return global Mangrove config
     */
    config(): Promise<[string, boolean, boolean, import("ethers").BigNumber, import("ethers").BigNumber, boolean] & {
        monitor: string;
        useOracle: boolean;
        notify: boolean;
        gasprice: import("ethers").BigNumber;
        gasmax: import("ethers").BigNumber;
        dead: boolean;
    }>;
    /********** */
    /**
     * Read a contract address on the given network.
     */
    static getAddress(name: string, network?: string): string;
    /**
     * Set a contract address on the given network.
     */
    static setAddress(name: string, address: string, network?: string): void;
    /**
     * Read decimals for `tokenName` on given network.
     * To read decimals directly onchain, use `cacheDecimals`.
     */
    static getDecimals(tokenName: string): number;
    /**
     * Set decimals for `tokenName` on current network.
     */
    static setDecimals(tokenName: string, dec: number): void;
    /**
     * Read chain for decimals of `tokenName` on current network and save them
     */
    static cacheDecimals(tokenName: string, provider: Provider): Promise<number>;
}
