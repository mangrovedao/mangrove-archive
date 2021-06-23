pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";
import "../lib/OpenOraclePriceData.sol";

// SPDX-License-Identifier: MIT

contract Defensive is MangroveOffer, Exponential, OpenOraclePriceData {
  event MissingLiquidity(address erc20, uint amount, uint offerId);
  event TransferFailure(address erc20, uint amount, uint offerId);
  event ReceiveFailure(address erc20, uint amount, uint offerId);

  OpenOraclePriceData immutable priceFeed;
  address immutable trustedSource;
  uint16 slippage;
  uint constant BP = 1000;

  constructor(
    address _priceFeed,
    address _trustedSource,
    address payable _MGV
  ) MangroveOffer(_MGV) {
    priceFeed = OpenOraclePriceData(_priceFeed);
    trustedSource = _trustedSource;
  }

  function setSlippage(uint _slippage) external onlyAdmin {
    require(uint16(_slippage) == _slippage, "Slippage overflow");
    slippage = uint16(_slippage);
  }

  function __lastLook__(MgvLib.SingleOrder calldata order)
    internal
    view
    virtual
    override
  {
    IERC20 base = IERC20(order.base);
    IERC20 quote = IERC20(order.quote);
    uint oracle_gives =
      mul_( //amount of base tokens required by taker (in ~USD, 6 decimals)
        order.wants,
        uint(priceFeed.getPrice(trustedSource, base.symbol())) //could be checking age of the time stamp of data
      );
    uint oracle_wants =
      mul_( //amount of quote tokens given by taker (in ~USD, 6 decimals)
        order.gives,
        uint(priceFeed.getPrice(trustedSource, quote.symbol()))
      );
    uint offer_wants = order.gives; //uint96
    uint offer_gives = order.wants; //uint96
    // if p'=oracle_wants/oracle_gives > p=offer_wants/offer_gives
    // we require p'-p > p*slippage/BP
    // which is (oracle_gives * offer_wants * slippage)/BP - offer_gives * oracle_wants + oracle_gives*offer_wants > 0
    uint oracleWantsTimesOfferGives = oracle_wants * offer_gives; // both are uint96 cannot overflow
    uint offerWantsTimesOracleGives = offer_wants * oracle_gives; // both are uint96 cannot overflow
    if (
      (offerWantsTimesOracleGives * slippage) /
        BP +
        offerWantsTimesOracleGives <
      oracleWantsTimesOfferGives
    ) {
      //revert if price is beyond slippage
      failTrade(Fail.Slippage, uint96(oracle_wants), uint96(oracle_gives)); //passing fail data to __finalize__
    }
  }

  function __finalize__(
    MgvLib.SingleOrder calldata order,
    Fail failtype,
    uint[] calldata args
  ) internal override {
    if (failtype == Fail.None) {
      return; // order was correctly processed nothing to be done
    }
    if (failtype == Fail.Liquidity) {
      emit MissingLiquidity(order.base, args[0], order.offerId);
      return; // offer was not provisioned enough, not reposting
    }
    if (failtype == Fail.Slippage) {
      (, , uint gasreq, uint gasprice) = getStoredOffer(order);
      updateMangroveOffer( // assumes there is enough provision for offer bounty (gasprice may have changed)
        order.base,
        order.quote,
        args[0],
        args[1],
        gasreq,
        gasprice,
        0,
        order.offerId
      );
      return;
    }
    if (failtype == Fail.Receive) {
      // contract was not able to receive taker's money
      emit ReceiveFailure(order.quote, order.gives, order.offerId);
      return;
    }
    if (failtype == Fail.Transfer) {
      // Mangrove was not able to transfer maker's asset
      emit TransferFailure(order.base, order.wants, order.offerId);
      return;
    }
  }
}
