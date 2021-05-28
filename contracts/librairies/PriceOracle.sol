pragma solidity ^0.7.0;
pragma abicoder v2;
import "./AccessControlled.sol";

contract PriceOracle is AccessControlled {
  address immutable base_token;

  mapping(address => uint160) private quotes;
  mapping(address => bool) public subscribers;

  constructor(address _base_token) AccessControlled() {
    base_token = _base_token;
  }

  function register(address subscriber) external onlyCaller(admin) {
    subscribers[subscriber] = true;
  }

  // price in quote for 1 unit of base.
  function set_quote_for(address erc_quote, uint amount)
    external
    onlyCaller(admin)
  {
    require(uint160(amount) == amount);
    quotes[erc_quote] = uint160(amount);
  }

  function get_quote_for(address erc_quote) external returns (uint) {
    require(subscribers[msg.sender]);
    return (quotes[erc_quote]);
  }
}
