// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma abicoder v2;
import {MgvLib as ML} from "./MgvLib.sol";

import {MgvOfferMaking} from "./MgvOfferMaking.sol";
import {MgvOfferTakingWithPermit} from "./MgvOfferTakingWithPermit.sol";
import {MgvGovernable} from "./MgvGovernable.sol";

abstract contract AbstractMangrove is
  MgvGovernable,
  MgvOfferTakingWithPermit,
  MgvOfferMaking
{
  constructor(
    uint gasprice,
    uint gasmax,
    string memory contractName
  ) MgvOfferTakingWithPermit(contractName) MgvGovernable(gasprice, gasmax) {}
}
