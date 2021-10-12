pragma solidity ^0.7.0;
pragma abicoder v2;
import "../CompoundTrader.sol";
import "hardhat/console.sol";

contract SwingingMarketMaker is CompoundTrader {
  event Begin();
  event NotEnoughLiquidity(address token, uint amountMissing);
  event MissingPrice(address token0, address token1);
  event NotEnoughProvision(uint amount);

  // price[B][A] : price of A in B
  mapping(address => mapping(address => uint)) private price; // price[tk0][tk1] is in tk0 precision
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
    price[tk0][tk1] = p; // has tk0.decimals() decimals
  }

  function startStrat(
    address tk0,
    address tk1,
    uint gives // amount of tk0 (with tk0.decimals() decimals)
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
    address outbound_tkn,
    address inbound_tkn,
    uint gives // in outbound_tkn
  ) internal returns (bool) {
    // computing how much inbound_tkn one should ask for `gives` amount of outbound tokens
    // NB p_10 has inbound_tkn.decimals() number of decimals
    uint p_10 = price[inbound_tkn][outbound_tkn];
    if (p_10 == 0) {
      // ! p_10 has the decimals of inbound_tkn
      emit MissingPrice(inbound_tkn, outbound_tkn);
      return false;
    }
    uint wants = div_(
      mul_(p_10, gives), // p(base|quote).(gives:quote) : base
      10**(IERC20(outbound_tkn).decimals())
    ); // in base units
    uint offerId = offers[outbound_tkn][inbound_tkn];
    if (offerId == 0) {
      offerId = newOfferInternal(
        outbound_tkn,
        inbound_tkn,
        wants,
        gives,
        OFR_GASREQ,
        OFR_GASPRICE,
        0
      );
      offers[outbound_tkn][inbound_tkn] = offerId;
    } else {
      updateOfferInternal(
        outbound_tkn,
        inbound_tkn,
        wants,
        gives,
        // offerId is already on the book so a good pivot
        OFR_GASREQ, // default value
        OFR_GASPRICE, // default value
        offerId,
        offerId
      );
    }
    return true;
  }

  function __postHookSuccess__(bytes32, MgvLib.SingleOrder calldata order)
    internal
    override
  {
    address token0 = order.outbound_tkn;
    address token1 = order.inbound_tkn;
    uint offer_received = MgvPack.offer_unpack_wants(order.offer); // amount with token1.decimals() decimals
    if (
      repostOffer({
        outbound_tkn: token1,
        inbound_tkn: token0,
        gives: offer_received
      })
    ) {
      return;
    } else {
      returnData(true, bytes32("swinging/failRepost"));
    }
  }

  function __postHookGetFailure__(bytes32, MgvLib.SingleOrder calldata order)
    internal
    override
  {
    uint missing = order.wants -
      IERC20(order.outbound_tkn).balanceOf(address(this));

    emit NotEnoughLiquidity(order.outbound_tkn, missing);
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

  function __get__(IERC20 base, uint amount)
    internal
    virtual
    override
    returns (uint)
  {
    // checks whether `this` contract has enough `base` token
    uint missingGet = MangroveOffer.__get__(base, amount);
    // if not tries to fetch missing liquidity on compound using `CompoundTrader`'s strat
    return super.__get__(base, missingGet);
  }
}
