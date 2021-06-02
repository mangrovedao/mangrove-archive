pragma solidity ^0.7.0;
pragma abicoder v2;
import {IMaker, MgvCommon as MgvC} from "../../MgvCommon.sol";
import "../../interfaces.sol";
import "../../Mangrove.sol";
import "../../MgvPack.sol";
import "../AccessControlled.sol";

/// @title Basic structure of an offer to be posted on the Mangrove
/// @author Giry

abstract contract MangroveOffer is IMaker, AccessControlled {
  address payable immutable MGV;  /** @dev The address of the Mangrove contract */ 
  address immutable BASE_ERC;  /** @dev The address of the token manager that the offer is selling */

  uint constant None = uint(-1);

  event LogAddress(string log_msg, address info);
  event LogInt(string log_msg, uint info);
  event LogInt2(string log_msg, uint info, uint info2);
  event LogString(string log_msg);

  function log(string memory msg) internal {
    emit LogString(msg);
  }

  function log(string memory msg, address addr) internal {
    emit LogAddress(msg, addr);
  }

  function log(string memory msg, uint info) internal {
    emit LogInt(msg, info);
  }

  function log(
    string memory msg,
    uint info1,
    uint info2
  ) internal {
    emit LogInt2(msg, info1, info2);
  }

  // value return
  enum TradeResult {Drop, Proceed}

  receive() external payable {}

  constructor(address payable _MGV, address _BASE_ERC) {
    MGV = _MGV;
    BASE_ERC = _BASE_ERC;
  }

  // Utilities

  // Queries the Mangrove to know how much WEI will be required to post a new offer
  function getProvision(
    address BASE_ERC,
    address quote_erc,
    uint gasreq,
    uint gasprice
  ) public returns (uint) {
    MgvC.Config memory config = Mangrove(MGV).getConfig(BASE_ERC, quote_erc);
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
      uint wants,
      uint gives,
      uint gasreq,
      uint gasprice
    )
  {
    gasreq = MgvPack.offerDetail_unpack_gasreq(order.offerDetail);
    (, , wants, gives, gasprice) = MgvPack.offer_unpack(order.offer);
  }

  // To throw a message that will be passed to posthook
  function trade_Revert(bytes32 data) internal pure {
    bytes memory revData = new bytes(32);
    assembly {
      mstore(add(revData, 32), data)
      revert(add(revData, 32), 32)
    }
  }

  // Mangrove basic interactions (logging is done by the Mangrove)

  function approveMangrove(uint amount) external onlyCaller(admin) {
    require(IERC20(BASE_ERC).approve(MGV, amount));
  }

  // transfer BASE or quote token from this contract to admin chosen recipient
  function erc_transfer(
    address erc,
    address recipient,
    uint amount
  ) external onlyCaller(admin) returns (bool) {
    return (IERC20(erc).transfer(recipient, amount));
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
    address quote_erc,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId
  ) public onlyCaller(admin) returns (uint offerId) {
    offerId = Mangrove(MGV).newOffer(
      BASE_ERC,
      quote_erc,
      wants,
      gives,
      gasreq,
      gasprice,
      pivotId
    );
  }

  function updateMangroveOffer(
    address quote_erc,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId,
    uint offerId
  ) public onlyCaller(admin) {
    Mangrove(MGV).updateOffer(
      BASE_ERC,
      quote_erc,
      wants,
      gives,
      gasreq,
      gasprice,
      pivotId,
      offerId
    );
  }

  function retractMangroveOffer(
    address quote_erc,
    uint offerId,
    bool deprovision
  ) public onlyCaller(admin) {
    Mangrove(MGV).retractOffer(BASE_ERC, quote_erc, offerId, deprovision);
  }
}
