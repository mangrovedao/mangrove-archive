pragma solidity ^0.7.0;
pragma abicoder v2;
// SPDX-License-Identifier: MIT

import "../interfaces/IOracle.sol";
import "./AccessControlled.sol";
import {IERC20} from "../../MgvLib.sol";

contract SimpleOracle is IOracle, AccessControlled {
  address reader; // if unset, anyone can read price
  IERC20 public immutable base_token;
  mapping(address => uint96) internal priceData;

  constructor(address _base) {
    try IERC20(_base).decimals() returns (uint8 d) {
      require(d != 0, "Invalid decimals number for Oracle base");
      base_token = IERC20(_base);
    } catch {
      revert("Invalid Oracle base address");
    }
  }

  function decimals() external view override returns (uint8) {
    return base_token.decimals();
  }

  function setReader(address _reader) external onlyAdmin {
    reader = _reader;
  }

  function setPrice(address token, uint price) external override onlyAdmin {
    require(uint96(price) == price, "price overflow");
    priceData[token] = uint96(price);
  }

  function getPrice(address token)
    external
    view
    override
    onlyCaller(reader)
    returns (uint96 price)
  {
    price = priceData[token];
    require(price != 0, "missing price data");
  }
}
