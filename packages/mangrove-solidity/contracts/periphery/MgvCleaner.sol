// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
import "../Mangrove.sol";

/* The purpose of the Cleaner contract is to execute failing offers and collect
 * their associated bounty. It takes an array of offers with same definition as
 * `Mangrove.snipes` and expects them all to fail or not execute. */

/* How to use:
   1) Ensure *your* address approved Mangrove for the token you will provide to the offer (`inbound_tkn`).
   2) Run `collect` on the offers that you detected were failing.

   You can adjust takerWants/takerGives and gasreq as needed.

   Note: in the current version you do not need to set MgvCleaner's allowance in Mangrove.
   TODO: add `collectWith` with an additional `taker` argument.
*/
contract MgvCleaner {
  AbstractMangrove immutable MGV;

  constructor(AbstractMangrove _MGV) {
    MGV = _MGV;
  }

  receive() external payable {}

  function collect(
    address outbound_tkn,
    address inbound_tkn,
    uint[4][] calldata targets,
    bool fillWants
  ) external returns (uint bal) {
    (uint successes, , ) = MGV.snipesFor(
      outbound_tkn,
      inbound_tkn,
      targets,
      fillWants,
      msg.sender
    );
    require(successes == 0, "mgvCleaner/anOfferDidNotFail");
    bal = address(this).balance;
    msg.sender.send(bal);
  }
}
