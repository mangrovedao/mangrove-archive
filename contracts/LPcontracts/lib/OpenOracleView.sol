// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.10;

import "./OpenOraclePriceData.sol";

/**
 * @title The Open Oracle View Base Contract
 * @author Compound Labs, Inc.
 */
contract OpenOracleView {
  /**
   * @notice The Oracle Data Contract backing this View
   */
  OpenOracleData public priceData;

  /**
   * @notice The static list of sources used by this View
   * @dev Note that while it is possible to create a view with dynamic sources,
   *  that would not conform to the Open Oracle Standard specification.
   */
  address[] public sources;

  /**
   * @notice Construct a view given the oracle backing address and the list of sources
   * @dev According to the protocol, Views must be immutable to be considered conforming.
   * @param data_ The address of the oracle data contract which is backing the view
   * @param sources_ The list of source addresses to include in the aggregate value
   */
  constructor(address data_, address[] memory sources_) {
    require(sources_.length > 0, "Must initialize with sources");
    priceData = OpenOracleData(data_);
    sources = sources_;
  }

/** taken from Compound Lab Inc
 * @notice The DelFi Price Feed View
 */

  function medianPrice(string memory symbol) public view returns (uint64 median) {
    require(sources.length > 0, "sources list must not be empty");

    uint N = sources.length;
    uint64[] memory postedPrices = new uint64[](N);
    for (uint i = 0; i < N; i++) {
        postedPrices[i] = OpenOraclePriceData(address(priceData)).getPrice(sources[i], symbol);
    }

    uint64[] memory sortedPrices = sort(postedPrices);
    return sortedPrices[N / 2];
  }
  
  function sort(uint64[] memory array) private pure returns (uint64[] memory) {
      uint N = array.length;
      for (uint i = 0; i < N; i++) {
        for (uint j = i + 1; j < N; j++) {
            if (array[i] > array[j]) {
                uint64 tmp = array[i];
                array[i] = array[j];
                array[j] = tmp;
            }
        }
    }
    return array;
    }
}
