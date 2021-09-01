import { addresses, decimals } from './constants';
import * as eth from './eth';
import { Market } from './market';
import { ConnectOptions, Provider, ProviderNetwork, Bigish } from "./types";
import { IERC20__factory } from './types/typechain/ierc20';
import { Mangrove as MangroveContract, Mangrove__factory } from './types/typechain/mangrove';
import { MgvReader as MgvReaderContract, MgvReader__factory } from './types/typechain/mgvreader';

import Big from 'big.js';
Big.prototype[Symbol.for('nodejs.util.inspect.custom')] = Big.prototype.toString;


/* Prevent directly calling Mangrove constructor
   use Mangrove.connect to make sure the network is reached during construction */
let canConstructMangrove = false;

export class Mangrove {
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

  static async connect(provider: Provider | string = 'mainnet', options: ConnectOptions = {}) : Promise<Mangrove> {

    options.provider = provider || options.provider;
    provider = eth._createProvider(options);
    const network = await eth.getProviderNetwork(provider);
    const address = Mangrove.getAddress("Mangrove", network.name);
    const readerAddress = Mangrove.getAddress("MgvReader", network.name);
    canConstructMangrove = true;
    const mgv = new Mangrove({
      provider: provider,
      network: network,
      contract: Mangrove__factory.connect(address,provider),
      readerContract: MgvReader__factory.connect(readerAddress,provider)
    });
    canConstructMangrove = false;
    return mgv;
  }

  constructor(params:{provider:Provider,network:ProviderNetwork,contract:MangroveContract,readerContract:MgvReaderContract}) {
    if (!canConstructMangrove) {
      throw Error("Mangrove.js must be initialized async with Mangrove.connect (constructors cannot be async)");
    }
    this._provider = params.provider,
    this._network = params.network;
    this.contract = params.contract;
    this.readerContract = params.readerContract;
  }
  /* Instance */
  /************** */

  /* Get Market object. 
     Argument of the form `{base,quote}` where each is a string.
     To set your own token, use `setDecimals` and `setAddress`.
  */
  async market(params: {base:string,quote:string}): Promise<Market> {
    return new Market({
      mgv: this,
      base: params.base,
      quote: params.quote
    });
  }

  /**
   * Read a contract address on the current network. 
   */
  getAddress(name: string) : string {
    return Mangrove.getAddress(name, this._network.name || "mainnet");
  }

  /** 
   * Set a contract address on the current network. 
   */
  setAddress(name: string, address: string) : void {
    Mangrove.setAddress(name,address,this._network.name || "mainnet");
  }

  /**
   * Read decimals for `tokenName`.
   * To read decimals off the chain, use `cacheDecimals`. 
   */
  getDecimals(tokenName: string) : number {
    return Mangrove.getDecimals(tokenName);
  }

  /** 
   * Set decimals for `tokenName`.
   */
  setDecimals(tokenName: string,decimals:number) : void{
    Mangrove.setDecimals(tokenName, decimals);
  }

  /** 
   * Read chain for decimals of `tokenName` on current network and save them.
   */
  async cacheDecimals(tokenName: string) : Promise<number> {
    return Mangrove.cacheDecimals(tokenName, this._provider);
  }

  /** Convert public token amount to internal token representation
   *
   *  @example
   *  ```
   *  mgv.toUnits("USDC",10) // 10e6
   *  ```
   */
  toUnits(tokenName: string, amount: Bigish) : Big {
    return Big(amount).mul(Big(10).pow(this.getDecimals(tokenName)));
  }

  /** Convert internal token amount to public token representation
   *
   *  @example
   *  ```
   *  mgv.toUnits("DAI","1e19") // 10
   *  ```
   */
  fromUnits(tokenName: string, amount: Bigish) : Big {
    return Big(amount).div(Big(10).pow(this.getDecimals(tokenName)));
  }

  /**
   * Return global Mangrove config 
   */
  // eslint-disable-next-line @typescript-eslint/explicit-module-boundary-types
  async config() {
    const config = await this.contract.getConfig("", "");
    return config.global;
  }

  /* Static */
  /********** */

  /**
   * Read a contract address on the given network.
   */
  static getAddress(name:string, network="mainnet") : string {
    if (!(addresses[network])) {
      throw Error(`No addresses for network ${network}.`);
    }

    if (!addresses[network][name]) {
      throw Error(`No address for ${name} on network ${network}.`);
    }

    return addresses[network]?.[name] as string;
  }

  /**
   * Set a contract address on the given network.
   */
  static setAddress(name: string, address: string, network="mainnet") : void {
    if (!addresses[network]) {
      addresses[network] = {};
    }
    addresses[network][name] = address;
  }

  /**
   * Read decimals for `tokenName` on given network.
   * To read decimals directly onchain, use `cacheDecimals`.
   */
  static getDecimals(tokenName: string) : number {
    if (typeof decimals[tokenName] !== 'number') {
      throw Error(`No decimals on record for token ${tokenName}`);
    }

    return decimals[tokenName] as number;
  }

  /**
   * Set decimals for `tokenName` on current network. 
   */
  static setDecimals(tokenName: string,dec:number) : void {
    decimals[tokenName] = dec;
  }

  /**
   * Read chain for decimals of `tokenName` on current network and save them 
   */
  static async cacheDecimals(tokenName: string, provider:Provider) : Promise<number> {
    const network = await eth.getProviderNetwork(provider);
    const token = IERC20__factory.connect(Mangrove.getAddress(tokenName, network.name),provider);
    const decimals = await token.decimals();
    this.setDecimals(tokenName,decimals);
    return decimals;
  }

}
