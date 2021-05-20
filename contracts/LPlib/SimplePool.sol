pragma solidity ^0.7.0;
pragma abicoder v2;
import {IMaker, MgvCommon as MgvC} from "../MgvCommon.sol";
import "../interfaces.sol";
import "../Mangrove.sol";

abstract contract SimplePool is IMaker {
  // Address of the Mangrove contract
  Mangrove mgv;

  // ERC20 pool that is used to swap token (ERC quote)
  IERC20 erc_quote;

  // Admin of [this]
  address admin;

  // gas required to execute makerTrade
  // underestimating this amount might result in loosing bounty during trade execution by the Mangrove
  uint gas_to_execute = 100_000;

  // gasprice value (in gwei) to define offer bounty
  uint gasprice_level = 1000;

  constructor(address payable _mgv, address _erc20) {
    mgv = Mangrove(_mgv);
    erc_quote = IERC20(_erc20);
    admin = msg.sender;
  }

  modifier onlyCaller(address caller) {
    require(msg.sender == caller, "InvalidCaller");
    _;
  }

  receive() external payable {}

  function setAdmin(address _admin) external onlyCaller(admin) {
    admin = _admin;
  }

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
  function getProvision(address erc_base) public returns (uint) {
    MgvC.Config memory config = mgv.getConfig(erc_base, address(erc_quote));
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

  // Mangrove trade management

  function makerTrade(MgvC.SingleOrder calldata order)
    external
    view
    override
    onlyCaller(address(mgv))
    returns (bytes32 ret)
  {
    require(erc_quote.balanceOf(address(this)) >= order.gives);
    ret = "TransferOK";
  }

  function approveMgv(uint amount) public onlyCaller(admin) {
    require(erc_quote.approve(address(mgv), amount));
  }

  function withdraw(uint amount)
    external
    onlyCaller(admin)
    returns (bool noRevert)
  {
    require(mgv.withdraw(amount));
    (noRevert, ) = admin.call{value: amount}("");
  }

  function transfer(address erc_base, uint amount) external onlyCaller(admin) {
    IERC20(erc_base).transfer(admin, amount);
  }

  // Mangrove offer posting management

  // returns offerId 0 if failed

  function newOffer(
    address erc_base,
    uint wants,
    uint gives,
    uint pivotId
  ) external onlyCaller(admin) returns (uint offerId) {
    offerId = mgv.newOffer(
      erc_base,
      address(erc_quote),
      wants,
      gives,
      gas_to_execute,
      gasprice_level,
      pivotId
    );
  }

  function updateOffer(
    address erc_base,
    uint wants,
    uint gives,
    uint pivotId,
    uint offerId
  ) external onlyCaller(admin) {
    mgv.updateOffer(
      erc_base,
      address(erc_quote),
      wants,
      gives,
      gas_to_execute,
      gasprice_level,
      pivotId,
      offerId
    );
  }

  function retractOffer(
    address base,
    uint offerId,
    bool _deprovision
  ) external onlyCaller(admin) {
    mgv.retractOffer(base, address(erc_quote), offerId, _deprovision);
  }
}
