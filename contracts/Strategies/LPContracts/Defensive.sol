pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";
import "../lib/OpenOracleView.sol";

// SPDX-License-Identifier: MIT

contract Defensive is MangroveOffer, OpenOracleView {
  event MissingLiquidity(address erc20, uint amount, uint offerId);
  event TransferFailure(address erc20, uint amount, uint offerId);
  event ReceiveFailure(address erc20, uint amount, uint offerId);

  uint16 slippage;
  uint constant BP = 1000;

  constructor(
    address _priceData,
    address[] memory _trustedSources,
    address payable _MGV
  ) MangroveOffer(_MGV) OpenOracleView(_priceData, _trustedSources) {}

  function setSlippage(uint _slippage) external onlyAdmin {
    require(uint16(_slippage) == _slippage, "Slippage overflow");
    slippage = uint16(_slippage);
  }

  function __getPrice__(string memory symbol)
    internal
    view
    virtual
    returns (uint)
  {
    return uint(medianPrice(symbol));
  }

  function __lastLook__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
  {
    IERC20 base = IERC20(order.base);
    IERC20 quote = IERC20(order.quote);
    uint oracle_gives = mul_( //amount of base tokens required by taker (in ~USD, 6 decimals)
      order.wants,
      __getPrice__(base.symbol()) // calling the method to get the price from priceData
    );
    uint oracle_wants = mul_( //amount of quote tokens given by taker (in ~USD, 6 decimals)
      order.gives, //padded uint96
      __getPrice__(quote.symbol()) //padded uint96
    );
    uint offer_wants = order.gives; //padded uint96
    uint offer_gives = order.wants; //padded uint96
    // if p'=oracle_wants/oracle_gives > p=offer_wants/offer_gives
    // we require p'-p > p*slippage/BP
    // which is (oracle_gives * offer_wants * slippage)/BP - offer_gives * oracle_wants + oracle_gives*offer_wants > 0
    uint oracleWantsTimesOfferGives = oracle_wants * offer_gives; // both are padded uint96 cannot overflow
    uint offerWantsTimesOracleGives = offer_wants * oracle_gives; // both are padded uint96 cannot overflow
    if (
      (offerWantsTimesOracleGives * slippage) /
        BP +
        offerWantsTimesOracleGives <
      oracleWantsTimesOfferGives
    ) {
      //revert if price is beyond slippage
      returnData({drop:true, postHook_switch:PostHook.Price, arg0:uint96(oracle_wants), arg1: uint96(oracle_gives)}); //passing fail data to __finalize__
    }
    else { //oportunistic adjustment to price. Slippage is not enough to drop trade, but price should be updated at repost
      returnData({drop:false, postHook_switch:PostHook.Price, arg0:uint96(oracle_wants), arg1: uint96(oracle_gives)});
    }
  }

  function __postHookPriceSlippage__(
    uint usd_maker_wants, 
    uint usd_maker_gives, 
    MgvLib.SingleOrder calldata order
    ) internal virtual override {
      (uint old_maker_gives,, uint old_gasreq, uint old_gasprice) = unpackOfferFromOrder(order);
      uint new_wants = div_(
        mul_(usd_maker_wants, old_maker_gives),
        usd_maker_gives
      );
      repost( // since Mangrove's gasprice may have changed, one can also override __autoRefill__ to declare this contract should refill provisions if needed
        order.base,
        order.quote,
        new_wants,
        old_maker_gives,
        old_gasreq,
        old_gasprice,
        0,
        order.offerId
      );
  }
}
