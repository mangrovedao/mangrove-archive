pragma solidity ^0.7.0;
pragma abicoder v2;
import {IMaker, MgvCommon as MgvC} from "../MgvCommon.sol";
import "../interfaces.sol";
import "../Mangrove.sol";
import "./AccessControlled.sol";

abstract contract MangroveOffer is IMaker, AccessControlled {
  // Address of the Mangrove contract
  Mangrove immutable MGV;

  // contract that is used as liquidity manager (for) base token)
  // should be ERC20 compatible
  address immutable BASE_ERC;
  struct MangroveOffer_env {
    uint16 gasprice;
    uint24 gasreq;
    uint96 gives;
  }

  MangroveOffer_env mangroveOffer_env;

  // value return
  enum TradeResult {Drop, Proceed}

  constructor(address payable mgv, address base_erc) {
    MGV = Mangrove(mgv);
    BASE_ERC = base_erc;
  }

  receive() external payable {}

  function setGasprice(uint gasprice) external onlyCaller(admin) {
    require(uint16(gasprice) == gasprice, "Gasprice too high");
    mangroveOffer_env.gasprice = uint16(gasprice);
  }

  function setGasReq(uint gasreq) external onlyCaller(admin) {
    require(uint24(gasreq) == gasreq, "Gasreq too high");
    mangroveOffer_env.gasreq = uint24(gasreq);
  }

  function setGives(uint gives) external onlyCaller(admin) {
    require(uint96(gives) == gives, "Offer gives too high");
    mangroveOffer_env.gives = uint96(gives);
  }

  // Utilities

  // Queries the Mangrove to know how much WEI will be required to post a new offer
  function getProvision(address quote_erc) external returns (uint) {
    MgvC.Config memory config = MGV.getConfig(BASE_ERC, quote_erc);
    uint _gp;
    if (config.global.gasprice > mangroveOffer_env.gasprice) {
      _gp = uint(config.global.gasprice);
    } else {
      _gp = mangroveOffer_env.gasprice;
    }
    return ((mangroveOffer_env.gasreq +
      config.local.overhead_gasbase +
      config.local.offer_gasbase) *
      _gp *
      10**9);
  }

  // To throw a message that will be passed to posthook
  function tradeRevert(bytes32 data) internal pure {
    bytes memory revData = new bytes(32);
    assembly {
      mstore(add(revData, 32), data)
      revert(add(revData, 32), 32)
    }
  }

  // Mangrove basic interactions

  function approveMgv(uint amount) public onlyCaller(admin) {
    require(IERC20(BASE_ERC).approve(address(MGV), amount));
  }

  function withdraw(address receiver, uint amount)
    external
    onlyCaller(admin)
    returns (bool noRevert)
  {
    require(MGV.withdraw(amount));
    require(receiver != address(0), "Cannot transfer WEIs to 0x0 address");
    (noRevert, ) = receiver.call{value: amount}("");
  }

  function newMangroveOffer(
    address quote_erc,
    uint wants,
    uint pivotId
  ) internal returns (uint offerId) {
    offerId = MGV.newOffer(
      BASE_ERC,
      quote_erc,
      wants,
      mangroveOffer_env.gives,
      mangroveOffer_env.gasreq,
      mangroveOffer_env.gasprice,
      pivotId
    );
  }

  function updateMangroveOffer(
    address quote_erc,
    uint wants,
    uint pivotId,
    uint offerId
  ) internal {
    MGV.updateOffer(
      BASE_ERC,
      quote_erc,
      wants,
      mangroveOffer_env.gives,
      mangroveOffer_env.gasreq,
      mangroveOffer_env.gasprice,
      pivotId,
      offerId
    );
  }

  function retractMangroveOffer(
    address quote_erc,
    uint offerId,
    bool deprovision
  ) internal {
    MGV.retractOffer(BASE_ERC, quote_erc, offerId, deprovision);
  }
}
