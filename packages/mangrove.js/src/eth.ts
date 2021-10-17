/**
 * @file Ethereum
 * @desc These methods facilitate interactions with the Ethereum blockchain.
 */

import { ethers, Signer } from "ethers";
import { CallOptions, Provider, ProviderNetwork } from "./types";

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
  _provider: Provider
): Promise<ProviderNetwork> {
  let networkId;
  if (_provider["send"]) {
    networkId = await (_provider as any).send("net_version");
  } else if (_provider["_network"]) {
    networkId = (_provider as any)._network.chainId;
  } else {
    throw Error(
      "Provider can neither make RPC requests nor has a known network."
    );
  }

  networkId = isNaN(networkId) ? 0 : +networkId;

  let networkName;

  if (networkId === 31337) {
    networkName = "hardhat";
  } else {
    networkName = ethers.providers.getNetwork(networkId).name;
  }

  return {
    id: networkId,
    name: networkName === "homestead" ? "mainnet" : networkName,
  };
}

/**
 * Creates an Ethereum network provider object.
 *
 * @param {CallOptions} options The call options of a pending Ethereum
 *     transaction.
 *
 * options.provider can be:
 * - a string (url or ethers.js network name)
 * - an EIP-1193 provider object (eg window.ethereum)
 *
 * @hidden
 *
 * @returns {object} Returns a valid Ethereum network signer object with an attached provider.
 */
export function _createSigner(options: CallOptions = {}): Signer {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let provider: any = options.provider;
  const isADefaultProvider = !!ethers.providers.getNetwork(provider.toString());

  let signer: Signer;

  // Create an ethers provider, web3s can sign
  if (typeof provider === "string") {
    if (isADefaultProvider) {
      provider = ethers.getDefaultProvider(provider);
    } else {
      provider = new ethers.providers.JsonRpcProvider(provider);
    }
  } else {
    provider = new ethers.providers.Web3Provider(provider);
  }

  if (provider.getSigner) {
    signer = provider.getSigner();
  }

  if (
    signer &&
    (!!options.privateKey || !!options.mnemonic || !!options.signer)
  ) {
    console.warn("Signing info provided will override default signer.");
  }

  // Add an explicit signer
  if (options.signer) {
    signer = options.signer;
    if (options.mnemonic || options.privateKey) {
      console.warn("options.signer overrides mnemonic and privateKey.");
    }
  } else if (options.privateKey) {
    signer = new ethers.Wallet(options.privateKey, provider);
    if (options.mnemonic) {
      console.warn("options.privateKey overrides mnemonic.");
    }
  } else if (options.mnemonic) {
    signer = new ethers.Wallet(
      ethers.Wallet.fromMnemonic(options.mnemonic),
      provider
    );
  } else if (!signer) {
    throw Error(
      "Must provide private key or mnemonic, selected provider has no signer info."
    );
  }

  return signer;
}
