// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma abicoder v2;
import {MgvCommon as MC} from "./MgvCommon.sol";

import {Mangrove} from "./Mangrove.sol";

contract MMgv is Mangrove {
  constructor(uint gasprice, uint gasmax) Mangrove(gasprice, gasmax, "FMD") {}

  function executeEnd(MultiOrder memory mor, MC.SingleOrder memory sor)
    internal
    override
  {}

  function executeCallback(MC.SingleOrder memory sor) internal override {}

  /* ## Flashloan */
  /*
     `flashloan` is for the 'normal' mode of operation. It:
     1. Flashloans `takerGives` `quote` from the taker to the maker and returns false if the loan fails.
     2. Runs `offerDetail.maker`'s `execute` function.
     3. Returns the result of the operations, with optional makerData to help the maker debug.
   */
  function flashloan(MC.SingleOrder calldata sor, address taker)
    external
    override
    returns (uint gasused)
  {
    /* `flashloan` must be used with a call (hence the `external` modifier) so its effect can be reverted. But a call from the outside would be fatal. */
    require(msg.sender == address(this), "mgv/flashloan/protected");
    /* The transfer taker -> maker is in 2 steps. First, taker->mgv. Then
       mgv->maker. With a direct taker->maker transfer, if one of taker/maker
       is blacklisted, we can't tell which one. We need to know which one:
       if we incorrectly blame the taker, a blacklisted maker can block a pair forever; if we incorrectly blame the maker, a blacklisted taker can unfairly make makers fail all the time. Of course we assume the Mangrove is not blacklisted. Also note that this setup doesn not work well with tokens that take fees or recompute balances at transfer time. */
    if (transferTokenFrom(sor.quote, taker, address(this), sor.gives)) {
      if (
        transferToken(
          sor.quote,
          $$(offerDetail_maker("sor.offerDetail")),
          sor.gives
        )
      ) {
        gasused = makerExecute(sor);
      } else {
        innerRevert([bytes32("mgv/makerReceiveFail"), bytes32(0), ""]);
      }
    } else {
      innerRevert([bytes32("mgv/takerFailToPayMaker"), "", ""]);
    }
  }
}
