pragma solidity ^0.7.0;
pragma abicoder v2;
import "../lib/AccessControlled.sol";
import "../lib/Exponential.sol";
import "../lib/TradeHandler.sol";
import "hardhat/console.sol";

// SPDX-License-Identifier: MIT

/// MangroveOffer is the basic building block to implement a reactive offer that interfaces with the Mangrove
contract MangroveOffer is AccessControlled, IMaker, TradeHandler, Exponential {
  Mangrove immutable MGV; // Address of the deployed Mangrove contract

  // default values
  uint public OFR_GASREQ = 1_000_000;

  receive() external payable {}

  // Offer constructor (caller will be admin)
  constructor(address _MGV) {
    (bytes32 global_pack, ) = Mangrove(payable(_MGV))._config(
      address(0),
      address(0)
    );
    uint dead = MP.global_unpack_dead(global_pack);
    require(dead == 0, "Mangrove contract is permanently disabled"); //sanity check
    MGV = Mangrove(payable(_MGV));
  }

  /// transfers token stored in `this` contract to some recipient address
  function transferToken(
    address token,
    address recipient,
    uint amount
  ) external onlyAdmin returns (bool success) {
    success = IERC20(token).transfer(recipient, amount);
  }

  /// trader needs to approve Mangrove to let it perform outbound token transfer at the end of the `makerExecute` function
  function approveMangrove(address outbound_tkn, uint amount)
    external
    onlyAdmin
  {
    require(
      IERC20(outbound_tkn).approve(address(MGV), amount),
      "Failed to approve Mangrove"
    );
  }

  /// withdraws ETH from the bounty vault of the Mangrove.
  /// NB: `Mangrove.fund` function need not be called by `this` so is not included here.
  function withdraw(address receiver, uint amount)
    external
    onlyAdmin
    returns (bool noRevert)
  {
    require(MGV.withdraw(amount));
    require(receiver != address(0), "Cannot transfer WEIs to 0x0 address");
    (noRevert, ) = receiver.call{value: amount}("");
  }

  // Posting a new offer on the (`outbound_tkn,inbound_tkn`) Offer List of Mangrove.
  // NB #1: Offer maker MUST:
  // * Approve Mangrove for at least `gives` amount of `outbound_tkn`.
  // * Make sure that offer maker has enough WEI provision on Mangrove to cover for the new offer bounty
  // * Make sure that `gasreq` and `gives` yield a sufficient offer density
  // NB #2: This function may revert when the above points are not met, it is thus made external only so that it can be encapsulated when called during `makerExecute`.
  function newOffer(
    address outbound_tkn, // address of the ERC20 contract managing outbound tokens
    address inbound_tkn, // address of the ERC20 contract managing outbound tokens
    uint wants, // amount of `inbound_tkn` required for full delivery
    uint gives, // max amount of `outbound_tkn` promised by the offer
    uint gasreq, // max gas required by the offer when called. If maxUint256 is used here, default `OFR_GASREQ` will be considered instead
    uint gasprice, // gasprice that should be consider to compute the bounty (Mangrove's gasprice will be used if this value is lower)
    uint pivotId // identifier of an offer in the (`outbound_tkn,inbound_tkn`) Offer List after which the new offer should be inserted (gas cost of insertion will increase if the `pivotId` is far from the actual position of the new offer)
  ) external internalOrAdmin returns (uint offerId) {
    if (gasreq == type(uint).max) {
      gasreq = OFR_GASREQ;
    }
    return
      MGV.newOffer(
        outbound_tkn,
        inbound_tkn,
        wants,
        gives,
        gasreq,
        gasprice,
        pivotId
      );
  }

  //  Updates an existing `offerId` on the Mangrove. `updateOffer` rely on the same offer requirements as `newOffer` and may throw if they are not met.
  //  Additionally `updateOffer` will thow if `this` contract is not the owner of `offerId`.
  //  The `__autoRefill__` hook may be overridden to provide a method to refill offer provision automatically.
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
    require(
      __autoRefill__(outbound_tkn, inbound_tkn, gasprice, gasreq, offerId),
      "mgvOffer/insufficientFunds"
    );
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

  // Retracts `offerId` from the (`outbound_tkn`,`inbound_tkn`) Offer list of Mangrove. Function call will throw if `this` contract is not the owner of `offerId`.
  function retractOffer(
    address outbound_tkn,
    address inbound_tkn,
    uint offerId,
    bool deprovision // if set to `true`, `this` contract will receive the remaining provision (in WEI) associated to `offerId`.
  ) external internalOrAdmin {
    MGV.retractOffer(outbound_tkn, inbound_tkn, offerId, deprovision);
  }

  function getMissingProvision(
    address outbound_tkn,
    address inbound_tkn,
    uint gasreq,
    uint gasprice,
    uint offerId
  ) public view returns (uint) {
    return
      getMissingProvision(
        MGV,
        outbound_tkn,
        inbound_tkn,
        gasreq,
        gasprice,
        offerId
      );
  }

  /////// Mandatory callback functions

  // `makerExecute` is the callback function to execute all offers that were posted on Mangrove by `this` contract.
  // it may not be overriden although it can be customized using `__lastLook__`, `__put__` and `__get__` hooks.
  // NB #1: Offer Maker SHOULD make sure the overriden hooks do not revert in order to be able to post logs in case of bad executions.
  // NB #2: if `makerExecute` does revert, the offer will be considered to be refusing the trade.
  function makerExecute(MgvLib.SingleOrder calldata order)
    external
    override
    onlyCaller(address(MGV))
    returns (bytes32)
  {
    if (!__lastLook__(order)) {
      // hook to check order details and decide whether `this` contract should renege on the offer.
      return RENEGED;
    }
    __put__(IERC20(order.inbound_tkn), order.gives); // hook to specify what should be done with the liquidity that is flashswapped by the offer taker to `this` contract
    uint missingGet = __get__(IERC20(order.outbound_tkn), order.wants); // hook to describe how `this` contract should make the outbound tokens available
    if (missingGet > 0) {
      return OUTOFLIQUIDITY;
    }
    return bytes32(""); // proceed with trade
  }

  // `makerPosthook` is the callback function that is called by Mangrove *after* the offer execution.
  // it may not be overriden although it can be customized using `__lastLook__`, `__put__` and `__get__` hooks.
  // NB #1: Offer Maker SHOULD make sure the overriden hooks do not revert in order to be able to post logs in case of bad executions.
  // NB #2: if `makerExecute` does revert, the offer will be considered to be refusing the trade.
  function makerPosthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata result
  ) external override onlyCaller(address(MGV)) {
    if (result.mgvData == "mgv/tradeSuccess") {
      // if trade was a success
      __posthookSuccess__(order);
      return;
    }
    // if trade was cancelled by offer maker
    if (result.makerData == OUTOFLIQUIDITY) {
      __posthookGetFailure__(order);
      return;
    }
    if (result.makerData == RENEGED) {
      __posthookReneged__(order);
      return;
    }
    __posthookFallback__(order, result);
    return;
  }

  ////// Hooks

  function __autoRefill__(
    address outbound_tkn,
    address inbound_tkn,
    uint gasreq,
    uint gasprice,
    uint offerId
  ) internal virtual returns (bool) {
    outbound_tkn; //shh
    inbound_tkn;
    gasreq;
    gasprice;
    offerId;
    return true;
  }

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

  function __posthookSuccess__(MgvLib.SingleOrder calldata order)
    internal
    virtual
  {
    order; // shh
  }

  function __posthookGetFailure__(MgvLib.SingleOrder calldata order)
    internal
    virtual
  {
    uint missing = order.wants -
      IERC20(order.outbound_tkn).balanceOf(address(this));
    emit NotEnoughLiquidity(order.outbound_tkn, missing);
  }

  function __posthookReneged__(MgvLib.SingleOrder calldata order)
    internal
    virtual
  {
    order; //shh
  }

  function __posthookFallback__(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata result
  ) internal virtual {
    order; //shh
    result;
  }
}
