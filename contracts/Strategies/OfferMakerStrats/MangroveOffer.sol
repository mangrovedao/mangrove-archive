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

  receive() external payable {}

  // default values
  uint OFR_GASREQ = 1_000_000;
  uint OFR_GASPRICE;

  // Offer constructor (caller will be admin)
  constructor(address _MGV) {
    bytes32 global_pack = Mangrove(payable(_MGV)).global();
    (, , , uint __gasprice, uint __gasmax, uint __dead) =
      MgvPack.global_unpack(global_pack);
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
  ) public onlyAdmin returns (uint offerId) {
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
  ) public onlyAdmin {
    (OPTgasreq, OPTgasprice, OPTpivotId) = fillOptionalArgs(
      OPTgasreq,
      OPTgasprice,
      OPTpivotId
    );
    uint bounty =
      getProvision(base_erc20, quote_erc20, MGV, OPTgasreq, OPTgasprice);
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
    __lastLook__(order); // might revert or let the trade proceed
    __put__(IERC20(order.quote), order.gives); // specifies what to do with the received funds
    uint missingGet = __get__(IERC20(order.base), order.wants); // fetches `offer_gives` amount of `base` token as specified by the withdraw function
    if (missingGet > 0) {
      return
        returnData({
          drop: true,
          postHook_switch: PostHook.Get,
          arg: uint96(missingGet)
        });
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
    if (
      result.statusCode == "mgv/tradeSuccess" ||
      result.statusCode == "mgv/makerRevert"
    ) {
      // if trade was a success or dropped by maker, `makerData` determines the posthook switch
      (postHook_switch, args) = getMakerData(result.makerData);
    } else {
      // if `mgv` rejected trade, `statusCode` should determine the posthook switch
      postHook_switch = switchOfStatusCode(result.statusCode);
    }
    // posthook selector based on maker's information
    if (postHook_switch == PostHook.Success) {
      __postHookNoFailure__(order);
    }
    if (postHook_switch == PostHook.Get) {
      emit GetFailure(order.base, order.quote, order.offerId, args[0]);
      __postHookGetFailure__(args[0], order);
    }
    if (postHook_switch == PostHook.Price) {
      emit PriceSlippage(
        order.base,
        order.quote,
        order.offerId,
        args[0],
        args[1]
      );
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

  function __put__(IERC20 quote, uint amount) internal virtual {
    /// @notice receive payment is just stored at this address
    quote;
    amount;
  }

  function __get__(IERC20 base, uint amount) internal virtual returns (uint) {
    uint balance = base.balanceOf(address(this));
    return (balance > amount ? 0 : amount - balance);
  }

  function __lastLook__(MgvLib.SingleOrder calldata order) internal virtual {
    order; //shh
  }

  function __autoRefill__(uint amount) internal virtual {
    require(amount == 0, "Insufficient provision");
  }

  function __postHookNoFailure__(MgvLib.SingleOrder calldata order)
    internal
    virtual
  {
    order; //shh
  }

  function __postHookGetFailure__(
    uint missingGet,
    MgvLib.SingleOrder calldata order
  ) internal virtual {
    missingGet; //shh
    order; //shh
  }

  function __postHookPriceSlippage__(
    uint usd_maker_gives,
    uint usd_maker_wants,
    MgvLib.SingleOrder calldata order
  ) internal virtual {
    usd_maker_gives; //shh
    usd_maker_wants; //shh
    order; //shh
  }

  function __postHookReceiveFailure__(MgvLib.SingleOrder calldata order)
    internal
    virtual
  {
    order;
  }

  function __postHookTransferFailure__(MgvLib.SingleOrder calldata order)
    internal
    virtual
  {
    order;
  }
}
