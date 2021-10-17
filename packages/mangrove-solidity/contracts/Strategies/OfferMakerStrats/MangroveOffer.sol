pragma solidity ^0.7.0;
pragma abicoder v2;
import "../lib/AccessControlled.sol";
import "../lib/Exponential.sol";
import "../lib/TradeHandler.sol";
import {MgvReader as MR} from "../../periphery/MgvReader.sol";

import "hardhat/console.sol";

// SPDX-License-Identifier: MIT

/// MangroveOffer is the basic building block to implement a reactive offer that interfaces with the Mangrove
contract MangroveOffer is AccessControlled, IMaker, TradeHandler, Exponential {
  Mangrove immutable MGV;
  uint immutable MGV_GASMAX;

  event PostHookError(address outbound_tkn, address inbound_tkn, uint offerId);

  receive() external payable {}

  // default values
  uint public OFR_GASREQ = 1_000_000;
  uint public OFR_GASPRICE;

  // Offer constructor (caller will be admin)
  constructor(address _MGV) {
    (bytes32 global_pack, ) = Mangrove(payable(_MGV))._config(
      address(0),
      address(0)
    );
    (, , , uint __gasprice, uint __gasmax, uint __dead) = MP.global_unpack(
      global_pack
    );
    require(__dead == 0, "Mangrove contract is permanently disabled"); //sanity check
    MGV = Mangrove(payable(_MGV));
    MGV_GASMAX = __gasmax;
    OFR_GASPRICE = __gasprice;
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
    (bytes32 global_pack, ) = Mangrove(MGV)._config(address(0), address(0));
    return MP.global_unpack_gasprice(global_pack);
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
  function approveMangrove(address outbound_tkn, uint amount)
    external
    onlyAdmin
  {
    require(
      IERC20(outbound_tkn).approve(address(MGV), amount),
      "Failed to approve Mangrove"
    );
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

  function newOffer(
    address outbound_tkn,
    address inbound_tkn,
    uint wants, //wants
    uint gives, //gives
    uint gasreq,
    uint gasprice,
    uint pivotId
  ) external internalOrAdmin returns (uint offerId) {
    if (gasreq == uint(-1)) {
      gasreq = OFR_GASREQ;
    }
    if (gasprice == uint(-1)) {
      gasprice = OFR_GASPRICE;
    }
    return
      MGV.newOffer(
        outbound_tkn,
        inbound_tkn,
        wants, //wants
        gives, //gives
        gasreq,
        gasprice,
        pivotId
      );
  }

  // updates an existing offer on the Mangrove. `update` will throw if offer density is no longer compatible with Mangrove's parameters
  // `update` will also throw if user provision no longer covers for the offer's bounty. `__autoRefill__` function may be use to provide a method to refill automatically.
  function updateOffer(
    address outbound_tkn,
    address inbound_tkn,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId,
    uint offerId
  ) external internalOrAdmin {
    MGV.updateOffer(
      outbound_tkn,
      inbound_tkn,
      wants,
      gives,
      gasreq,
      gasprice,
      pivotId,
      offerId
    );
  }

  function retractOffer(
    address outbound_tkn,
    address inbound_tkn,
    uint offerId,
    bool deprovision
  ) external internalOrAdmin {
    MGV.retractOffer(outbound_tkn, inbound_tkn, offerId, deprovision);
  }

  /////// Mandatory callback functions

  // not a virtual function to make sure it is only MGV callable
  function makerExecute(MgvLib.SingleOrder calldata order)
    external
    override
    onlyCaller(address(MGV))
    returns (bytes32)
  {
    if (!__lastLook__(order)) {
      return RENEGED;
    }
    __put__(IERC20(order.inbound_tkn), order.gives); // specifies what to do with the received funds
    uint missingGet = __get__(IERC20(order.outbound_tkn), order.wants); // fetches `offer_gives` amount of `outbound_tkn` token as specified by the withdraw function
    if (missingGet > 0) {
      return OUTOFLIQUIDITY;
    }
    return PROCEED;
  }

  // not a virtual function to make sure it is only MGV callable
  // TODO deal properly with posthook selection
  function makerPosthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata result
  ) external override onlyCaller(address(MGV)) {
    if (result.mgvData == "mgv/tradeSuccess") {
      // if trade was a success
      __postHookSuccess__(order);
      return;
    }
    // if trade was cancelled by offer maker
    if (result.makerData == OUTOFLIQUIDITY) {
      __postHookGetFailure__(order);
      return;
    }
    if (result.makerData == RENEGED) {
      __postHookReneged__(order);
      return;
    }
    __postHookFallback__(order, result);
    return;
  }

  ////// Virtual functions to customize trading strategies

  function __put__(IERC20 inbound_tkn, uint amount) internal virtual {
    /// @notice receive payment is just stored at this address
    inbound_tkn;
    amount;
  }

  function __get__(IERC20 outbound_tkn, uint amount)
    internal
    virtual
    returns (uint)
  {
    uint balance = outbound_tkn.balanceOf(address(this));
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

  // Post-hook tries to repost residual offer (if any) at the same price
  // Logs MangroveRevert if the context prevents reposting (i.e offer is not provisioned or does not comply with density requirements)
  function __postHookSuccess__(MgvLib.SingleOrder calldata order)
    internal
    virtual
  {
    uint new_gives = MP.offer_unpack_gives(order.offer) - order.wants;
    uint new_wants = MP.offer_unpack_wants(order.offer) - order.gives;
    try
      this.updateOffer(
        order.outbound_tkn,
        order.inbound_tkn,
        new_wants,
        new_gives,
        MP.offerDetail_unpack_gasreq(order.offerDetail),
        MP.offer_unpack_gasprice(order.offer),
        MP.offer_unpack_next(order.offer),
        order.offerId
      )
    {} catch Error(string memory message) {
      emit MangroveRevert(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offerId,
        message
      );
    }
  }

  function __postHookGetFailure__(MgvLib.SingleOrder calldata order)
    internal
    virtual
  {
    order; //shh
  }

  function __postHookReneged__(MgvLib.SingleOrder calldata order)
    internal
    virtual
  {
    order; //shh
  }

  function __postHookFallback__(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata result
  ) internal virtual {
    order; //shh
    result;
  }
}
