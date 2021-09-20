/**
 * @file Mangrove
 * @desc This file defines the exports of the `mangrove.js` package.
 * @hidden
 */
import { ethers } from 'ethers';
import * as eth from './eth';
import { decimals } from './constants';
import { Mangrove } from './mangrove';
export default Mangrove;
export { eth, decimals, ethers, Mangrove };
