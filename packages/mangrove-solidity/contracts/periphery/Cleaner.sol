pragma solidity ^0.7.0;
pragma abicoder v2;
import "../Strategies/lib/AccessControlled.sol";
import "../Mangrove.sol";
import "../Strategies/lib/CarefulMath.sol";
import "../MgvLib.sol";

contract Keeper is AccessControlled, CarefulMath {
  Mangrove immutable MGV;

  constructor(Mangrove _MGV) {
    MGV = _MGV;
  }

  receive() external payable {
    (bool success, ) = admin.call{value: msg.value}(""); // to collect the bounty
    require(success, "Bounty transfer failure");
  }

  function approveMgv(address quote, uint amount) public onlyAdmin {
    IERC20(quote).approve(address(MGV), amount);
  }

  function collect(
    address base,
    address quote,
    uint[] memory offers
  ) external {
    uint[4][] memory args = new uint[4][](offers.length);
    for (uint i = 0; i < offers.length; i++) {
      args[i] = [offers[i], 0, uint(MAXUINT96), uint(MAXUINT24)]; //offerId,takerWants,takerGives,gasreq
    }
    (uint successes, , ) = MGV.snipes(base, quote, args, false); //fillGives to try and take the whole volume
    require(successes == 0, "Some offer collection failed");
  }

  function touchAndCollect(
    address base,
    address quote,
    uint offerId,
    uint gives
  ) external {
    (bool success, , ) =
      MGV.snipe(base, quote, offerId, 0, gives, uint(MAXUINT24), false);
    require(!success, "Collect failed");
  }

  function transfer(
    address erc,
    address recipient,
    uint amount
  ) external onlyAdmin returns (bool) {
    return IERC20(erc).transfer(recipient, amount);
  }
}
