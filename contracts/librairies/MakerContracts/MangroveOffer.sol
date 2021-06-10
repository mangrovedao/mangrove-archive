pragma solidity ^0.7.0;
pragma abicoder v2;
import {IMaker, MgvCommon as MgvC} from "../../MgvCommon.sol";
import "../../interfaces.sol";
import "../../Mangrove.sol";
import "../../MgvPack.sol";
import "../AccessControlled.sol";
import "../Exponential.sol";

/// @title Basic structure of an offer to be posted on the Mangrove
/// @author Giry

contract MangroveOffer is IMaker, AccessControlled {
  event RepostFailed(address erc, uint amount);
  enum GetResult {OK, Error, FatalError}

  address payable immutable MGV;

  receive() external payable {}

  constructor(address payable _MGV) {
    MGV = _MGV;
  }

  /// @notice Utility function to get/extract data sent by the Mangrove during trade execution
  /// @notice Queries the Mangrove to know how much WEI will be required to post a new offer
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

  /// @dev extracts old offer from the order that is received from the Mangrove
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

  /// @dev Throws a message that will be passed to posthook (message is truncated after 32 bytes)
  function tradeRevertWithData(bytes32 data) internal pure {
    bytes memory revData = new bytes(32);
    assembly {
      mstore(add(revData, 32), data)
      revert(add(revData, 32), 32)
    }
  }

  /// @title Mangrove basic interactions (logging is done by the Mangrove)

  /// @dev trader needs to approve the Mangrove to perform base token transfer at the end of the `makerTrade` function
  function approveMangrove(address base_erc20, uint amount)
    external
    virtual
    onlyCaller(admin)
  {
    require(IERC20(base_erc20).approve(MGV, amount));
  }

  /// @dev withdraws ETH from the bounty vault of the Mangrove.
  /// @notice `Mangrove.fund` function need not be called by `this` so is not included here.
  function withdrawFromMangrove(address receiver, uint amount)
    external
    virtual
    onlyCaller(admin)
    returns (bool noRevert)
  {
    require(Mangrove(MGV).withdraw(amount));
    require(receiver != address(0), "Cannot transfer WEIs to 0x0 address");
    (noRevert, ) = receiver.call{value: amount}("");
  }

  /// @dev posts a new offer on the mangrove
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
  ) public virtual onlyCaller(admin) returns (uint offerId) {
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

  /// @dev updates an existing offer (i.e having already an offerId) on the mangrove. Gasprice is lower than creating the offer anew.
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
  ) public virtual onlyCaller(admin) {
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
  ) public virtual onlyCaller(admin) {
    Mangrove(MGV).retractOffer(base_erc20, quote_erc20, offerId, deprovision);
  }

  /// @notice Basic strategy to fetch liquidity (simply checks the balance of `this`)
  /// @notice Deposit is done only if fetch liquidity succeeds in order to save gas. So strategy is not using flashloan from the taker.
  function fetchLiquidity(
    address base,
    address quote,
    uint order_wants,
    uint order_gives
  ) internal virtual returns (bytes32) {
    bool successDeposit = put(quote, order_gives); // specifies what to do with the received funds
    uint remaining = get(base, order_wants); // fetches `offer_gives` amount of `base` token as specified by the withdraw function
    if (remaining > 0) {
      // fetched amount could be higher than order requires for gas efficiency
      tradeRevertWithData(INSUFFICIENTFUNDS);
    } else {
      if (successDeposit) {
        return DEPOSITSUCCESS;
      } else {
        return DEPOSITFAIL;
      }
    }
  }

  /////// Mandatory callback functions

  function makerTrade(MgvC.SingleOrder calldata order)
    external
    override
    onlyCaller(MGV)
    returns (bytes32 returnData)
  {
    if (validate(order)) {
      returnData = fetchLiquidity(
        order.base,
        order.quote,
        order.wants,
        order.gives
      );
    } else tradeRevertWithData(DROPTRADE);
  }

  function makerPosthook(
    MgvC.SingleOrder calldata order,
    MgvC.OrderResult calldata result
  ) external override onlyCaller(MGV) {
    repost(order, result);
  }

  /// @dev these functions correspond to default strategy. Contracts that inherit MangroveOffer to define their own deposit/withdraw strategies should define their own version (and eventually call these ones as backup)
  ///@dev default strategy is to not deposit payment in another contract
  ///@param quote is the address of the ERC20 managing the payment token
  ///@param amount is the amount of quote token that has been flashloaned to `this`
  function put(address quote, uint amount) internal virtual returns (bool) {
    /// @dev receive payment is just stored at this address
    return true;
  }

  /// @dev default withdraw is to let the Mangrove fetch base token associated to `this`
  ///@param base is the address of the ERC20 managing the token promised by the offer
  ///@param amount is the amount of base token that has to be available in the balance of `this` by the end of makerTrade
  ///@return remainsToBeFetched is the amount of Base token that is yet to be fetched after calling this function.
  function get(address base, uint amount)
    internal
    virtual
    returns (GetResult result, uint remainsToBeFetched);

  /// @dev function MUST use tradeRevertWithData(data) if order is to be reneged.
  /// @dev default strategy is to accept order at offer price.
  function validate(MgvC.SingleOrder calldata order)
    internal
    virtual
    returns (bool)
  {
    return true;
  }

  /// @dev default strategy is to not repost a taken offer and let user do this
  function repost(
    MgvC.SingleOrder calldata order,
    MgvC.OrderResult calldata result
  ) internal virtual {}
}
