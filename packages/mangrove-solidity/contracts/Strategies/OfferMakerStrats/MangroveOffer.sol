pragma solidity ^0.7.0;
pragma abicoder v2;
import "../lib/AccessControlled.sol";
import "../lib/Exponential.sol";
import "../lib/TradeHandler.sol";

//import "hardhat/console.sol";

// SPDX-License-Identifier: MIT

/// MangroveOffer is the basic building block to implement a reactive offer that interfaces with the Mangrove
contract MangroveOffer is AccessControlled, IMaker, TradeHandler, Exponential {
  Mangrove immutable MGV;
  uint immutable MGV_GASMAX;

  event NewMakerContract(address mgv);
  event Fallback(string message);

  receive() external payable {}

  // default values
  uint OFR_GASREQ = 1_000_000;
  uint OFR_GASPRICE;

  // Offer constructor (caller will be admin)
  constructor(address _MGV) {
    bytes32 global_pack = Mangrove(payable(_MGV)).global();
    (, , , uint __gasprice, uint __gasmax, uint __dead) = MgvPack.global_unpack(
      global_pack
    );
    require(__dead == 0, "Mangrove contract is permanently disabled"); //sanity check
    MGV = Mangrove(payable(_MGV));
    MGV_GASMAX = __gasmax;
    OFR_GASPRICE = __gasprice;
    emit NewMakerContract(_MGV);
  }

  /// transfers token stored in `this` contract to some recipient address
  function transferToken(
    address token,
    address recipient,
    uint amount
  ) external onlyAdmin returns (bool success) {
    success = IERC20(token).transfer(recipient, amount);
  }

  //queries the mangrove to get current gasprice (considered to compute bounty)
  function getCurrentGasPrice() public view returns (uint) {
    bytes32 global_pack = Mangrove(MGV).global();
    (, , , uint __gasprice, , ) = MgvPack.global_unpack(global_pack);
    return __gasprice;
  }

  // updates state variables
  function udpateGasPrice(uint gasprice) external onlyAdmin {
    OFR_GASPRICE = gasprice;
  }

  function udpateGasPrice() external onlyAdmin {
    OFR_GASPRICE = getCurrentGasPrice();
  }

  function updateGasReq(uint gasreq) external onlyAdmin {
    OFR_GASREQ = gasreq;
  }

  /// trader needs to approve the Mangrove to perform base token transfer at the end of the `makerExecute` function
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

  function fillOptionalArgs(
    uint gasreq,
    uint gasprice,
    uint pivotId
  )
    private
    view
    returns (
      uint,
      uint,
      uint
    )
  {
    if (gasreq == MAXUINT) {
      gasreq = OFR_GASREQ;
    }
    if (gasprice == MAXUINT) {
      gasprice = OFR_GASPRICE;
    }
    if (pivotId == MAXUINT) {
      pivotId = 0;
    }
    return (gasreq, gasprice, pivotId);
  }

  function newOffer(
    address base,
    address quote,
    uint promised_base,
    uint quote_for_promised_base,
    uint OPTgasreq,
    uint OPTgasprice,
    uint OPTpivotId
  ) external onlyAdmin returns (uint offerId) {
    offerId = newOfferInternal(
      base,
      quote,
      promised_base,
      quote_for_promised_base,
      OPTgasreq,
      OPTgasprice,
      OPTpivotId
    );
  }

  function newOfferInternal(
    address base,
    address quote,
    uint promised_base,
    uint quote_for_promised_base,
    uint OPTgasreq,
    uint OPTgasprice,
    uint OPTpivotId
  ) internal returns (uint offerId) {
    (OPTgasreq, OPTgasprice, OPTpivotId) = fillOptionalArgs(
      OPTgasreq,
      OPTgasprice,
      OPTpivotId
    );
    offerId = MGV.newOffer({
      base: base,
      quote: quote,
      gives: promised_base,
      wants: quote_for_promised_base,
      gasreq: OPTgasreq,
      gasprice: OPTgasprice,
      pivotId: OPTpivotId
    });
  }

  // updates an existing offer on the Mangrove. `update` will throw if offer density is no longer compatible with Mangrove's parameters
  // `update` will also throw if user provision no longer covers for the offer's bounty. `__autoRefill__` function may be use to provide a method to refill automatically.
  function updateOffer(
    address base_erc20,
    address quote_erc20,
    uint wants,
    uint gives,
    uint OPTgasreq,
    uint OPTgasprice,
    uint OPTpivotId,
    uint offerId
  ) external onlyAdmin {
    updateOfferInternal(
      base_erc20,
      quote_erc20,
      wants,
      gives,
      OPTgasreq,
      OPTgasprice,
      OPTpivotId,
      offerId
    );
  }

  function updateOfferInternal(
    address base_erc20,
    address quote_erc20,
    uint wants,
    uint gives,
    uint OPTgasreq,
    uint OPTgasprice,
    uint OPTpivotId,
    uint offerId
  ) internal {
    (OPTgasreq, OPTgasprice, OPTpivotId) = fillOptionalArgs(
      OPTgasreq,
      OPTgasprice,
      OPTpivotId
    );
    uint bounty = getProvision(
      base_erc20,
      quote_erc20,
      MGV,
      OPTgasreq,
      OPTgasprice
    );
    uint provision = MGV.balanceOf(address(this));
    if (bounty > provision) {
      __autoRefill__(bounty - provision);
    }
    MGV.updateOffer(
      base_erc20,
      quote_erc20,
      wants,
      gives,
      OPTgasreq,
      OPTgasprice,
      OPTpivotId,
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
    returns (bytes32)
  {
    bool proceed = __lastLook__(order); // might revert or let the trade proceed
    if (!proceed) {
      returnData({drop: true, postHook_switch: PostHook.Reneged});
    }
    __put__(IERC20(order.quote), order.gives); // specifies what to do with the received funds
    uint missingGet = __get__(IERC20(order.base), order.wants); // fetches `offer_gives` amount of `base` token as specified by the withdraw function
    if (missingGet > 0) {
      return returnData({drop: true, postHook_switch: PostHook.Get});
    }
    return returnData({drop: false, postHook_switch: PostHook.Success});
  }

  // not a virtual function to make sure it is only MGV callable
  function makerPosthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata result
  ) external override onlyCaller(address(MGV)) {
    PostHook postHook_switch;
    uint[] memory args;
    bytes32 word;
    if (
      result.statusCode == "mgv/tradeSuccess" ||
      result.statusCode == "mgv/makerRevert"
    ) {
      // if trade was a success or dropped by maker, `makerData` determines the posthook switch
      (postHook_switch, word) = getMakerData(result.makerData);
    }
    // posthook selector based on maker's information
    if (postHook_switch == PostHook.Success) {
      __postHookSuccess__(word, order);
      return;
    }
    if (postHook_switch == PostHook.Get) {
      __postHookGetFailure__(word, order);
      return;
    }
    if (postHook_switch == PostHook.Reneged) {
      __postHookReneged__(word, order);
      return;
    }
    if (postHook_switch == PostHook.Fallback) {
      __postHookFallback__(word, order);
      return;
    } else {
      // if `mgv` rejected trade, `statusCode` is the argument given to fallback posthook
      __postHookFallback__(result.statusCode, order);
    }
  }

  ////// Virtual functions to customize trading strategies

  function __put__(IERC20 quote, uint amount) internal virtual {
    /// @notice receive payment is just stored at this address
    quote;
    amount;
  }

  function __get__(IERC20 base, uint amount) internal virtual returns (uint) {
    uint balance = base.balanceOf(address(this));
    return (balance > amount ? 0 : amount - balance);
  }

  function __lastLook__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    returns (bool)
  {
    order; //shh
    return true;
  }

  function __autoRefill__(uint amount) internal virtual {
    require(amount == 0, "Insufficient provision");
  }

  function __postHookSuccess__(
    bytes32 message,
    MgvLib.SingleOrder calldata order
  ) internal virtual {
    message;
    order; //shh
  }

  function __postHookGetFailure__(
    bytes32 message,
    MgvLib.SingleOrder calldata order
  ) internal virtual {
    message; //shh
    order; //shh
  }

  function __postHookReneged__(
    bytes32 message,
    MgvLib.SingleOrder calldata order
  ) internal virtual {
    message;
    order; //shh
  }

  function __postHookFallback__(
    bytes32 message,
    MgvLib.SingleOrder calldata order
  ) internal virtual {
    message; //shh
    order; //shh
  }
}
