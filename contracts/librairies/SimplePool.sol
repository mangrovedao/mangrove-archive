pragma solidity ^0.7.0;
pragma abicoder v2;
import "./AccessControlled.sol";
import "./templates/Persistent.sol";

contract SimplePool is MangroveOffer, Persistent {
  constructor(address payable mgv, address base_erc)
    MangroveOffer(mgv, base_erc)
  {}

  /*** Offer management ***/

  /// @notice callback function for Trade settlement with the Mangrove
  /// @notice caller MUST be `MGV`
  function makerTrade(MgvC.SingleOrder calldata order)
    external
    view
    override
    onlyCaller(MGV)
    returns (bytes32)
  {
    (TradeResult result, bytes32 balance) = trade_checkLiquidity(order);
    if (result == TradeResult.Proceed) {
      /** @dev balance is liquidity left */
      return balance; /** @dev This tells the Mangrove to proceed with the trade */
    } else {
      trade_revert(balance); /** @dev This tells the Mangrove that trade has failed (so she must not attempt to transfer funds) */
    }
  }

  /// @notice callback function after the execution of makerTrade
  /// @notice caller MUST be `MGV`
  function makerPosthook(
    MgvC.SingleOrder calldata order,
    MgvC.OrderResult calldata result
  ) external override onlyCaller(MGV) {
    if (result.success) {
      uint balanceLeft = uint(result.makerData);
      (, uint gives, , ) = getStoredOffer(order);
      if (balanceLeft >= gives) {
        posthook_repostOfferAsIs(order); /** @dev reposts offer on the Mangrove at the same price */
      }
    }
  }
}
