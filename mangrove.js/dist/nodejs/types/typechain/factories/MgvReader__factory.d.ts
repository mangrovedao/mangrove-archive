import { Signer } from "ethers";
import { Provider } from "@ethersproject/providers";
import type { MgvReader, MgvReaderInterface } from "../MgvReader";
export declare class MgvReader__factory {
    static readonly abi: ({
        inputs: {
            internalType: string;
            name: string;
            type: string;
        }[];
        stateMutability: string;
        type: string;
        name?: undefined;
        outputs?: undefined;
    } | {
        inputs: {
            internalType: string;
            name: string;
            type: string;
        }[];
        name: string;
        outputs: ({
            internalType: string;
            name: string;
            type: string;
            components?: undefined;
        } | {
            components: {
                internalType: string;
                name: string;
                type: string;
            }[];
            internalType: string;
            name: string;
            type: string;
        })[];
        stateMutability: string;
        type: string;
    })[];
    static createInterface(): MgvReaderInterface;
    static connect(address: string, signerOrProvider: Signer | Provider): MgvReader;
}
