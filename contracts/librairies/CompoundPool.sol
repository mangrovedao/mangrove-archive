pragma solidity ^0.7.0;
pragma abicoder v2;
import "./AccessControlled.sol";
import "./templates/Pooled.sol";
import "./templates/Persistent.sol";
import "./templates/CapitalEfficient.sol";
import "./templates/MangroveOffer.sol";

contract CompoundPool is MangroveOffer, Pooled, Persistent, CompoundSourced {
  mapping(address => address) public overlyingAdresses;

  constructor(
    address payable mgv,
    address base_erc,
    address base_cErc
  ) MangroveOffer(mgv, base_erc) CompoundSourced(base_cErc) {
    require(IcERC20(base_cErc).underlying() == base_erc);
  }

  function setOverlyingAddress(address erc20, address cErc20)
    external
    onlyCaller(admin)
  {
    overlyingAdresses[erc20] = cErc20;
  }

  function getOverlyingAddress(address erc20) public returns (address) {
    return (overlyingAdresses[erc20]);
  }

  /*** Offer management ***/

  /// @notice callback function for Trade settlement with the Mangrove
  /// @notice caller MUST be `MGV`
  function makerTrade(MgvC.SingleOrder calldata order)
    external
    override
    onlyCaller(MGV)
    returns (bytes32)
  {
    // placing received quote into compound if possible
    address cQuote = getOverlyingAddress(order.quote);
    if (cQuote != address(0) || !supplyErc20ToCompound(cQuote, order.gives)) {
      log("Failed to supply quote token to compound");
    }
    // fetch liquidity from Compound if necessary
    (TradeResult result, bytes32 data) = trade_checkLiquidity(order);
    if (result == TradeResult.Proceed) {
      // enough liquidity immediately available
      return "FromPool";
    } else {
      // data contains missing liquidity
      uint missing_amount = uint(data);
      (result, data) = trade_redeemCompoundBase(missing_amount); // tries to fetch redeem required base from compound
      if (result == TradeResult.Proceed) {
        return "FromCompound";
      }
      trade_revert(bytes32(missing_amount));
    }
  }

  /// @notice callback function after the execution of makerTrade
  /// @notice caller MUST be `MGV`
  function makerPosthook(
    MgvC.SingleOrder calldata order,
    MgvC.OrderResult calldata result
  ) external override onlyCaller(MGV) {}
}
