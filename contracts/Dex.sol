// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./interfaces.sol";
import "./DexCommon.sol";
import "./DexLib.sol";

//import "@nomiclabs/buidler/console.sol";

contract Dex {
  // FIXME: Temporarily storing function selector because .selector doesn't work on public function.
  bytes4 private constant internalMarketOrderSelector = bytes4(
    keccak256("internalMarketOrder(uint256,uint256,uint256,uint256)")
  );

  bytes4 private constant internalSnipesSelector = bytes4(
    keccak256("internalSnipes(uint256[],uint)")
  );

  address public immutable OFR_TOKEN; // ofr_token is the token orders give
  address public immutable REQ_TOKEN; // req_token is the token orders wants

  Config private config;

  bool public open = true;
  bool public accessOB = true; // whether a modification of the OB is permitted
  UintContainer public best; // (32)
  uint private lastId; // (32)

  mapping(uint => Order) private orders;
  mapping(uint => OrderDetail) private orderDetails;
  mapping(address => uint) private freeWei;

  // TODO low gascost bookkeeping methods
  //updateOrder(constant price)
  //updateOrder(change price)

  constructor(
    address initialAdmin,
    uint initialDustPerGasWanted,
    uint initialMinFinishGas,
    uint initialPenaltyPerGas,
    uint initialMinGasWanted,
    address ofrToken,
    address reqToken
  ) {
    OFR_TOKEN = ofrToken;
    REQ_TOKEN = reqToken;
    DexLib.setConfigKey(config, ConfigKey.admin, initialAdmin);
    DexLib.setConfigKey(
      config,
      ConfigKey.dustPerGasWanted,
      initialDustPerGasWanted
    );
    DexLib.setConfigKey(config, ConfigKey.minFinishGas, initialMinFinishGas);
    DexLib.setConfigKey(config, ConfigKey.penaltyPerGas, initialPenaltyPerGas);
    DexLib.setConfigKey(config, ConfigKey.minGasWanted, initialMinGasWanted);
    DexLib.setConfigKey(config, ConfigKey.transferGas, 2300);
  }

  function requireSelfSend() internal view {
    require(msg.sender == address(this), "caller must be dex");
  }

  function requireAdmin() internal view returns (bool) {
    require(address(this) == msg.sender, "not admin");
  }

  function requireOpenOB() internal view {
    require(open, "market is closed");
  }

  function requireAccessibleOB() internal view {
    require(accessOB, "OB not accessible");
  }

  function getLastId() public view returns (uint) {
    requireAccessibleOB();
    return lastId;
  }

  function closeMarket() external {
    requireAdmin();
    open = false;
  }

  //Emulates the transfer function, but with adjustable gas transfer
  function dexTransfer(address payable addr, uint amount) internal {
    (bool success, ) = addr.call{gas: config.transferGas, value: amount}("");
    require(success, "dexTransfer failed");
  }

  function getBest() external view returns (uint) {
    requireAccessibleOB();
    return best.value;
  }

  function getOrderInfo(uint orderId)
    external
    view
    returns (
      uint,
      uint,
      uint,
      uint,
      uint,
      uint,
      address
    )
  {
    requireAccessibleOB();
    Order memory order = orders[orderId];
    OrderDetail memory orderDetail = orderDetails[orderId];
    return (
      order.wants,
      order.gives,
      order.next,
      orderDetail.gasWanted,
      orderDetail.minFinishGas, // global minFinishGas at order creation time
      orderDetail.penaltyPerGas, // global penaltyPerGas at order creation time
      orderDetail.maker
    );
  }

  function setConfigKey(ConfigKey key, uint value) external {
    requireAdmin();
    DexLib.setConfigKey(config, key, value);
  }

  function setConfigKey(ConfigKey key, address value) external {
    requireAdmin();
    DexLib.setConfigKey(config, key, value);
  }

  function getConfigUint(ConfigKey key) external view returns (uint) {
    return DexLib.getConfigUint(config, key);
  }

  function getConfigAddress(ConfigKey key) external view returns (address) {
    return DexLib.getConfigAddress(config, key);
  }

  function balanceOf(address maker) external view returns (uint) {
    return freeWei[maker];
  }

  receive() external payable {
    freeWei[msg.sender] += msg.value;
  }

  function withdraw(uint amount) external {
    require(
      freeWei[msg.sender] >= amount,
      "cannot withdraw more than available in freeWei"
    );
    freeWei[msg.sender] -= amount;
    dexTransfer(msg.sender, amount);
  }

  function cancelOrder(uint orderId) external returns (uint) {
    requireAccessibleOB();
    OrderDetail memory orderDetail = orderDetails[orderId];
    if (msg.sender == orderDetail.maker) {
      Order memory order = orders[orderId];
      internalDeleteOrder(order, orderId);
      // Freeing provisioned penalty for maker
      uint provision = orderDetail.penaltyPerGas * orderDetail.gasWanted;
      freeWei[msg.sender] += provision;
      return provision;
    }
    return 0;
  }

  function newOrder(
    uint wants,
    uint gives,
    uint gasWanted,
    uint pivotId
  ) external returns (uint) {
    requireOpenOB();
    requireAccessibleOB();
    return
      DexLib.newOrder(
        config,
        freeWei,
        orders,
        orderDetails,
        best,
        ++lastId,
        wants,
        gives,
        gasWanted,
        pivotId
      );
  }

  // ask for a volume by setting takerWants to however much you want and
  // takerGive to max_uint. Any price will be accepted.

  // ask for an average price by setting takerGives such that gives/wants is the price

  // there is no limit price setting

  // setting takerWants to max_int and takergives to however much you're ready to spend will
  // not work, you'll just be asking for a ~0 price.
  function internalMarketOrder(
    uint takerWants,
    uint takerGives,
    uint punishLength,
    uint orderId
  ) public returns (uint[] memory) {
    requireOpenOB();
    requireAccessibleOB();
    require(uint32(orderId) == orderId, "orderId is 32 bits wide");
    require(uint96(takerWants) == takerWants, "takerWants is 96 bits wide");
    require(uint96(takerGives) == takerGives, "takerGives is 96 bits wide");

    uint localTakerWants;
    uint localTakerGives;
    Order memory order = orders[orderId];
    require(isOrder(order), "invalid order");
    uint pastOrderId = order.prev;

    uint[] memory failures = new uint[](2 * punishLength);
    uint numFailures;

    accessOB = false;
    // inlining (minTakerWants = dustPerGasWanted*minGasWanted) to avoid stack too deep
    while (
      takerWants >= config.dustPerGasWanted * config.minGasWanted &&
      orderId != 0
    ) {
      // is the taker ready to take less per unit than the maker is ready to give per unit?
      // takerWants/takerGives <= order.ofrAmount / order.reqAmount
      // here we normalize how much the maker would ask for takerWant

      uint makerWouldWant = (takerWants * order.wants) / order.gives;
      if (makerWouldWant <= takerGives) {
        // price is OK for taker
        (localTakerWants, localTakerGives) = order.gives < takerWants
          ? (order.gives, order.wants)
          : (takerWants, makerWouldWant);

        //if success, gasUsedForFailure == 0
        //Warning: orderId is deleted *after* execution
        (bool success, uint gasUsedForFailure) = flashSwapTokens(
          order,
          orderId,
          localTakerWants,
          localTakerGives,
          msg.sender
        );

        if (success) {
          //proceeding with market order
          takerWants -= localTakerWants;
          takerGives -= localTakerGives;
          if (
            order.gives - localTakerWants >=
            config.dustPerGasWanted * config.minGasWanted
          ) {
            orders[orderId].gives = uint96(order.gives - localTakerWants);
            orders[orderId].wants = uint96(order.wants - localTakerGives);
          } else {
            dirtyDeleteOrder(orderId);
          }
        } else {
          dirtyDeleteOrder(orderId);
          if (numFailures++ < punishLength) {
            // storing orderId and gas used for cancellation
            failures[2 * numFailures] = orderId;
            failures[2 * numFailures + 1] = gasUsedForFailure;
          }
        }
        orderId = order.next;
        order = orders[orderId];
      } else {
        // price is not OK for taker
        break; // or revert depending on market order type (see price fill or kill order type of oasis)
      }
    }
    accessOB = true;
    stitchOrders(pastOrderId, orderId);
    // Function throws list of failures if market order was successful
    // returns the error message otherwise
    assembly {
      mstore(failures, mul(2, numFailures))
    } // reduce failures array size
    return failures;
  }

  function snipe(uint orderId, uint takerWants) external {
    requireOpenOB();
    requireAccessibleOB();
    require(uint32(orderId) == orderId, "orderId is 32 bits wide");
    require(uint96(takerWants) == takerWants, "takerWants is 96 bits wide");

    Order memory order = orders[orderId];
    require(isOrder(order), "bad orderId");

    (bool success, ) = executeOrder(orderId, order, takerWants, msg.sender);
    require(success, "execute order failed");
  }

  function snipes(uint[] calldata targets) external {
    internalSnipes(targets, 0);
  }

  function internalSnipes(uint[] calldata targets, uint punishLength)
    public
    returns (uint[] memory)
  {
    requireOpenOB();
    requireAccessibleOB();

    uint targetIndex;
    uint numFailures;
    uint[] memory failures = new uint[](punishLength * 2);
    accessOB = false;
    while (targetIndex < targets.length) {
      uint orderId = targets[2 * targetIndex];
      uint takerWants = targets[2 * targetIndex + 1];
      require(uint32(orderId) == orderId, "orderId is 32 bits wide");
      require(uint96(takerWants) == takerWants, "takerWants is 96 bits wide");
      Order memory order = orders[orderId];
      if (isOrder(order)) {
        (bool success, uint gasUsed) = executeOrder(
          orderId,
          order,
          takerWants,
          msg.sender
        );
        if (!success && numFailures < punishLength) {
          failures[2 * numFailures] = orderId;
          failures[2 * numFailures + 1] = gasUsed;
          numFailures++;
        }
      }
      targetIndex++;
    }
    accessOB = true;
    assembly {
      mstore(failures, mul(2, numFailures))
    } /* reduce failures array size */
    return failures;
  }

  // implements a market order with condition on the minimal delivered volume
  function conditionalMarketOrder(uint takerWants, uint takerGives) external {
    internalMarketOrder(takerWants, takerGives, 0, best.value);
  }

  function stitchOrders(uint past, uint future) internal {
    if (past != 0) {
      orders[past].next = uint32(future);
    } else {
      best.value = future;
    }

    if (future != 0) {
      orders[future].prev = uint32(past);
    }
  }

  function dirtyDeleteOrder(uint orderId) internal {
    delete orders[orderId];
    delete orderDetails[orderId];
  }

  function internalDeleteOrder(Order memory order, uint orderId) internal {
    dirtyDeleteOrder(orderId);
    stitchOrders(order.prev, order.next);
  }

  // internal order execution
  // does not check for reentrancy
  // does not check for parameter validity
  // computes reqToken
  // cleanup OB after execution
  function executeOrder(
    uint orderId,
    Order memory order,
    uint takerWants,
    address payable taker
  ) internal returns (bool, uint) {
    uint localTakerWants = order.gives < takerWants ? order.gives : takerWants;
    uint localTakerGives = (localTakerWants * order.wants) / order.gives;

    accessOB = false;
    (bool success, uint gasUsed) = flashSwapTokens(
      order,
      orderId,
      localTakerGives,
      localTakerWants,
      taker
    );
    accessOB = true;

    if (
      order.gives - localTakerWants >=
      config.dustPerGasWanted * config.minGasWanted
    ) {
      orders[orderId].gives = uint96(order.gives - localTakerWants);
      orders[orderId].wants = uint96(order.wants - localTakerGives);
    } else {
      internalDeleteOrder(order, orderId);
    }
    return (success, gasUsed);
  }

  function applyPenalty(
    address payable taker,
    uint gasUsed,
    OrderDetail memory orderDetail
  ) internal {
    uint maxGasUsed = orderDetail.gasWanted + orderDetail.minFinishGas;
    gasUsed = maxGasUsed < gasUsed ? maxGasUsed : gasUsed;

    freeWei[orderDetail.maker] +=
      (maxGasUsed - gasUsed) *
      orderDetail.penaltyPerGas;
    dexTransfer(taker, gasUsed * orderDetail.penaltyPerGas);
  }

  // swap tokens according to parameters.
  // trusts caller
  // uses flashlend to ensure postcondition
  function flashSwapTokens(
    Order memory order,
    uint orderId,
    uint takerGives,
    uint takerWants,
    address payable taker
  ) internal returns (bool, uint) {
    OrderDetail memory orderDetail = orderDetails[orderId];
    // Execute order
    uint oldGas = gasleft();

    require(
      oldGas >= orderDetail.gasWanted + config.minFinishGas,
      "not enough gas left to safely execute order"
    );

    uint dexFee = (config.takerFee +
      (config.takerFee * config.dustPerGasWanted * orderDetail.gasWanted) /
      order.gives) / 2;

    (bool noRevert, bytes memory retdata) = address(DexLib).delegatecall(
      abi.encodeWithSelector(
        DexLib.swapTokens.selector,
        OFR_TOKEN,
        REQ_TOKEN,
        orderId,
        takerGives,
        takerWants,
        taker,
        dexFee,
        config.takerFee,
        orderDetail
      )
    );
    uint gasUsed = oldGas - gasleft();
    if (noRevert) {
      bool flashSuccess = abi.decode(retdata, (bool));
      require(flashSuccess, "taker failed to send tokens to maker");
      applyPenalty(taker, 0, orderDetail);
      return (true, gasUsed);
    } else {
      applyPenalty(taker, gasUsed, orderDetail);
      return (false, gasUsed);
    }
  }

  // Low-level reverts for different data types
  function evmRevert(bytes memory data) internal pure {
    uint length = data.length;
    assembly {
      revert(data, add(length, 32))
    }
  }

  function evmRevert(uint[] memory data) internal pure {
    uint length = data.length;
    assembly {
      revert(data, add(mul(length, 32), 32))
    }
  }

  // run and revert a market order so as to collect orderId's that are failing
  // punishLength is the number of failing orders one is trying to catch
  function punishingMarketOrderFrom(
    uint fromOrderId,
    uint takerWants,
    uint takerGives,
    uint punishLength
  ) external {
    (bool noRevert, bytes memory retdata) = address(this).delegatecall(
      abi.encodeWithSelector(
        Dex.internalPunishingMarketOrderFrom.selector,
        fromOrderId,
        takerWants,
        takerGives,
        punishLength
      )
    );

    if (noRevert) {
      // `retdata` is a revert data sent as normal return value
      // by `internalPunishingMarketOrderFrom`.
      evmRevert(retdata);
    } else {
      // `retdata` encodes a uint[] array of failed orders.
      punish(retdata, msg.sender);
    }
  }

  function punishingSnipes(uint[] calldata targets, uint punishLength)
    external
  {
    (bool noRevert, bytes memory retdata) = address(this).delegatecall(
      abi.encodeWithSelector(
        Dex.internalPunishingSnipes.selector,
        targets,
        punishLength
      )
    );

    if (noRevert) {
      // `retdata` is a revert data sent as normal return value
      // by `internalPunishingMarketOrderFrom`.
      evmRevert(retdata);
    } else {
      // `retdata` encodes a uint[] array of failed orders.
      punish(retdata, msg.sender);
    }
  }

  function punish(bytes memory failureBytes, address payable taker) internal {
    uint failureIndex;
    uint[] memory failures;
    assembly {
      failures := failureBytes
    }
    uint numFailures = failures.length / 2;
    while (failureIndex < numFailures) {
      uint punishedOrderId = failures[failureIndex * 2];
      uint gasUsed = failures[failureIndex * 2 + 1];
      Order memory order = orders[punishedOrderId];
      OrderDetail memory orderDetail = orderDetails[punishedOrderId];
      internalDeleteOrder(order, punishedOrderId);
      applyPenalty(taker, gasUsed, orderDetail);
      failureIndex++;
    }
  }

  function internalPunishingMarketOrderFrom(
    uint orderId,
    uint takerWants,
    uint takerGives,
    uint punishLength
  ) external returns (bytes memory) {
    // must wrap this to avoid bubbling up "fake failures" from other calls.
    (bool noRevert, bytes memory retdata) = address(this).delegatecall(
      abi.encodeWithSelector(
        internalMarketOrderSelector,
        takerWants,
        takerGives,
        punishLength,
        orderId
      )
    );

    // MarketOrder finished w/o reverting
    // Failing orders have been collected in [failures]
    if (noRevert) {
      // `retdata` encodes a uint[] array of failed orders.
      evmRevert(retdata);
      // Market order failed to complete.
    } else {
      // `retdata` is revert data
      return retdata;
    }
  }

  function internalPunishingSnipes(uint[] calldata targets, uint punishLength)
    external
    returns (bytes memory)
  {
    (bool noRevert, bytes memory retdata) = address(this).delegatecall(
      abi.encodeWithSelector(internalSnipesSelector, targets, punishLength)
    );

    // MarketOrder finished w/o reverting
    // Failing orders have been collected in [failures]
    if (noRevert) {
      // `retdata` encodes a uint[] array of failed orders.
      evmRevert(retdata);
      // Market order failed to complete.
    } else {
      // `retdata` is revert data
      return retdata;
    }
  }
}
