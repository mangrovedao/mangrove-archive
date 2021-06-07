pragma solidity ^0.7.0;
pragma abicoder v2;
import {IMaker, MgvCommon as MgvC} from "../../MgvCommon.sol";
import "../../interfaces.sol";
import "../../Mangrove.sol";
import "../../MgvPack.sol";
import "../AccessControlled.sol";

/// @title Basic structure of an offer to be posted on the Mangrove
/// @author Giry

contract MangroveOffer is IMaker, AccessControlled {
  address payable immutable MGV; /** @dev The address of the Mangrove contract */

  // value return
  enum TradeResult {NotEnoughFunds, Proceed, Success}

  receive() external payable {}

  constructor(address payable _MGV) {
    MGV = _MGV;
  }

  // Utilities

  // Queries the Mangrove to know how much WEI will be required to post a new offer
  function getProvision(
    address base_erc20,
    address quote_erc20,
    uint gasreq,
    uint gasprice
  ) internal returns (uint) {
    MgvC.Config memory config =
      Mangrove(MGV).getConfig(base_erc20, quote_erc20);
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

  function getStoredOffer(MgvC.SingleOrder calldata order)
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

  // To throw a message that will be passed to posthook
  function tradeRevertWithData(bytes32 data) internal pure {
    bytes memory revData = new bytes(32);
    assembly {
      mstore(add(revData, 32), data)
      revert(add(revData, 32), 32)
    }
  }

  // Mangrove basic interactions (logging is done by the Mangrove)

  function approveMangrove(address base_erc20, uint amount)
    external
    onlyCaller(admin)
  {
    require(IERC20(base_erc20).approve(MGV, amount));
  }

  function withdrawFromMangrove(address receiver, uint amount)
    external
    onlyCaller(admin)
    returns (bool noRevert)
  {
    require(Mangrove(MGV).withdraw(amount));
    require(receiver != address(0), "Cannot transfer WEIs to 0x0 address");
    (noRevert, ) = receiver.call{value: amount}("");
  }

  function newMangroveOffer(
    address base_erc20,
    address quote_erc20,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId
  ) public onlyCaller(admin) returns (uint offerId) {
    offerId = Mangrove(MGV).newOffer(
      base_erc20,
      quote_erc20,
      wants,
      gives,
      gasreq,
      gasprice,
      pivotId
    );
  }

  function updateMangroveOffer(
    address base_erc20,
    address quote_erc20,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId,
    uint offerId
  ) public onlyCaller(admin) {
    Mangrove(MGV).updateOffer(
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
  ) public onlyCaller(admin) {
    Mangrove(MGV).retractOffer(base_erc20, quote_erc20, offerId, deprovision);
  }

  /// trade and posthook functions
  function validateOrder(MgvC.SingleOrder calldata order)
    internal
    returns (TradeResult, bytes32)
  {
    (uint offer_gives, uint offer_wants, , ) = getStoredOffer(order);
    return fetchLiquidity(order.base, order.quote, offer_gives, offer_wants);
  }

  //// @notice Basic strategy to fetch liquidity (simply checks the balance of `this`)
  function fetchLiquidity(
    address base,
    address quote,
    uint offer_gives,
    uint offer_wants
  ) internal returns (TradeResult, bytes32) {
    (TradeResult result, bytes32 data) = withdraw(base, offer_gives); /// @dev fetches `offer_gives` amount of `base` token as specified by the withdraw function
    if (result == TradeResult.Proceed) {
      return deposit(quote, offer_wants); /// @dev places `offer_wants` amount of `quote` token as specified by the deposit function
    }
    return (result, data);
  }

  function withdraw(address base, uint amount)
    internal
    returns (TradeResult, bytes32)
  {
    uint balance = IERC20(base).balanceOf(address(this));
    if (balance >= amount) {
      return (TradeResult.Proceed, "");
    }
    return (TradeResult.NotEnoughFunds, bytes32(amount - balance));
  }

  function deposit(address quote, uint amount) internal {
    /// @dev token is just stored at this address
    return (TradeResult.Success, "");
  }

  function repostOffer(
    MgvC.SingleOrder calldata order,
    MgvC.SingleOrder calldata result
  ) internal pure virtual {}

  /////// Mandatory callback functions

  function makerTrade(MgvC.SingleOrder calldata order)
    external
    onlyCaller(MGV)
    returns (bytes32)
  {
    (TradeResult result, bytes32 data) =
      fetchLiquidity(order.base, order.quote, order.wants, order.gives);
    if (result != TradeResult.Success) {
      tradeRevertWithData(data);
    }
    return data;
  }

  function makerPosthook(
    MgvC.SingleOrder calldata order,
    MgvC.SingleOrder calldata result
  ) external onlyCaller(MGV) {
    repostOffer(order, result);
  }
}
