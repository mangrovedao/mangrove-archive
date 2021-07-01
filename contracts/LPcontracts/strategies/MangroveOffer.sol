pragma solidity ^0.7.0;
pragma abicoder v2;
import "../../Mangrove.sol";
import "../../MgvLib.sol";
import "../../MgvPack.sol";
import "../lib/AccessControlled.sol";
import "../lib/Exponential.sol";
import "../lib/TradeHandler.sol";

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
  function unpackFromOrder(MgvLib.SingleOrder calldata order)
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
  function update(
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
    returnData = makerExecuteInternal(
      order.base,
      order.quote,
      order.wants,
      order.gives
    );
  }

  // not a virtual function to make sure it is only MGV callable
  function makerPosthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata result
  ) external override onlyCaller(address(MGV)) {
    postHookInternal(order, result);
  }

  function postHookInternal(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata result
  ) internal {
    Fail failtype;
    uint[] memory args;
    if (result.statusCode != "mgv/tradeSuccess") {
      if (result.statusCode == "mgv/makerRevert") {
        // if trade was dropped by maker
        (failtype, args) = getMakerData(result.makerData);
      } else {
        // trade was dropped by the Mangrove
        if (result.statusCode == "mgv/makerTransferFail") {
          failtype = Fail.Transfer;
        } else {
          if (result.statusCode == "mgv/makerReceiveFail") {
            failtype = Fail.Receive;
          }
        }
      }
    }
    __finalize__(order, failtype, args); // NB failtype == Fail.None and args = uint[](0) if trade was a success
  }

  /// @notice Core strategy to fetch liquidity
  function makerExecuteInternal(
    address base,
    address quote,
    uint order_wants,
    uint order_gives
  ) internal returns (bytes32) {
    uint missingPut = __put__(quote, order_gives); // specifies what to do with the received funds
    uint missingGet = __get__(base, order_wants); // fetches `offer_gives` amount of `base` token as specified by the withdraw function
    if (missingGet > 0) {
      //missingGet is padded uint96
      // fetched amount could be higher than order requires for gas efficiency
      //failTrade(Fail.Liquidity, uint96(missingGet), uint96(0));
    }
    if (missingPut == 0) {
      return "Success";
    }
    return "PutFailed";
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
  /// @param amount is the amount of base token that has to be available in the balance of `this` by the end of makerExecute
  /// @return remainsToBeFetched is the amount of Base token that is yet to be fetched after calling this function.
  function __get__(address base, uint amount) internal virtual returns (uint) {
    uint balance = IERC20(base).balanceOf(address(this));
    return (balance > amount ? 0 : amount - balance);
  }

  /// @notice default strategy is to accept order at offer price.
  function __lastLook__(MgvLib.SingleOrder calldata) internal virtual {}

  /// @notice default strategy is to not repost a taken offer and let user do this
  function __finalize__(
    MgvLib.SingleOrder calldata,
    Fail,
    uint[] memory
  ) internal virtual {}

  // override this function in order to refill bounty provision automatically when reposting offers.
  function __autoRefill__(uint amount) internal pure virtual {
    require(amount == 0, "Insufficient provision");
  }
}
