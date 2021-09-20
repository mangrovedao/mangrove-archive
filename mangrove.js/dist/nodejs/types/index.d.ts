import { Signer as AbstractSigner } from '@ethersproject/abstract-signer/lib/index';
import { FallbackProvider } from '@ethersproject/providers/lib/fallback-provider';
import { BlockTag, TransactionRequest, TransactionResponse } from '@ethersproject/abstract-provider';
import { Deferrable } from '@ethersproject/properties';
import { BigNumber } from '@ethersproject/bignumber/lib/bignumber';
import type { Awaited, MarkOptional } from 'ts-essentials';
import type { Big } from 'big.js';
import { MgvReader, Mangrove } from './typechain';
declare type _bookReturns = Awaited<ReturnType<MgvReader["functions"]["book"]>>;
export declare type bookReturns = {
    indices: _bookReturns[0];
    offers: _bookReturns[1];
    details: _bookReturns[2];
};
export declare type internalConfig = Awaited<ReturnType<Mangrove["functions"]["config"]>>["ret"];
export declare type localConfig = {
    active: boolean;
    fee: number;
    density: number;
    overhead_gasbase: number;
    offer_gasbase: number;
    lock: boolean;
    best: number;
    last: number;
};
export declare type Offer = {
    prev: number;
    next: number;
    volume: Big;
    price: Big;
    gives: Big;
    wants: Big;
    overhead_gasbase: number;
    offer_gasbase: number;
    maker: string;
    gasreq: number;
    gasprice: number;
};
export interface ConnectOptions {
    privateKey?: string;
    mnemonic?: string;
    provider?: Provider | string;
}
export interface AbiType {
    internalType?: string;
    name?: string;
    type?: string;
    components?: AbiType[];
}
export interface AbiItem {
    constant?: boolean;
    inputs?: AbiType[];
    name?: string;
    outputs?: AbiType[];
    payable?: boolean;
    stateMutability?: string;
    type?: string;
}
export interface CallOptions {
    _compoundProvider?: Provider;
    abi?: string | string[] | AbiItem[];
    provider?: Provider | string;
    network?: string;
    from?: number | string;
    gasPrice?: number;
    gasLimit?: number;
    value?: number | string | BigNumber;
    data?: number | string;
    chainId?: number;
    nonce?: number;
    privateKey?: string;
    mnemonic?: string;
    mantissa?: boolean;
    blockTag?: number | string;
}
export interface Connection {
    url?: string;
}
export interface Network {
    chainId: number;
    name: string;
}
export interface ProviderNetwork {
    id?: number;
    name?: string;
}
declare type GenericGetBalance = (addressOrName: string | number | Promise<string | number>, blockTag?: string | number | Promise<string | number>) => Promise<BigNumber>;
declare type GenericGetTransactionCount = (addressOrName: string | number | Promise<string>, blockTag?: BlockTag | Promise<BlockTag>) => Promise<number>;
declare type GenericSendTransaction = (transaction: string | Promise<string> | Deferrable<TransactionRequest>) => Promise<TransactionResponse>;
export interface Provider extends AbstractSigner, FallbackProvider {
    connection?: Connection;
    _network: Network;
    call: AbstractSigner['call'] | FallbackProvider['call'];
    getBalance: GenericGetBalance;
    getTransactionCount: GenericGetTransactionCount;
    resolveName: AbstractSigner['resolveName'] | FallbackProvider['resolveName'];
    sendTransaction: GenericSendTransaction;
    send?: (method: string, parameters: string[]) => any;
}
export interface APIResponse {
    error?: string;
    responseCode?: number;
    responseMessage?: string;
}
export interface precise {
    value: string;
}
export interface AccountServiceRequest {
    addresses?: string[] | string;
    min_borrow_value_in_eth?: precise;
    max_health?: precise;
    block_number?: number;
    block_timestamp?: number;
    page_size?: number;
    page_number?: number;
    network?: string;
}
export interface CTokenServiceRequest {
    addresses?: string[] | string;
    block_number?: number;
    block_timestamp?: number;
    meta?: boolean;
    network?: string;
}
export interface MarketHistoryServiceRequest {
    asset?: string;
    min_block_timestamp?: number;
    max_block_timestamp?: number;
    num_buckets?: number;
    network?: string;
}
export interface GovernanceServiceRequest {
    proposal_ids?: number[];
    state?: string;
    with_detail?: boolean;
    page_size?: number;
    page_number?: number;
    network?: string;
}
export declare type APIRequest = AccountServiceRequest | CTokenServiceRequest | MarketHistoryServiceRequest | GovernanceServiceRequest;
export interface Signature {
    r: string;
    s: string;
    v: string;
}
export interface EIP712Type {
    name: string;
    type: string;
}
export interface EIP712Domain {
    name: string;
    chainId: number;
    verifyingContract: string;
}
export interface VoteTypes {
    EIP712Domain: EIP712Type[];
    Ballot: EIP712Type[];
}
export interface DelegateTypes {
    EIP712Domain: EIP712Type[];
    Delegation: EIP712Type[];
}
export declare type EIP712Types = VoteTypes | DelegateTypes;
export interface DelegateSignatureMessage {
    delegatee: string;
    nonce: number;
    expiry: number;
}
export interface VoteSignatureMessage {
    proposalId: number;
    support: number;
}
export declare type EIP712Message = DelegateSignatureMessage | VoteSignatureMessage;
interface SimpleEthersProvider {
    jsonRpcFetchFunc(method: string, parameters: any[]): any;
}
export interface SimpleEthersSigner {
    _signingKey(): any;
    getAddress(): any;
    provider?: SimpleEthersProvider;
}
export interface TokenInfo {
    name: string;
    address: string;
    decimals: number;
}
export interface MarketParams {
    base: string | MarkOptional<TokenInfo, "address" | "decimals">;
    quote: string | MarkOptional<TokenInfo, "address" | "decimals">;
}
export declare type Bigish = Big | number | string;
export declare type TradeParams = {
    volume: Bigish;
    price: Bigish;
} | {
    wants: Bigish;
    gives: Bigish;
};
export {};
