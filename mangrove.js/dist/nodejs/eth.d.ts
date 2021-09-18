/**
 * @file Ethereum
 * @desc These methods facilitate interactions with the Ethereum blockchain.
 */
import { CallOptions, Provider, ProviderNetwork } from './types';
/**
 * This helps the mangrove.js constructor discover which Ethereum network the
 *     developer wants to use.
 *
 * @param {Provider | string} [provider] Optional Ethereum network provider.
 *     Defaults to Ethers.js fallback mainnet provider.
 *
 * @hidden
 *
 * @returns {object} Returns a metadata object containing the Ethereum network
 *     name and ID.
 */
export declare function getProviderNetwork(provider: Provider): Promise<ProviderNetwork>;
/**
 * Creates an Ethereum network provider object.
 *
 * @param {CallOptions} options The call options of a pending Ethereum
 *     transaction.
 *
 * @hidden
 *
 * @returns {object} Returns a valid Ethereum network provider object.
 */
export declare function _createProvider(options?: CallOptions): Provider;
