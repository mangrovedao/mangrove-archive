pragma solidity ^0.7.0;
pragma abicoder v2;

import "../Persistent.sol";

//import "hardhat/console.sol";

contract Basic is Persistent {
  constructor(address payable _MGV) MangroveOffer(_MGV) {}
}
