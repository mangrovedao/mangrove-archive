/**
 * @file Ethereum
 * @desc These methods facilitate interactions with the Ethereum blockchain.
 */

import { ethers } from 'ethers';
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
export async function getProviderNetwork(
  provider: Provider
) : Promise<ProviderNetwork> {
  let _provider;
  if (provider._isSigner) {
    _provider = provider.provider;
  } else {
    _provider = provider;
  }

  let networkId;
  if (_provider.send) {
    networkId = await _provider.send('net_version');
  } else {
    networkId = _provider._network.chainId;
  }

  networkId = isNaN(networkId) ? 0 : +networkId;

  const network = ethers.providers.getNetwork(networkId) || { name: 'unknown' };

  return {
    id: networkId,
    name: network.name === 'homestead' ? 'mainnet' : network.name
  };
}

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
export function _createProvider(options: CallOptions = {}) : Provider {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let provider: any = options.provider || (options.network || 'mainnet');
  const isADefaultProvider = !!ethers.providers.getNetwork(provider.toString());

  // Create an ethers provider, web3s can sign
  if (isADefaultProvider) {
    provider = ethers.getDefaultProvider(provider);
  } else if (typeof provider === 'object') {
    provider = new ethers.providers.Web3Provider(provider).getSigner();
  } else {
    provider = new ethers.providers.JsonRpcProvider(provider);
  }

  // Add an explicit signer
  if (options.privateKey) {
    provider = new ethers.Wallet(options.privateKey, provider);
  } else if (options.mnemonic) {
    provider = new ethers.Wallet(ethers.Wallet.fromMnemonic(options.mnemonic), provider);
  }

  return provider;
}
