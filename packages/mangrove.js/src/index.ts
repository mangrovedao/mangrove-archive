/**
 * @file Mangrove
 * @desc This file defines the exports of the `mangrove.js` package.
 * @hidden
 */

import { ethers } from 'ethers';
import * as eth from './eth';
import { decimals } from './constants';

import {Mangrove} from './mangrove';

// Turn off Ethers.js warnings
// ethers.utils.Logger.setLogLevel(ethers.utils.Logger.levels.ERROR);


export default Mangrove
export {eth,decimals,ethers,Mangrove}
