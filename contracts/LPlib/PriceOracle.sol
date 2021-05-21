pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";
import "./PriceOracle.sol";

contract PriceOracle is AccessControlled{
  address immutable base_token ;

  mapping(address => uint) private quotes;
  mapping (address => bool) private subscribers;

  constructor(address _base_token) AccessControlled (){
    base_token = _base_token;
  }

 function register(address subscriber) external onlyCaller(admin){
   subscribers[subscriber] = true;
 }

 // price in quote for 1 unit of base.
 function set_price_for(address erc_quote, uint amount) external onlyCaller(admin) {
   quotes[erc_quote] = amount ;
 }

 function is_registered(address addr) internal returns (bool){
   return (subscribers[addr]);
 }

 function get_price_for(address erc_quote) external returns (uint){
   require (is_registered(msg.sender));
   return (quotes[erc_quote]);
 }

}
