pragma solidity ^0.7.0;
pragma abicoder v2;
import {IMaker, MgvCommon as MgvC} from "../../MgvCommon.sol";
import "../../interfaces.sol";
import "../../Mangrove.sol";
import "../../MgvPack.sol";
import "../AccessControlled.sol";

interface IcERC20 is IERC20 {
  /*** User Interface ***/
  // from https://github.com/compound-finance/compound-protocol/blob/master/contracts/CTokenInterfaces.sol
  function mint(uint amount) external returns (uint);

  function redeem(uint redeemTokens) external returns (uint);

  function redeemUnderlying(uint redeemAmount) external returns (uint);

  function borrow(uint borrowAmount) external returns (uint);

  function repayBorrow(uint repayAmount) external returns (uint);

  function balanceOfUnderlying(address owner) external returns (uint);
}

abstract contract MangroveOffer is IMaker, AccessControlled {
  event LogAddress(string log_msg, address info);
  event LogInt(string log_msg, uint info);
  event LogInt2(string log_msg, uint info, uint info2);

  function log(string memory msg, address addr) internal {
    emit LogAddress(msg,addr);
  }
  function log(string memory msg, uint info) internal {
    emit LogInt(msg, info);
  }
  function log(string memory msg, uint info1, uint info2) internal {
    emit LogInt2(msg,info1,info2);
  }

  // Address of the Mangrove contract
  Mangrove immutable MGV;

  // contract that is used as liquidity manager (for) base token)
  // should be ERC20 compatible
  address immutable BASE_ERC;

  // value return
  enum TradeResult {Drop, Proceed}

  constructor(address payable mgv, address base_erc) {
    MGV = Mangrove(mgv);
    BASE_ERC = base_erc;
  }

  receive() external payable {}

  // Utilities

  // Queries the Mangrove to know how much WEI will be required to post a new offer
  function getProvision(address quote_erc, uint gasreq, uint gasprice) public returns (uint) {
    MgvC.Config memory config = MGV.getConfig(BASE_ERC, quote_erc);
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

  function __trade_posthook_getStoredOffer(MgvC.SingleOrder calldata order) internal returns (uint,uint,uint,uint) {
    uint gasreq = MgvPack.offerDetail_unpack_gasreq(order.offerDetail);
    (,,uint wants,uint gives, uint gasprice) = MgvPack.offer_unpack(order.offer);
    return (wants,gives,gasreq,gasprice);
  }

  // To throw a message that will be passed to posthook
  function __trade_Revert(bytes32 data) internal pure {
    bytes memory revData = new bytes(32);
    assembly {
      mstore(add(revData, 32), data)
      revert(add(revData, 32), 32)
    }
  }

  // Mangrove basic interactions (logging is done by the Mangrove)

  function approveMgv(uint amount) public onlyCaller(admin) {
    require(IERC20(BASE_ERC).approve(address(MGV), amount));
  }

  function withdraw(address receiver, uint amount)
    public
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
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId
  ) internal returns (uint offerId) {
    offerId = MGV.newOffer(
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
  ) internal {
    MGV.updateOffer(
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
  ) internal {
    MGV.retractOffer(BASE_ERC, quote_erc, offerId, deprovision);
  }
}
