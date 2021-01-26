// SPDX-License-Identifier: UNLICENSED

/* # Introduction
Due to the 24kB contract size limit, we pay some additional complexity in the form of `DexLib`, to which `Dex` will delegate some calls. It notably includes configuration getters and setters, token transfer low-level functions, as well as the `writeOffer` machinery used by makers when they post new offers and update existing ones.
*/
pragma solidity ^0.7.0;
pragma abicoder v2;
import "./DexCommon.sol";
import "./interfaces.sol";
import {DexCommon as DC, DexEvents} from "./DexCommon.sol";

library DexLib {
  /* # Token transfer */
  //+clear+
  /*
     `flashloan` is for the 'normal' mode of operation. It:
     1. Flashloans `takerGives` `REQ_TOKEN` from the taker to the maker and returns false if the loan fails.
     2. Runs `offerDetail.maker`'s `execute` function.
     3. Returns the result of the operations, with optional makerData to help the maker debug.
   */
  function flashloan(DC.SingleOrder calldata sor)
    external
    returns (uint gasused)
  {
    /* the transfer from taker to maker must be in this function
       so that any issue with the maker also reverts the flashloan */
    if (
      transferToken(
        sor.quote,
        msg.sender,
        $$(od_maker("sor.offerDetail")),
        sor.gives
      )
    ) {
      gasused = makerExecute(sor);
    } else {
      innerRevert([bytes32("dex/takerFailToPayMaker"), "", ""]);
    }
  }

  /*
     `invertedFlashloan` is for the 'arbitrage' mode of operation. It:
     0. Calls the maker's `execute` function. If successful (tokens have been sent to taker):
     2. Runs `msg.sender`'s `execute` function.
     4. Returns the results ofthe operations, with optional makerData to help the maker debug.

     There are two ways to do the flashloan:
     1. balanceOf before/after
     2. run transferFrom ourselves.

     ### balanceOf pros:
       * maker may `transferFrom` another address they control; saves gas compared to dex's `transferFrom`
       * maker does not need to `approve` dex
     ### balanceOf cons
       * if the ERC20 transfer method has a callback to receiver, the method does not work (the receiver can set its balance to 0 during the callback)
       * costs more gas to do 2 SLOADS (checking balanceOf twice) than to run the `transfer` ourselves -- if there's only one transfer.
    */

  function invertedFlashloan(DC.SingleOrder calldata sor)
    external
    returns (uint gasused)
  {
    gasused = makerExecute(sor);
  }

  function makerExecute(DC.SingleOrder calldata sor)
    internal
    returns (uint gasused)
  {
    bytes memory cd =
      abi.encodeWithSelector(IMaker.makerTrade.selector, sor, msg.sender);

    uint oldBalance = IERC20(sor.base).balanceOf(msg.sender);
    /* If the transfer would trigger an overflow, we blame the taker. Since sor.wants is `min(takerWants,offer.gives)`, the taker cannot be tricked into overflow by a maker. This check must be done before the callto maker because an overflow-trggering ERC20 transfer could throw and result in an unjust maker failure. */
    if (oldBalance + sor.wants < oldBalance) {
      innerRevert([bytes32("dex/tradeOverflow"), "", ""]);
    }
    /* Calls an external function with controlled gas expense. A direct call of the form `(,bytes memory retdata) = maker.call{gas}(selector,...args)` enables a griefing attack: the maker uses half its gas to write in its memory, then reverts with that memory segment as argument. After a low-level call, solidity automaticaly copies `returndatasize` bytes of `returndata` into memory. So the total gas consumed to execute a failing offer could exceed `gasreq + gasbase`. This yul call only retrieves the first byte of the maker's `returndata`. */
    uint gasreq = $$(od_gasreq("sor.offerDetail"));
    address maker = $$(od_maker("sor.offerDetail"));
    bytes memory retdata = new bytes(32);
    bool success;
    bytes32 makerData;
    uint oldGas = gasleft();
    /* We let the maker pay for the overhead of checking remaining gas and making the call. So the `require` below is just an approximation: if the overhead of (`require` + cost of CALL) is $$h$$, the maker will receive at worst $$\textrm{gasreq} - \frac{63h}{64}$$ gas. */
    /* Note : as a possible future feature, we could stop an order when there's not enough gas left to continue processing offers. This could be done safely by checking, as soon as we start processing an offer, whether 63/64(gasleft-gasbase) > gasreq. If no, we'd know by induction that there is enough gas left to apply fees, stitch offers, etc (or could revert safely if no offer has been taken yet). */
    if (!(oldGas - oldGas / 64 >= gasreq)) {
      innerRevert([bytes32("dex/notEnoughGasForMakerTrade"), "", ""]);
    }

    assembly {
      success := call(
        gasreq,
        maker,
        0,
        add(cd, 32),
        mload(cd),
        add(retdata, 32),
        32
      )
      makerData := mload(add(retdata, 32))
    }
    gasused = oldGas - gasleft();
    // An example why this is not safe if ERC20 has a callback:
    // https://peckshield.medium.com/akropolis-incident-root-cause-analysis-c11ee59e05d4
    uint newBalance = IERC20(sor.base).balanceOf(msg.sender);
    /* oldBalance + sor.wants cannot overflow thanks to earlier check */
    /* `msg.sender == maker` balance might be invariant*/
    if (!success) {
      innerRevert([bytes32("dex/makerRevert"), bytes32(gasused), makerData]);
    } else if (
      (newBalance >= oldBalance + sor.wants) || (msg.sender == maker)
    ) {
      // ok
    } else {
      innerRevert(
        [bytes32("dex/makerTransferFail"), bytes32(gasused), makerData]
      );
    }
  }

  function innerRevert(bytes32[3] memory data) internal pure {
    assembly {
      revert(data, 96)
    }
  }

  /* `transferToken` is adapted from [existing code](https://soliditydeveloper.com/safe-erc20) and in particular avoids the
  "no return value" bug. It never throws and returns true iff the transfer was successful according to `tokenAddress`.

    Note that any spurious exception due to an error in Dex code will be falsely blamed on `from`.
  */
  function transferToken(
    address tokenAddress,
    address from,
    address to,
    uint value
  ) internal returns (bool) {
    bytes memory cd =
      abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value);
    (bool noRevert, bytes memory data) = tokenAddress.call(cd);
    return (noRevert && (data.length == 0 || abi.decode(data, (bool))));
  }

  /* # New offer */
  //+clear+

  /* <a id="DexLib/definition/newOffer"></a> When a maker posts a new offer or updates an existing one, the offer gets automatically inserted at the correct location in the book, starting from a maker-supplied `pivotId` parameter. The extra `storage` parameters are sent to `DexLib` by `Dex` so that it can write to `Dex`'s storage.

  Code in this function is weirdly structured; this is necessary to avoid "stack too deep" errors.

  */
}
