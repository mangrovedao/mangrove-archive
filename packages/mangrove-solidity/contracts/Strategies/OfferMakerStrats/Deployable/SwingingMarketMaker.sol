pragma solidity ^0.7.0;
pragma abicoder v2;
import "../CompoundTrader.sol";

contract SwingingMarketMaker is CompoundTrader {
  event Begin();
  event NotEnoughLiquidity(address token, uint amountMissing);
  event MissingPrice(address token0, address token1);
  event NotEnoughProvision(uint amount);

  // price[B][A] : price of A in B
  mapping(address => mapping(address => uint)) private price; // 18 decimals precision
  mapping(address => mapping(address => uint)) private offers;

  constructor(
    address _unitroller,
    address payable _MGV,
    address wethAddress
  ) CompoundLender(_unitroller, wethAddress) MangroveOffer(_MGV) {
    emit Begin();
  }

  // sets P(tk0|tk1)
  // one wants P(tk0|tk1).P(tk1|tk0) >= 1
  function setPrice(
    address tk0,
    address tk1,
    uint p
  ) external onlyAdmin {
    price[tk0][tk1] = p;
  }

  function startStrat(
    address tk0,
    address tk1,
    uint gives
  ) external onlyAdmin returns (bool) {
    bool success = repostOffer(tk0, tk1, gives);
    if (success) {
      IERC20(tk0).approve(address(MGV), uint(-1)); // approving MGV for tk0 transfer
      IERC20(tk1).approve(address(MGV), uint(-1)); // approving MGV for tk1 transfer
    }
    return success;
  }

  // at this stage contract has `received` amount in token0
  function repostOffer(
    address token0,
    address token1,
    uint received
  ) internal returns (bool) {
    uint p_10 = price[token1][token0];
    if (p_10 == 0) {
      emit MissingPrice(token0, token1);
      return false;
    }
    uint wants = div_(
      mul_(p_10, received), // p(base|quote).(gives:quote) : base
      10**18
    ); // in base units
    uint offerId = offers[token0][token1];
    if (offerId == 0) {
      offerId = newOfferInternal({
        supplyToken: token0,
        demandToken: token1,
        wants: wants,
        gives: received,
        gasreq: OFR_GASREQ,
        gasprice: OFR_GASPRICE,
        pivotId: 0
      });
      offers[token0][token1] = offerId;
    } else {
      updateOfferInternal({
        supplyToken: token0,
        demandToken: token1,
        wants: wants,
        gives: received,
        offerId: offerId,
        pivotId: offerId, // offerId is already on the book so a good pivot
        gasreq: OFR_GASREQ, // default value
        gasprice: OFR_GASPRICE // default value
      });
    }
    return true;
  }

  function __postHookSuccess__(bytes32, MgvLib.SingleOrder memory order)
    internal
    override
  {
    address token0 = order.base;
    address token1 = order.quote;
    uint offer_received = MgvPack.offer_unpack_wants(order.offer); // in token1
    repostOffer({token0: token1, token1: token0, received: offer_received});
  }

  function __postHookGetFailure__(
    bytes32 missing,
    MgvLib.SingleOrder memory order
  ) internal override {
    emit NotEnoughLiquidity(order.base, uint(missing));
  }

  function __autoRefill__(uint amount) internal override returns (bool) {
    if (amount > 0) {
      try MGV.fund{value: amount}() {
        return true;
      } catch {
        emit NotEnoughProvision(amount);
        return false;
      }
    }
  }
}
