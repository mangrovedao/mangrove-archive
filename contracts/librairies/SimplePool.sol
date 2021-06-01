pragma solidity ^0.7.0;
pragma abicoder v2;
import "./AccessControlled.sol";
import "./templates/Pooled.sol";
import "./templates/Persistent.sol";

contract SimplePool is Pooled, Persistent {
  uint reserve_limit; // min amount of base token that should be reserved
  bytes32 constant ERRORRESERVE = "ErrorReserve";
  bytes32 constant ERRORFUND = "ErrorFund";

  constructor(
    address payable mgv,
    address base_erc,
    uint _reserve_limit
  ) MangroveOffer(mgv, base_erc) {
    reserve_limit = _reserve_limit;
  }

  function setReserveLimit(uint new_limit) external onlyCaller(admin) {
    reserve_limit = new_limit;
  }

  /*** Offer management ***/

  /*** Trade settlement with the Mangrove ***/
  function makerTrade(MgvC.SingleOrder calldata order)
    external
    override
    onlyCaller(MGV)
    returns (bytes32)
  {
    (TradeResult result, bytes32 new_balance) = __trade_checkLiquidity(order);
    if (result == TradeResult.Proceed) {
      // delta is liquidity left
      if (uint(new_balance) < reserve_limit) {
        __trade_Revert(ERRORRESERVE); // for insufficient reserve
      }
      return new_balance; // Let the Mangrove try the transfer
    }
    __trade_Revert(ERRORFUND); // for insufficient funds
  }

  function makerPosthook(
    MgvC.SingleOrder calldata order,
    MgvC.OrderResult calldata result
  ) external override onlyCaller(MGV) {
    if (result.success) {
      __posthook_repostOfferAsIs(order);
    } else {
      //trade was dropped
      if (result.makerData == ERRORRESERVE) {
        log("InsufficientReserve");
      } else {
        log("InsufficientFunds");
      }
    }
  }
}
