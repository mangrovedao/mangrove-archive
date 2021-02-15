// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import {DexCommon as DC} from "./DexCommon.sol";
import "./Dex.sol";

library DexIt {
  // Read a particular offer's information.

  /*To be used to revert a makerTrade function with data to pass to posthook */
  function tradeRevert(bytes32 data) internal {
    bytes memory revData = new bytes(32);
    assembly {
      mstore(add(revData, 32), data)
      revert(add(revData, 32), 32)
    }
  }
}
