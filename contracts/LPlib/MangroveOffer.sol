pragma solidity ^0.7.0;
pragma abicoder v2;
import {IMaker, MgvCommon as MgvC} from "../MgvCommon.sol";
import "../interfaces.sol";
import "../Mangrove.sol";
import "./AccessControlled.sol";

abstract contract MangroveOffer is IMaker,AccessControlled {
  // Address of the Mangrove contract
  Mangrove mgv;

  // contract that is used to source liquidity (in base token)
  // should be ERC20 compatible
  address immutable liquidity_source;

  // gas required to execute makerTrade
  // underestimating this amount might result in loosing bounty during trade execution by the Mangrove
  uint gas_to_execute;

  // gasprice value (in gwei) to define offer bounty
  uint gasprice_level;

  constructor(address payable _mgv, address _liquidity_source, uint _gas_to_execute, uint _gasprice_level) {
    mgv = Mangrove(_mgv);
    liquidity_source = _liquidity_source;
    require(uint24(_gas_to_execute) == _gas_to_execute);
    gas_to_execute = _gas_to_execute;
    require(uint16(_gasprice_level) == _gasprice_level);
    gasprice_level = _gasprice_level;
  }

  receive() external payable {}

  function setExecGas(uint gasreq) external onlyCaller(admin) {
    require(uint24(gasreq) == gasreq);
    gas_to_execute = gasreq;
  }

  function setGasPrice(uint gasprice) external onlyCaller(admin) {
    require(uint16(gasprice) == gasprice);
    gasprice_level = gasprice;
  }

  // Utilities

  // Queries the Mangrove to know how much WEI will be required to post a new offer
  function getProvision(address erc_quote) external returns (uint) {
    MgvC.Config memory config = mgv.getConfig(liquidity_source, erc_quote);
    uint _gp;
    if (config.global.gasprice > gasprice_level) {
      _gp = uint(config.global.gasprice);
    } else {
      _gp = gasprice_level;
    }
    return ((gas_to_execute +
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

  // Mangrove trade management

  // Function that verifies that the pool is sufficiently provisioned
  // throws otherwise
  // Note that the order.gives is NOT verified
  function makerTrade(MgvC.SingleOrder calldata order)
    public
    override
    virtual
    onlyCaller(address(mgv))
    returns (bytes32 ret)
  {
    ret = _makerTrade(order);
  }

  function _makerTrade(MgvC.SingleOrder calldata order) internal returns (bytes32){
    if (IERC20(liquidity_source).balanceOf(address(this)) > order.wants) {
      return ("TransferOK");
    }
    else {
      tradeRevert("NoEnoughLiquidity");
    }
  }

  function approveMgv(uint amount) public onlyCaller(admin) {
    require(IERC20(liquidity_source).approve(address(mgv), amount));
  }

  function withdraw(address receiver, uint amount)
    external
    onlyCaller(admin)
    returns (bool noRevert)
  {
    require(mgv.withdraw(amount));
    (noRevert, ) = receiver.call{value: amount}("");
  }

  function transfer(address erc, address receiver, uint amount)
  external
  onlyCaller(admin)
  returns (bool) {
    return (IERC20(erc).transfer(receiver, amount));
  }

  // Mangrove offer posting management

  // returns offerId 0 if failed

  function newOffer(
    address erc_quote,
    uint wants,
    uint gives,
    uint pivotId
  ) external onlyCaller(admin) returns (uint offerId) {
    offerId = mgv.newOffer(
      address(liquidity_source),
      erc_quote,
      wants,
      gives,
      gas_to_execute,
      gasprice_level,
      pivotId
    );
  }

  function updateOffer(
    address erc_quote,
    uint wants,
    uint gives,
    uint pivotId,
    uint offerId
  ) external onlyCaller(admin) {
    mgv.updateOffer(
      address(liquidity_source),
      erc_quote,
      wants,
      gives,
      gas_to_execute,
      gasprice_level,
      pivotId,
      offerId
    );
  }

  function retractOffer(
    address erc_quote,
    uint offerId,
    bool _deprovision
  ) external onlyCaller(admin) {
    mgv.retractOffer(liquidity_source, erc_quote, offerId, _deprovision);
  }
}
