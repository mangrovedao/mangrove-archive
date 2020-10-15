// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./interfaces.sol";

//import "@nomiclabs/buidler/console.sol";

contract Dex {
  struct Order {
    uint32 prev; // better orderm
    uint32 next; // worse order
    uint96 wants; // amount requested in OFR_TOKEN
    uint96 gives; // amount on order in REQ_TOKEN
  }

  struct OrderDetail {
    uint24 gasWanted; // gas requested
    uint24 minFinishGas; // global minFinishGas at order creation time
    uint48 penaltyPerGas; // global penaltyPerGas at order creation time
    address maker;
  }

  uint public takerFee; // in basis points
  uint private best; // (32)
  uint public minFinishGas; // (24) min gas available
  uint public dustPerGasWanted; // (32) min amount to offer per gas requested, in OFR_TOKEN;
  uint public minGasWanted; // (32) minimal amount of gas you can ask for; also used for market order's dust estimation
  bool public open = true; // a closed market cannot make/take orders
  uint public penaltyPerGas; // (48) in wei;
  IERC20 public immutable OFR_TOKEN; // ofr_token is the token orders give
  IERC20 public immutable REQ_TOKEN; // req_token is the token orders wants

  address private admin;
  bool public accessOB = true; // whether a modification of the OB is permitted
  uint private lastId = 0; // (32)
  uint private transferGas = 2300; //default amount of gas given for a transfer

  mapping(uint => Order) private orders;
  mapping(uint => OrderDetail) private orderDetails;
  mapping(address => uint) freeWei;

  // TODO low gascost bookkeeping methods
  //updateOrder(constant price)
  //updateOrder(change price)

  constructor(
    address initialAdmin,
    uint initialDustPerGasWanted,
    uint initialMinFinishGas,
    uint initialPenaltyPerGas,
    uint initialMinGasWanted,
    IERC20 ofrToken,
    IERC20 reqToken
  ) {
    admin = initialAdmin;
    setDustPerGasWanted(initialDustPerGasWanted);
    setMinFinishGas(initialMinFinishGas);
    setPenaltyPerGas(initialPenaltyPerGas);
    setMinGasWanted(initialMinGasWanted);
    OFR_TOKEN = ofrToken;
    REQ_TOKEN = reqToken;
  }

  function getLastId() public view returns (uint) {
    require(accessOB, "OB not accessible");
    return lastId;
  }

  //Emulates the transfer function, but with adjustable gas transfer
  function dexTransfer(address payable addr, uint amount) internal {
    (bool success, ) = addr.call{gas: transferGas, value: amount}("");
    require(success, "dexTransfer failed");
  }

  function getBest() external view returns (uint) {
    require(accessOB, "OB not accessible");
    return best;
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
      address
    )
  {
    require(accessOB); // to prevent frontrunning attacks
    Order memory order = orders[orderId];
    OrderDetail memory orderDetail = orderDetails[orderId];
    return (
      order.wants,
      order.gives,
      orderDetail.gasWanted,
      orderDetail.minFinishGas, // global minFinishGas at order creation time
      orderDetail.penaltyPerGas, // global penaltyPerGas at order creation time
      orderDetail.maker
    );
  }

  function isAdmin(address maybeAdmin) internal view returns (bool) {
    return maybeAdmin == admin;
  }

  function updateAdmin(address newValue) external {
    if (isAdmin(msg.sender)) {
      admin = newValue;
    }
  }

  function updateTransferGas(uint gas) external {
    if (isAdmin(msg.sender)) {
      transferGas = gas;
    }
  }

  function closeMarket() external {
    if (isAdmin(msg.sender)) {
      open = false;
    }
  }

  function setDustPerGasWanted(uint newValue) internal {
    require(newValue > 0, "dustPerGasWanted must be > 0");
    require(uint32(newValue) == newValue);
    dustPerGasWanted = newValue;
  }

  function setTakerFee(uint newValue) internal {
    require(newValue <= 10000, "takerFee is in bps, must be <= 10000"); // at most 14 bits
    takerFee = newValue;
  }

  function setMinFinishGas(uint newValue) internal {
    require(uint24(newValue) == newValue, "minFinishGas is 24 bits wide");
    minFinishGas = newValue;
  }

  function setPenaltyPerGas(uint newValue) internal {
    require(uint48(newValue) == newValue, "penaltyPerGas is 48 bits wide");
    penaltyPerGas = newValue;
  }

  function setMinGasWanted(uint newValue) internal {
    require(uint32(newValue) == newValue, "minGasWanted is 32 bits wide");
    minGasWanted = newValue;
  }

  function updateDustPerGasWanted(uint newValue) external {
    if (isAdmin(msg.sender)) {
      setDustPerGasWanted(newValue);
    }
  }

  function updateTakerFee(uint newValue) external {
    if (isAdmin(msg.sender)) {
      setTakerFee(newValue);
    }
  }

  function updateMinFinishGas(uint newValue) external {
    if (isAdmin(msg.sender)) {
      setMinFinishGas(newValue);
    }
  }

  function updatePenaltyPerGas(uint newValue) external {
    if (isAdmin(msg.sender)) {
      setPenaltyPerGas(newValue);
    }
  }

  function updateMinGasWanted(uint newValue) external {
    if (isAdmin(msg.sender)) {
      setMinGasWanted(newValue);
    }
  }

  function isOrder(Order memory order) internal pure returns (bool) {
    return order.gives > 0;
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
    require(accessOB, "reentrancy not allowed on OB functions");
    OrderDetail memory orderDetail = orderDetails[orderId];
    if (msg.sender == orderDetail.maker) {
      Order memory order = orders[orderId];
      deleteOrder(order, orderId);
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
    require(open, "no new order on closed market");
    require(accessOB, "reentrancy not allowed on OB functions");
    require(gives >= gasWanted * dustPerGasWanted, "offering below dust limit");
    require(uint96(wants) == wants, "wants is 96 bits wide");
    require(uint96(gives) == gives, "gives is 96 bits wide");
    require(uint24(gasWanted) == gasWanted, "gasWanted is 24 bits wide");
    require(gasWanted > 0, "gasWanted > 0"); // division by gasWanted occurs later
    require(uint32(pivotId) == pivotId, "pivotId is 32 bits wide");

    (uint32 prev, uint32 next) = findPosition(wants, gives, pivotId);

    uint maxPenalty = (gasWanted + minFinishGas) * penaltyPerGas;
    //require(freeWei[msg.sender] >= maxPenalty, "insufficient penalty provision to create order");
    freeWei[msg.sender] -= maxPenalty;

    uint32 orderId = uint32(++lastId);

    //TODO Check if Solidity optimizer prefers this or orders[i].a = a'; ... ; orders[i].b = b'
    orders[orderId] = Order({
      prev: prev,
      next: next,
      wants: uint96(wants),
      gives: uint96(gives)
    });

    orderDetails[orderId] = OrderDetail({
      gasWanted: uint24(gasWanted),
      minFinishGas: uint24(minFinishGas),
      penaltyPerGas: uint48(penaltyPerGas),
      maker: msg.sender
    });

    if (prev != 0) {
      orders[prev].next = orderId;
    } else {
      best = orderId;
    }

    if (next != 0) {
      orders[next].prev = orderId;
    }
    return orderId;
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

  // 1. add a ghost order orderId with (want,gives) in the right position
  //    you should make sure that the order orderId has the correct price
  // 2. not trying to be a stable sort
  //    but giving privilege to earlier orders
  // 3. to use the least gas, consider which orders would surround yours (with older orders being sorted first)
  //    give any of those as _refId
  //    no analysis was done if garbage ids are allowed
  function findPosition(
    uint wants,
    uint gives,
    uint pivotId
  ) internal view returns (uint32, uint32) {
    Order memory pivot = orders[pivotId];

    if (!isOrder(pivot)) {
      // in case pivotId is not or no longer a valid order
      pivot = orders[best];
      pivotId = best;
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

  function min(uint a, uint b) internal pure returns (uint) {
    return a < b ? a : b;
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

  // ask for a volume by setting takerWants to however much you want and
  // takerGive to max_uint. Any price will be accepted.

  // ask for an average price by setting takerGives such that gives/wants is the price

  // there is no limit price setting

  // setting takerWants to max_int and takergives to however much you're ready to spend will
  // not work, you'll just be asking for a ~0 price.
  function internalMarketOrderFrom(
    uint takerWants,
    uint takerGives,
    uint punishLength,
    uint orderId,
    address payable taker
  ) internal returns (uint[] memory) {
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
    while (takerWants >= dustPerGasWanted * minGasWanted && orderId != 0) {
      // is the taker ready to take less per unit than the maker is ready to give per unit?
      // takerWants/takerGives <= order.ofrAmount / order.reqAmount
      // here we normalize how much the maker would ask for takerWant

      uint makerWouldWant = (takerWants * order.wants) / order.gives;
      if (makerWouldWant <= takerGives) {
        // price is OK for taker
        localTakerWants = min(order.gives, takerWants); // the result of this determines the next line
        localTakerGives = min(order.wants, makerWouldWant);

        //if success, gasUsedForFailure == 0
        //Warning: orderId is deleted *after* execution
        (bool success, uint gasUsedForFailure) = flashSwapTokens(
          order,
          orderId,
          localTakerWants,
          localTakerGives,
          taker
        );

        if (success) {
          //proceeding with market order
          takerWants -= localTakerWants;
          takerGives -= localTakerGives;
          if (
            order.gives - localTakerWants >= dustPerGasWanted * minGasWanted
          ) {
            orders[orderId].gives = uint96(order.gives - localTakerWants);
            orders[orderId].wants = uint96(order.wants - localTakerGives);
          } else {
            _deleteOrder(orderId);
          }
        } else {
          _deleteOrder(orderId);
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
    require(open, "no new order on closed market");
    require(accessOB, "reentrancy not allowed on OB functions");
    require(uint32(orderId) == orderId, "orderId is 32 bits wide");
    require(uint96(takerWants) == takerWants, "takerWants is 96 bits wide");

    Order memory order = orders[orderId];
    require(isOrder(order), "bad orderId");

    (bool success, ) = executeOrder(orderId, order, takerWants, msg.sender);
    require(success, "execute order failed");
  }

  function snipes(uint[] calldata targets) external {
    require(open, "no new order on closed market");
    require(accessOB, "reentrancy not allowed on OB functions");

    internalSnipes(targets, 0, msg.sender);
  }

  function internalSnipes(
    uint[] calldata targets,
    uint punishLength,
    address payable taker
  ) internal returns (uint[] memory) {
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
          taker
        );
        if (!success && numFailures < punishLength) {
          failures[2 * numFailures] = orderId;
          failures[2 * numFailures + 1] = gasUsed;
          numFailures++;
        }
      }
      targetIndex++;
      accessOB = true;
    }
    assembly {
      mstore(failures, mul(2, numFailures))
    } /* reduce failures array size */
    return failures;
  }

  // implements a market order with condition on the minimal delivered volume
  function conditionalMarketOrder(uint takerWants, uint takerGives) external {
    internalMarketOrderFrom(takerWants, takerGives, 0, best, msg.sender);
  }

  function stitchOrders(uint past, uint future) internal {
    if (past != 0) {
      orders[past].next = uint32(future);
    } else {
      best = future;
    }

    if (future != 0) {
      orders[future].prev = uint32(past);
    }
  }

  function _deleteOrder(uint orderId) internal {
    delete orders[orderId];
    delete orderDetails[orderId];
  }

  function deleteOrder(Order memory order, uint orderId) internal {
    _deleteOrder(orderId);
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
    uint localTakerWants = min(order.gives, takerWants);
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

    if (order.gives - localTakerWants >= dustPerGasWanted * minGasWanted) {
      orders[orderId].gives = uint96(order.gives - localTakerWants);
      orders[orderId].wants = uint96(order.wants - localTakerGives);
    } else {
      deleteOrder(order, orderId);
    }
    return (success, gasUsed);
  }

  function applyPenalty(
    address payable sender,
    uint gasUsed,
    OrderDetail memory orderDetail
  ) internal {
    uint maxPenalty = (orderDetail.gasWanted + orderDetail.minFinishGas) *
      orderDetail.penaltyPerGas;

    //is gasUsed covering enough operation?
    uint penalty = min(gasUsed * orderDetail.penaltyPerGas, maxPenalty);

    freeWei[orderDetail.maker] += maxPenalty - penalty;
    dexTransfer(sender, penalty);
  }

  // swap tokens according to parameters.
  // trusts caller
  // uses flashlend to ensure postcondition
  function flashSwapTokens(
    Order memory order,
    uint orderId,
    uint takerGives,
    uint takerWants,
    address payable sender
  ) internal returns (bool, uint) {
    OrderDetail memory orderDetail = orderDetails[orderId];

    // Execute order
    uint oldGas = gasleft();

    require(
      oldGas >= orderDetail.gasWanted + minFinishGas,
      "not enough gas left to safely execute order"
    );

    uint dexFee = (takerFee +
      (takerFee * dustPerGasWanted * orderDetail.gasWanted) /
      order.gives) / 2;

    try
      this.swapTokens(
        orderId,
        sender,
        takerGives,
        takerWants,
        orderDetail.gasWanted,
        orderDetail.penaltyPerGas,
        orderDetail.maker,
        dexFee
      )
    returns (bool flashSuccess) {
      uint gasUsed = oldGas - gasleft();
      require(flashSuccess, "taker failed to send tokens to maker");
      applyPenalty(sender, 0, orderDetail);
      return (true, gasUsed);
    } catch (
      bytes memory /*reason*/
    ) {
      uint gasUsed = oldGas - gasleft();
      applyPenalty(sender, gasUsed, orderDetail);
      return (false, gasUsed);
    }
  }

  // swap tokens, no checks except msg.sender, throws if bad postcondition
  function swapTokens(
    uint orderId,
    address taker,
    uint takerGives,
    uint takerWants,
    uint32 orderGasWanted,
    uint64 orderPenaltyPerGas,
    address orderMaker,
    uint dexFee
  ) external returns (bool) {
    require(msg.sender == address(this), "caller must be dex");

    if (transferToken(REQ_TOKEN, taker, orderMaker, takerGives)) {
      // Execute order
      IMaker(orderMaker).execute{gas: orderGasWanted}(
        takerWants,
        takerGives,
        orderPenaltyPerGas,
        orderId
      );

      require(
        transferToken(
          OFR_TOKEN,
          orderMaker,
          address(this),
          (takerWants * dexFee) / 10000
        ),
        "fail transfer to dex"
      );
      require(
        transferToken(
          OFR_TOKEN,
          orderMaker,
          taker,
          (takerWants * (10000 - takerFee)) / 10000
        ),
        "fail transfer to taker"
      );
      return true;
    } else {
      return false;
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
    try
      this.internalPunishingMarketOrderFrom(
        fromOrderId,
        takerWants,
        takerGives,
        punishLength,
        msg.sender
      )
    returns (bytes memory error) {
      evmRevert(error);
    } catch (bytes memory failureBytes) {
      punish(failureBytes, msg.sender);
    }
  }

  function punishingSnipes(uint[] calldata targets, uint punishLength)
    external
  {
    try
      this.internalPunishingSnipes(targets, punishLength, msg.sender)
    returns (bytes memory error) {
      evmRevert(error);
    } catch (bytes memory failureBytes) {
      punish(failureBytes, msg.sender);
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
      deleteOrder(order, punishedOrderId);
      applyPenalty(taker, gasUsed, orderDetail);
      failureIndex++;
    }
  }

  function internalPunishingMarketOrderFrom(
    uint orderId,
    uint takerWants,
    uint takerGives,
    uint punishLength,
    address payable taker
  ) external returns (bytes memory) {
    // must wrap this to avoid bubbling up "fake failures" from other calls.
    require(msg.sender == address(this), "caller must be dex");
    try
      this.secureInternalMarketOrderFrom(
        takerWants,
        takerGives,
        punishLength,
        orderId,
        taker
      )
    returns (uint[] memory failures) {
      // MarketOrder finished w/o reverting
      // Failing orders have been collected in [failures]
      evmRevert(failures);
    } catch (bytes memory error) {
      return error; // Market order failed to complete.
    }
  }

  function secureInternalMarketOrderFrom(
    uint takerWants,
    uint takerGives,
    uint punishLength,
    uint orderId,
    address payable taker
  ) external returns (uint[] memory) {
    require(msg.sender == address(this), "caller must be dex");
    return
      internalMarketOrderFrom(
        takerWants,
        takerGives,
        punishLength,
        orderId,
        taker
      );
  }

  function internalPunishingSnipes(
    uint[] calldata targets,
    uint punishLength,
    address payable taker
  ) external returns (bytes memory) {
    require(msg.sender == address(this), "caller must be dex");
    try this.secureInternalSnipes(targets, punishLength, taker) returns (
      uint[] memory failures
    ) {
      evmRevert(failures);
    } catch (bytes memory error) {
      return error;
    }
  }

  function secureInternalSnipes(
    uint[] calldata targets,
    uint punishLength,
    address payable taker
  ) external returns (uint[] memory) {
    require(msg.sender == address(this), "caller must be dex");
    return internalSnipes(targets, punishLength, taker);
  }

  // Avoid "no return value" bug
  // https://soliditydeveloper.com/safe-erc20
  function transferToken(
    IERC20 token,
    address from,
    address to,
    uint value
  ) internal returns (bool) {
    bytes memory cd = abi.encodeWithSelector(
      token.transferFrom.selector,
      from,
      to,
      value
    );
    (bool success, bytes memory data) = address(token).call(cd);
    return (success && (data.length == 0 || abi.decode(data, (bool))));
  }
}
