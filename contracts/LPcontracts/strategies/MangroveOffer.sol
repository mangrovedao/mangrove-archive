pragma solidity ^0.7.0;
pragma abicoder v2;
import "../interfaces/IMangrove.sol";
import "../interfaces/IERC20.sol";
import "../lib/AccessControlled.sol";
import "../lib/Exponential.sol";
import "../lib/MgvPack.sol";

// SPDX-License-Identifier: MIT

/// @title Basic structure of an offer to be posted on the Mangrove
/// @author Giry

contract MangroveOffer is AccessControlled, IMaker {
  bytes32 constant INSUFFICIENTFUNDS = "InsufficientFunds";
  bytes32 constant GETFAILED = "GetFailed";
  bytes32 constant SUCCESS = "Success";
  bytes32 constant PUTFAILED = "PutFailed";

  event RepostFailed(address erc, uint amount);

  address payable immutable MGV;

  receive() external payable {}

  constructor(address payable _MGV) {
    MGV = _MGV;
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
  function getStoredOffer(MgvCommon.SingleOrder calldata order)
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

  /// @notice Throws a message that will be passed to posthook (message is truncated after 32 bytes)
  function tradeRevertWithData(bytes32 data) internal pure {
    bytes memory revData = new bytes(32);
    assembly {
      mstore(add(revData, 32), data)
      revert(add(revData, 32), 32)
    }
  }

  /// @title Mangrove basic interactions (logging is done by the Mangrove)

  /// @notice trader needs to approve the Mangrove to perform base token transfer at the end of the `makerTrade` function
  function approveMangrove(address base_erc20, uint amount) external onlyAdmin {
    require(IERC20(base_erc20).approve(MGV, amount));
  }

  /// @notice withdraws ETH from the bounty vault of the Mangrove.
  /// @notice `Mangrove.fund` function need not be called by `this` so is not included here.
  function withdrawFromMangrove(address receiver, uint amount)
    external
    onlyAdmin
    returns (bool noRevert)
  {
    require(IMangrove(MGV).withdraw(amount));
    require(receiver != address(0), "Cannot transfer WEIs to 0x0 address");
    (noRevert, ) = receiver.call{value: amount}("");
  }

  /// @notice posts a new offer on the mangrove
  /// @param wants the amount of quote token the offer is asking
  /// @param gives the amount of base token the offer is proposing
  /// @param gasreq the amount of gas unit the offer requires to be executed
  /// @notice we recommend gasreq to be at least 10% higher than dryrun tests
  /// @param gasprice is used to offer a bounty that is higher than normal (as given by a call to `Mangrove.config(base_erc20,quote_erc20).global.gasprice`) in order to cover this offer from future gasprice increase
  /// @notice if gasprice is lower than Mangrove's (for instance if gasprice is set to 0), Mangrove's gasprice will be used to compute the bounty
  /// @param pivotId asks the Mangroce to insert this offer at pivotId in the order book in order to minimize gas costs of insertion. If PivotId is not in the order book (for instance if 0 is chosen), offer will be inserted, starting from best offer.
  /// @return offerId id>0 of the created offer
  function newMangroveOffer(
    address base_erc20,
    address quote_erc20,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId
  ) public onlyAdmin returns (uint offerId) {
    offerId = IMangrove(MGV).newOffer(
      base_erc20,
      quote_erc20,
      wants,
      gives,
      gasreq,
      gasprice,
      pivotId
    );
  }

  /// @notice updates an existing offer (i.e having already an offerId) on the mangrove. Gasprice is lower than creating the offer anew.
  /// @notice the offer may be present on the order book or retracted
  /// @param wants the amount of quote token the offer is asking
  /// @param gives the amount of base token the offer is proposing
  /// @param gasreq the amount of gas unit the offer requires to be executed
  /// @notice we recommend gasreq to be at least 10% higher than dryrun tests
  /// @param gasprice is used to offer a bounty that is higher than normal (as given by a call to `Mangrove.config(base_erc20,quote_erc20).global.gasprice`) in order to cover this offer from future gasprice increase
  /// @notice if gasprice is lower than Mangrove's (for instance if gasprice is set to 0), Mangrove's gasprice will be used to compute the bounty
  /// @param pivotId asks the Mangroce to insert this offer at pivotId in the order book in order to minimize gas costs of insertion. If PivotId is not in the order book (for instance if 0 is chosen), offer will be inserted, starting from best offer.
  /// @param offerId should be the id that was attributed to the offer when it was first posted
  function updateMangroveOffer(
    address base_erc20,
    address quote_erc20,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId,
    uint offerId
  ) public onlyAdmin {
    IMangrove(MGV).updateOffer(
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

  function retractMangroveOffer(
    address base_erc20,
    address quote_erc20,
    uint offerId,
    bool deprovision
  ) public onlyAdmin {
    IMangrove(MGV).retractOffer(base_erc20, quote_erc20, offerId, deprovision);
  }

  /////// Mandatory callback functions

  // not a virtual function to make sure it is only MGV callable
  function makerTrade(MgvCommon.SingleOrder calldata order)
    external
    override
    onlyCaller(MGV)
    returns (bytes32 returnData)
  {
    uint info = __lastLook__(order);
    if (info == 0) {
      returnData = fetchLiquidity(
        order.base,
        order.quote,
        order.wants,
        order.gives
      );
    } else tradeRevertWithData(bytes32(info));
  }

  // not a virtual function to make sure it is only MGV callable
  function makerPosthook(
    MgvCommon.SingleOrder calldata order,
    MgvCommon.OrderResult calldata result
  ) external override onlyCaller(MGV) {
    __finalize__(order, result);
  }

  /// @notice Core strategy to fetch liquidity
  function fetchLiquidity(
    address base,
    address quote,
    uint order_wants,
    uint order_gives
  ) internal returns (bytes32) {
    uint missingPut = __put__(quote, order_gives); // specifies what to do with the received funds
    uint missingGet = __get__(base, order_wants); // fetches `offer_gives` amount of `base` token as specified by the withdraw function
    if (missingGet > 0) {
      // fetched amount could be higher than order requires for gas efficiency
      tradeRevertWithData(INSUFFICIENTFUNDS);
    }
    if (missingPut == 0) {
      return SUCCESS;
    }
    return PUTFAILED;
  }

  ////// Virtual functions to customize trading strategies

  /// @notice these functions correspond to default strategy. Contracts that inherit MangroveOffer to define their own deposit/withdraw strategies should define their own version (and eventually call these ones as backup)
  /// @notice default strategy is to not deposit payment in another contract
  /// @param quote is the address of the ERC20 managing the payment token
  /// @param amount is the amount of quote token that has been flashloaned to `this`
  /// @return remainsToBePut is the sub amount that could not be deposited
  function __put__(address quote, uint amount)
    internal
    virtual
    returns (uint remainsToBePut)
  {
    /// @notice receive payment is just stored at this address
    quote;
    amount;
    return 0;
  }

  /// @notice default withdraw is to let the Mangrove fetch base token associated to `this`
  /// @param base is the address of the ERC20 managing the token promised by the offer
  /// @param amount is the amount of base token that has to be available in the balance of `this` by the end of makerTrade
  /// @return remainsToBeFetched is the amount of Base token that is yet to be fetched after calling this function.
  function __get__(address base, uint amount) internal virtual returns (uint) {
    uint balance = IERC20(base).balanceOf(address(this));
    return (balance > amount ? 0 : amount - balance);
  }

  /// @notice default strategy is to accept order at offer price.
  function __lastLook__(MgvCommon.SingleOrder calldata)
    internal
    virtual
    returns (uint)
  {
    return 0; // 0 is the convention for a valid order
  }

  /// @notice default strategy is to not repost a taken offer and let user do this
  function __finalize__(
    MgvCommon.SingleOrder calldata,
    MgvCommon.OrderResult calldata
  ) internal virtual {}
}
