// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "./DexCommon.sol";
import "./interfaces.sol";

//import "@nomiclabs/buidler/console.sol";

library DexLib {
  function setConfigKey(
    Config storage config,
    ConfigKey key,
    uint value
  ) external {
    if (key == ConfigKey.takerFee) {
      require(value <= 10000, "takerFee is in bps, must be <= 10000"); // at most 14 bits
      config.takerFee = value;
    } else if (key == ConfigKey.minFinishGas) {
      require(uint24(value) == value, "minFinishGas is 24 bits wide");
      config.minFinishGas = value;
    } else if (key == ConfigKey.dustPerGasWanted) {
      require(value > 0, "dustPerGasWanted must be > 0");
      require(uint32(value) == value);
      config.dustPerGasWanted = value;
    } else if (key == ConfigKey.minGasWanted) {
      require(uint32(value) == value, "minGasWanted is 32 bits wide");
      config.minGasWanted = value;
    } else if (key == ConfigKey.penaltyPerGas) {
      require(uint48(value) == value, "penaltyPerGas is 48 bits wide");
      config.penaltyPerGas = value;
    } else if (key == ConfigKey.transferGas) {
      config.transferGas = value;
    } else {
      revert("Unknown config key");
    }
  }

  function getConfigUint(Config storage config, ConfigKey key)
    external
    view
    returns (uint)
  {
    if (key == ConfigKey.takerFee) {
      return config.takerFee;
    } else if (key == ConfigKey.minFinishGas) {
      return config.minFinishGas;
    } else if (key == ConfigKey.dustPerGasWanted) {
      return config.dustPerGasWanted;
    } else if (key == ConfigKey.minFinishGas) {
      return config.minGasWanted;
    } else if (key == ConfigKey.penaltyPerGas) {
      return config.penaltyPerGas;
    } else if (key == ConfigKey.transferGas) {
      return config.transferGas;
    } else {
      revert("Unknown config key");
    }
  }

  function setConfigKey(
    Config storage config,
    ConfigKey key,
    address value
  ) external {
    if (key == ConfigKey.admin) {
      config.admin = value;
    } else {
      revert("Unknown config key");
    }
  }

  function getConfigAddress(Config storage config, ConfigKey key)
    external
    view
    returns (address value)
  {
    if (key == ConfigKey.admin) {
      return config.admin;
    } else {
      revert("Unknown config key");
    }
  }

  // swap tokens, no checks except msg.sender, throws if bad postcondition
  function swapTokens(
    address ofrToken,
    address reqToken,
    uint orderId,
    uint takerGives,
    uint takerWants,
    uint dexFee,
    uint takerFee,
    OrderDetail memory orderDetail
  ) external returns (bool) {
    // WARNING Should be unnecessary as long as swapTokens is in a library
    //requireSelfSend();
    if (transferToken(reqToken, msg.sender, orderDetail.maker, takerGives)) {
      // Execute order
      IMaker(orderDetail.maker).execute{gas: orderDetail.gasWanted}(
        takerWants,
        takerGives,
        orderDetail.penaltyPerGas,
        orderId
      );

      require(
        transferToken(
          ofrToken,
          orderDetail.maker,
          address(this),
          (takerWants * dexFee) / 10000
        ),
        "fail transfer to dex"
      );
      require(
        transferToken(
          ofrToken,
          orderDetail.maker,
          msg.sender,
          (takerWants * (10000 - takerFee)) / 10000
        ),
        "fail transfer to taker"
      );
      return true;
    } else {
      return false;
    }
  }

  // Avoid "no return value" bug
  // https://soliditydeveloper.com/safe-erc20
  function transferToken(
    address tokenAddress,
    address from,
    address to,
    uint value
  ) internal returns (bool) {
    bytes memory cd = abi.encodeWithSelector(
      IERC20.transferFrom.selector,
      from,
      to,
      value
    );
    (bool success, bytes memory data) = tokenAddress.call(cd);
    return (success && (data.length == 0 || abi.decode(data, (bool))));
  }

  // returns false iff (wants1,gives1) is strictly worse than (wants2,gives2)
  function better(
    uint wants1,
    uint gives1,
    uint wants2,
    uint gives2
  ) internal pure returns (bool) {
    return wants1 * gives2 <= wants2 * gives1;
  }

  function newOrder(
    Config storage config,
    mapping(address => uint) storage freeWei,
    mapping(uint => Order) storage orders,
    mapping(uint => OrderDetail) storage orderDetails,
    UintContainer storage best,
    uint _orderId,
    uint wants,
    uint gives,
    uint gasWanted,
    uint pivotId
  ) external returns (uint) {
    require(
      gives >= gasWanted * config.dustPerGasWanted,
      "offering below dust limit"
    );
    require(uint96(wants) == wants, "wants is 96 bits wide");
    require(uint96(gives) == gives, "gives is 96 bits wide");
    require(uint24(gasWanted) == gasWanted, "gasWanted is 24 bits wide");
    require(gasWanted > 0, "gasWanted > 0"); // division by gasWanted occurs later
    require(uint32(pivotId) == pivotId, "pivotId is 32 bits wide");

    {
      uint maxPenalty = (gasWanted + config.minFinishGas) *
        config.penaltyPerGas;
      require(
        freeWei[msg.sender] >= maxPenalty,
        "insufficient penalty provision to create order"
      );
      freeWei[msg.sender] -= maxPenalty;
    }

    (uint32 prev, uint32 next) = findPosition(
      orders,
      best.value,
      wants,
      gives,
      pivotId
    );

    uint32 orderId = uint32(_orderId);

    //TODO Check if Solidity optimizer prefers this or orders[i].a = a'; ... ; orders[i].b = b'
    orders[orderId] = Order({
      prev: prev,
      next: next,
      wants: uint96(wants),
      gives: uint96(gives)
    });

    orderDetails[orderId] = OrderDetail({
      gasWanted: uint24(gasWanted),
      minFinishGas: uint24(config.minFinishGas),
      penaltyPerGas: uint48(config.penaltyPerGas),
      maker: msg.sender
    });

    if (prev != 0) {
      orders[prev].next = orderId;
    } else {
      best.value = orderId;
    }

    if (next != 0) {
      orders[next].prev = orderId;
    }
    return orderId;
  }

  // 1. add a ghost order orderId with (want,gives) in the right position
  //    you should make sure that the order orderId has the correct price
  // 2. not trying to be a stable sort
  //    but giving privilege to earlier orders
  // 3. to use the least gas, consider which orders would surround yours (with older orders being sorted first)
  //    give any of those as _refId
  //    no analysis was done if garbage ids are allowed
  function findPosition(
    mapping(uint => Order) storage orders,
    uint bestValue,
    uint wants,
    uint gives,
    uint pivotId
  ) internal view returns (uint32, uint32) {
    Order memory pivot = orders[pivotId];

    if (!isOrder(pivot)) {
      // in case pivotId is not or no longer a valid order
      pivot = orders[bestValue];
      pivotId = bestValue;
    }

    if (better(pivot.wants, pivot.gives, wants, gives)) {
      // o is better or as good, we follow next

      Order memory pivotNext;
      while (pivot.next != 0) {
        pivotNext = orders[pivot.next];
        if (better(pivotNext.wants, pivotNext.gives, wants, gives)) {
          pivotId = pivot.next;
          pivot = pivotNext;
        } else {
          break;
        }
      }
      return (uint32(pivotId), pivot.next); // this is also where we end up with an empty OB
    } else {
      // o is strictly worse, we follow prev

      Order memory pivotPrev;
      while (pivot.prev != 0) {
        pivotPrev = orders[pivot.prev];
        if (better(pivotPrev.wants, pivotPrev.gives, wants, gives)) {
          break;
        } else {
          pivotId = pivot.prev;
          pivot = pivotPrev;
        }
      }
      return (pivot.prev, uint32(pivotId));
    }
  }
}
