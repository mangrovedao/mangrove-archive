pragma solidity ^0.7.0;
pragma abicoder v2;
import "./AccessControlled.sol";

contract PriceOracle is AccessControlled {
  event QuoteReceived(uint);
  event Subscribed(address);

  mapping(address => uint) private quotes;
  mapping(address => bool) public subscribers;

  function register(address subscriber) external onlyCaller(admin) {
    subscribers[subscriber] = true;
  }

  // price in quote for 1 exaunit of base.
  function set_quote_for(address erc_quote, uint amount)
    external
    onlyCaller(admin)
  {
    quotes[erc_quote] = amount;
    emit QuoteReceived(amount);
  }

  function get_quote_for(address erc_quote) external returns (uint) {
    emit Subscribed(erc_quote);
    require(subscribers[msg.sender]);
    return (quotes[erc_quote]);
  }
}
