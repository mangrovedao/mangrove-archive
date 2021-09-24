pragma solidity ^0.7.0;
pragma abicoder v2;
// SPDX-License-Identifier: MIT

import "../interfaces/IOracle.sol";
import "./AccessControlled.sol";

contract SimpleOracle is IOracle, AccessControlled {
    address reader; // if unset, anyone can read price

    function setReader(address _reader) onlyAdmin external { 
        reader = _reader;
    }

    mapping (address => uint96) internal priceData;   

    function setPrice(address token, uint price) external onlyAdmin override {
        require(uint96(price)==price, "price overflow");
        priceData[token] = uint96(price);
    }

    function getPrice(address token) onlyCaller(reader) external view override returns (uint96 price) {
        price = priceData[token];
        require(price != 0, "missing price data");
    }
}