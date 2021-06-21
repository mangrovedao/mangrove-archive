// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma abicoder v2;
import {ITaker, MgvLib as ML} from "./MgvLib.sol";

import {AbstractMangrove} from "./AbstractMangrove.sol";

contract InvertedMangrove is AbstractMangrove {
  constructor(uint gasprice, uint gasmax)
    AbstractMangrove(gasprice, gasmax, "FTD")
  {}

  // execute taker trade
  function executeEnd(MultiOrder memory mor, ML.SingleOrder memory sor)
    internal
    override
  {
    ITaker(mor.taker).takerTrade(
      sor.base,
      sor.quote,
      mor.totalGot,
      mor.totalGave
    );
    bool success =
      transferTokenFrom(sor.quote, mor.taker, address(this), mor.totalGave);
    require(success, "mgv/takerFailToPayMaker");
  }

  /* We use `transferFrom` with takers (instead of checking `balanceOf` before/after the call) for the following reason we want the taker to be awaken after all loans have been made, so either
     1. The taker gets a list of all makers and loops through them to pay back, or
     2. we call a new taker method "payback" after returning from each maker call, or
     3. we call transferFrom after returning from each maker call

So :
   1. Would mean accumulating a list of all makers, which would make the market order code too complex
   2. Is OK, but has an extra CALL cost on top of the token transfer, one for each maker. This is unavoidable anyway when calling makerTrade (since the maker must be able to execute arbitrary code at that moment), but we can skip it here.
   3. Is the cheapest, but it has the drawbacks of `transferFrom`: money must end up owned by the taker, and taker needs to `approve` Mangrove
   */
  function executeCallback(ML.SingleOrder memory sor) internal override {
    /* If `transferToken` returns false here, we're in a special (and bad) situation. The taker is returning part of their total loan to a maker, but the maker can't receive the tokens. Only case we can see: maker is blacklisted. We could punish maker. We don't. We could send money back to taker. We don't. */
    transferToken(
      sor.quote,
      $$(offerDetail_maker("sor.offerDetail")),
      sor.gives
    );
  }

  /* # Flashloans */
  //+clear+
  /* ## Inverted Flashloan */
  /*
     `invertedFlashloan` is for the 'arbitrage' mode of operation. It:
     0. Calls the maker's `execute` function. If successful (tokens have been sent to taker):
     2. Runs `taker`'s `execute` function.
     4. Returns the results ofthe operations, with optional makerData to help the maker debug.

     There are two ways to do the flashloan:
     1. balanceOf before/after
     2. run transferFrom ourselves.

     ### balanceOf pros:
       * maker may `transferFrom` another address they control; saves gas compared to Mangrove's `transferFrom`
       * maker does not need to `approve` Mangrove

     ### balanceOf cons
       * if the ERC20 transfer method has a callback to receiver, the method does not work (the receiver can set its balance to 0 during the callback)
       * if the taker is malicious, they can analyze the maker code. If the maker goes on any Mangrove2, they may execute code provided by the taker. This would reduce the taker balance and make the maker fail. So the taker could steal the maker's balance.

    We choose `transferFrom`.
    */

  function flashloan(ML.SingleOrder calldata sor, address)
    external
    override
    returns (uint gasused)
  {
    /* `invertedFlashloan` must be used with a call (hence the `external` modifier) so its effect can be reverted. But a call from the outside would be fatal. */
    require(msg.sender == address(this), "mgv/invertedFlashloan/protected");
    gasused = makerExecute(sor);
  }
}
