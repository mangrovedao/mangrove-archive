// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

library MgvIt {
  // Read a particular offer's information.

  /*To be used to revert a makerTrade function with data to pass to posthook */
  function tradeRevert(bytes32 data) internal pure {
    bytes memory revData = new bytes(32);
    assembly {
      mstore(add(revData, 32), data)
      revert(add(revData, 32), 32)
    }
  }
}
