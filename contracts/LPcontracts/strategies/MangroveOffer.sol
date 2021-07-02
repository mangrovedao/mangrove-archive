pragma solidity ^0.7.0;
pragma abicoder v2;
import "../lib/AccessControlled.sol";
import "../lib/Exponential.sol";
import "../lib/TradeHandler.sol";
import "../../Mangrove.sol";
import "../../MgvLib.sol";
import "../../MgvPack.sol";

// SPDX-License-Identifier: MIT

/// @title Basic structure of an offer to be posted on the Mangrove
/// @author Giry

contract MangroveOffer is AccessControlled, IMaker, TradeHandler, Exponential {
  Mangrove immutable MGV;

  receive() external payable {}

  constructor(address payable _MGV) {
    MGV = Mangrove(_MGV);
  }

  /// @notice transfers token stored in `this` contract to some recipient address
  function transferToken(
    address token,
    address recipient,
    uint amount
  ) external onlyAdmin returns (bool success) {
    success = IERC20(token).transfer(recipient, amount);
  }

  /// @notice extracts old offer from the order that is received from the Mangrove
  function unpackOfferFromOrder(MgvLib.SingleOrder calldata order)
    internal
    pure
    returns (
      uint offer_gives,
      uint offer_wants,
      uint gasreq,
      uint gasprice
    )
  {
    gasreq = MgvPack.offerDetail_unpack_gasreq(order.offerDetail);
    (, , offer_gives, offer_wants, gasprice) = MgvPack.offer_unpack(
      order.offer
    );
  }

  /// @title Mangrove basic interactions (logging is done by the Mangrove)

  /// @notice trader needs to approve the Mangrove to perform base token transfer at the end of the `makerExecute` function
  function approveMangrove(address base_erc20, uint amount) external onlyAdmin {
    require(IERC20(base_erc20).approve(address(MGV), amount));
  }

  /// @notice withdraws ETH from the bounty vault of the Mangrove.
  /// @notice `Mangrove.fund` function need not be called by `this` so is not included here.
  function withdraw(address receiver, uint amount)
    external
    onlyAdmin
    returns (bool noRevert)
  {
    require(MGV.withdraw(amount));
    require(receiver != address(0), "Cannot transfer WEIs to 0x0 address");
    (noRevert, ) = receiver.call{value: amount}("");
  }

  function post(
    address _base,
    address _quote,
    uint promised_base,
    uint quote_for_promised_base,
    uint _gasreq,
    uint _gasprice,
    uint _pivotId
  ) public onlyAdmin returns (uint offerId) {
    offerId = MGV.newOffer({
      base: _quote,
      quote: _base,
      gives: promised_base,
      wants: quote_for_promised_base,
      gasreq: _gasreq,
      gasprice: _gasprice,
      pivotId: _pivotId
    });
  }

  function getProvision(
    address base,
    address quote,
    uint gasreq,
    uint gasprice
  ) internal returns (uint) {
    ML.Config memory config = MGV.getConfig(base, quote);
    uint _gp;
    if (config.global.gasprice > gasprice) {
      _gp = uint(config.global.gasprice);
    } else {
      _gp = gasprice;
    }
    return ((gasreq +
      config.local.overhead_gasbase +
      config.local.offer_gasbase) *
      _gp *
      10**9);
  }

  // updates an existing offer on the Mangrove. `update` will throw if offer density is no longer compatible with Mangrove's parameters
  // `update` will also throw if user provision no longer covers for the offer's bounty. `__autoRefill__` function may be use to provide a method to refill automatically.
  function repost(
    address base_erc20,
    address quote_erc20,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId,
    uint offerId
  ) public onlyAdmin {
    uint bounty = getProvision(base_erc20, quote_erc20, gasreq, gasprice);
    uint provision = MGV.balanceOf(address(this));
    if (bounty > provision) {
      __autoRefill__(bounty - provision);
    }
    MGV.updateOffer(
      base_erc20,
      quote_erc20,
      wants,
      gives,
      gasreq,
      gasprice,
      pivotId,
      offerId
    );
  }

  function retract(
    address base_erc20,
    address quote_erc20,
    uint offerId,
    bool deprovision
  ) public onlyAdmin {
    MGV.retractOffer(base_erc20, quote_erc20, offerId, deprovision);
  }

  /////// Mandatory callback functions

  // not a virtual function to make sure it is only MGV callable
  function makerExecute(MgvLib.SingleOrder calldata order)
    external
    override
    onlyCaller(address(MGV))
    returns (bytes32 returnData)
  {
    __lastLook__(order); // might revert or let the trade proceed
    __put__(order.quote, order.gives); // specifies what to do with the received funds
    uint missingGet = __get__(order.base, order.wants); // fetches `offer_gives` amount of `base` token as specified by the withdraw function
    if (missingGet > 0) {
      return finalize({drop:true, postHook_switch:PostHook.Get, arg:uint96(missingGet)});
    }
    return finalize({drop:false, postHook_switch:PostHook.None});
  }

  // not a virtual function to make sure it is only MGV callable
  function makerPosthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata result
  ) external override onlyCaller(address(MGV)) {
    PostHook postHook_switch; 
    uint[] memory args;
    if ( result.statusCode == "mgv/tradeSuccess" || result.statusCode == "mgv/makerRevert") {
        // if trade was a success or dropped by maker, `makerData` determines the posthook switch
        (postHook_switch, args) = getMakerData(result.makerData);
    } else { // if `mgv` rejected trade, `statusCode` should determine the posthook switch
        postHook_switch = switchOfStatus(result.statusCode);
    }
    // posthook selector based on maker's information
    if (postHook_switch == PostHook.None) {
      __postHookNoFailure__(order);
    }
    if (postHook_switch == PostHook.Get) {
      emit GetFailure(order.base, order.quote, order.offerId, args[0]);
      __postHookGetFailure__(args[0],order);
    }
    if (postHook_switch == PostHook.Price) {
      emit PriceSlippage(order.base, order.quote, order.offerId, args[0], args[1]);
      __postHookPriceSlippage__(args[0], args[1], order);
    }
    // Posthook based on Mangrove's information
    if (postHook_switch == PostHook.Receive) {
      __postHookReceiveFailure__(order);
    }
    if (postHook_switch == PostHook.Transfer) {
      __postHookTransferFailure__(order);
    }
  }

  ////// Virtual functions to customize trading strategies

  function __put__(address quote, uint amount)
    internal
    virtual
  {
    /// @notice receive payment is just stored at this address
    quote;
    amount;
  }
  function __get__(address base, uint amount) internal virtual returns (uint) {
    uint balance = IERC20(base).balanceOf(address(this));
    return (balance > amount ? 0 : amount - balance);
  }
  function __lastLook__(MgvLib.SingleOrder calldata order) internal virtual {
    order; //shh
  }
  function __autoRefill__(uint amount) internal virtual {
    require(amount == 0, "Insufficient provision");
  }
  function __postHookNoFailure__(MgvLib.SingleOrder calldata order) internal virtual {
    order; //shh
  }
  function __postHookGetFailure__(uint missingGet, MgvLib.SingleOrder calldata order) internal virtual {
    missingGet; //shh
    order; //shh
  }
  function __postHookPriceSlippage__(uint usd_maker_gives, uint usd_maker_wants, MgvLib.SingleOrder calldata order)
  internal virtual {
    usd_maker_gives; //shh
    usd_maker_wants; //shh
    order; //shh
  }
  function __postHookReceiveFailure__(MgvLib.SingleOrder calldata order) internal virtual {
    order;
  }
  function __postHookTransferFailure__(MgvLib.SingleOrder calldata order) internal virtual {
    order;
  }
}
