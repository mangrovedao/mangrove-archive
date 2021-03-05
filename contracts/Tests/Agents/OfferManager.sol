// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma abicoder v2;

import "../../Dex.sol";
import "../../interfaces.sol";
//import "../../DexCommon.sol";
import {DexCommon as DC, DexEvents, IDexMonitor} from "../../DexCommon.sol";
import "hardhat/console.sol";

import "../Toolbox/Display.sol";

contract OfferManager is IMaker, ITaker {
  // erc_addr -> owner_addr -> balance
  Dex dex;
  Dex invDex;
  address caller_id;
  // dex_addr -> base_addr -> quote_addr -> offerId -> owner
  mapping(address => mapping(address => mapping(address => mapping(uint => address)))) owners;
  uint constant gas_to_execute = 100_000;

  constructor(Dex _dex, Dex _inverted) {
    dex = _dex;
    invDex = _inverted;
  }

  //posthook data:
  //base: orp.base,
  // quote: orp.quote,
  // takerWants: takerWants,
  // takerGives: takerGives,
  // offerId: offerId,
  // offerDeleted: toDelete

  function takerTrade(
    //NB this is not called if dex is not a flashTaker dex
    address base,
    address quote,
    uint netReceived,
    uint shouldGive
  ) external override {
    if (msg.sender == address(invDex)) {
      ITaker(caller_id).takerTrade(base, quote, netReceived, shouldGive); // taker will find funds
      IERC20(quote).transferFrom(caller_id, address(this), shouldGive); // ready to be withdawn by Dex
    }
  }

  function makerPosthook(
    DC.SingleOrder calldata _order,
    DC.OrderResult calldata
  ) external override {
    if (msg.sender == address(invDex)) {
      //should have received funds by now
      address owner =
        owners[msg.sender][_order.base][_order.quote][_order.offerId];
      require(owner != address(0), "Unkown owner");
      IERC20(_order.quote).transfer(owner, _order.gives);
    }
  }

  // Maker side execute for residual offer
  event Execute(
    address dex,
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives
  );

  function makerTrade(DC.SingleOrder calldata _order)
    external
    override
    returns (bytes32 ret)
  {
    emit Execute(
      msg.sender,
      _order.base,
      _order.quote,
      _order.offerId,
      _order.wants,
      _order.gives
    );
    if (msg.sender == address(dex)) {
      // if residual of offerId is < dust, offer will be removed and dust lost
      // also freeWeil[this] will increase, offerManager may chose to give it back to owner
      address owner =
        owners[address(dex)][_order.base][_order.quote][_order.offerId];
      require(owner != address(0), "Unkown owner");
      try IERC20(_order.quote).transfer(owner, _order.gives) {
        ret = "OfferManager/transferOK";
      } catch {
        ret = "transferToOwnerFail";
      }
    } else {}
  }

  //marketOrder (base,quote) + NewOffer(quote,base)
  function order(
    Dex DEX,
    address base,
    address quote,
    uint wants,
    uint gives,
    bool invertedResidual
  ) external payable {
    bool flashTaker = (address(DEX) == address(invDex));
    caller_id = msg.sender; // this should come with a reentrancy lock
    if (!flashTaker) {
      // else caller_id will be called when takerTrade is called by Dex
      IERC20(quote).transferFrom(msg.sender, address(this), gives); // OfferManager must be approved by sender
    }
    IERC20(quote).approve(address(DEX), 100 ether); // to pay maker
    IERC20(base).approve(address(DEX), 100 ether); // takerfee

    (uint netReceived, ) = DEX.marketOrder(base, quote, wants, gives); // OfferManager might collect provisions of failing offers

    try IERC20(base).transfer(msg.sender, netReceived) {
      uint residual_w = wants - netReceived;
      uint residual_g = (gives * residual_w) / wants;

      Dex _DEX;
      if (invertedResidual) {
        _DEX = invDex;
      } else {
        _DEX = dex;
      }
      DC.Config memory config = _DEX.getConfig(base, quote);
      require(
        msg.value >= gas_to_execute * uint(config.global.gasprice) * 10**9,
        "Insufficent funds to delegate order"
      ); //not checking overflow issues
      (bool success, ) = address(_DEX).call{value: msg.value}("");
      require(success, "provision dex failed");
      uint residual_ofr =
        _DEX.newOffer(
          quote,
          base,
          residual_w,
          residual_g,
          gas_to_execute,
          0,
          0
        );
      owners[address(_DEX)][quote][base][residual_ofr] = msg.sender;
    } catch {
      require(false, "Failed to send market order money to owner");
    }
  }
}
