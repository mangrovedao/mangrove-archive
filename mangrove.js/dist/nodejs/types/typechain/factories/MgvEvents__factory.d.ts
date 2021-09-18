import { Signer } from "ethers";
import { Provider } from "@ethersproject/providers";
import type { MgvEvents, MgvEventsInterface } from "../MgvEvents";
export declare class MgvEvents__factory {
    static readonly abi: {
        anonymous: boolean;
        inputs: {
            indexed: boolean;
            internalType: string;
            name: string;
            type: string;
        }[];
        name: string;
        type: string;
    }[];
    static createInterface(): MgvEventsInterface;
    static connect(address: string, signerOrProvider: Signer | Provider): MgvEvents;
}
