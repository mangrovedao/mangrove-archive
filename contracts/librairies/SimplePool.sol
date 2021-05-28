pragma solidity ^0.7.0;
pragma abicoder v2;
import "./AccessControlled.sol";
import "./templates/Pooled.sol";
import "./templates/Persistent.sol";


contract SimplePool is Pooled, Persistent {
  uint fractional_reserve; // min amount of base token that should be reserved
  bytes32 constant INSUFFICIENTFUNDS = "InsufficientFunds";
  bytes32 constant INSUFFICIENTRESERVE = "InsufficientReserve";


  constructor(address payable mgv, address base_erc, uint _fractional_reserve)
  MangroveOffer(mgv,base_erc) {
    fractional_reserve = uint8(_fractional_reserve);
  }

  function setFractionalReserve(uint new_reserve) external onlyCaller(admin) {
    fractional_reserve = new_reserve;
  }

  /*** Offer management ***/


  /*** Trade settlement with the Mangrove ***/
  function makerTrade(MgvC.SingleOrder calldata order)
    external
    override
    onlyCaller(address(MGV))
    returns (bytes32){
      (TradeResult result, bytes32 new_balance) = __trade_checkLiquidity(order,address(this));
      if (result==TradeResult.Proceed) { // delta is liquidity left
        if (uint(new_balance) < fractional_reserve) {
          __trade_Revert(INSUFFICIENTRESERVE);
        }
        return new_balance;
      }
      __trade_Revert(INSUFFICIENTFUNDS);
    }

  function makerPosthook(
    MgvC.SingleOrder calldata order,
    MgvC.OrderResult calldata result
  ) external override onlyCaller(address(MGV)) {
    if (result.success) {
      __posthook_repostOfferAsIs(order);
    }
    else{
      if (result.makerData == INSUFFICIENTFUNDS) {
        log("InsufficientFunds");
      }
      else {
        log("InsufficientReserve");
      }
    }
  }
}
