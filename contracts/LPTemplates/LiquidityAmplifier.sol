pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";

abstract contract LiquidityAmplifier is MangroveOffer {
  constructor(address payable mgv, address base_erc)
    MangroveOffer(mgv, base_erc)
  {}

  function trade_check_liquidity() internal {}
}
