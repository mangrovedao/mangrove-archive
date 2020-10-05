// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./interfaces.sol";
import "@nomiclabs/buidler/console.sol";

contract Dex {
  struct Order {
    uint32 prev; // better order
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

  uint256 public takerFee; // in basis points
  uint256 private best; // (32)
  uint256 public minFinishGas; // (24) min gas available
  uint256 public dustPerGasWanted; // (32) min amount to offer per gas requested, in OFR_TOKEN;
  uint256 public minGasWanted; // (32) minimal amount of gas you can ask for; also used for market order's dust estimation
  bool public open = true; // a closed market cannot make/take orders
  // TODO Do not remove offer when partially filled
  uint256 public penaltyPerGas; // (48) in wei;
  IERC20 public immutable OFR_TOKEN; // ofr_token is the token orders give
  IERC20 public immutable REQ_TOKEN; // req_token is the token orders wants

  address private admin;
  address private immutable THIS; // prevent a delegatecall entry into _executeOrder.
  bool public accessOB = true; // whether a modification of the OB is permitted
  uint256 private lastId = 0; // (32)
  uint256 private transferGas = 2300; //default amount of gas given for a transfer

  mapping(uint256 => Order) private orders;
  mapping(uint256 => OrderDetail) private orderDetails;
  mapping(address => uint256) freeWei;

  // TODO low gascost bookkeeping methods
  //updateOrder(constant price)
  //updateOrder(change price)

  constructor(
    address initialAdmin,
    uint256 initialDustPerGasWanted,
    uint256 initialMinFinishGas,
    uint256 initialPenaltyPerGas,
    uint256 initialMinGasWanted,
    IERC20 ofrToken,
    IERC20 reqToken
  ) {
    admin = initialAdmin;
    THIS = address(this);
    setDustPerGasWanted(initialDustPerGasWanted);
    setMinFinishGas(initialMinFinishGas);
    setPenaltyPerGas(initialPenaltyPerGas);
    setMinGasWanted(initialMinGasWanted);
    OFR_TOKEN = ofrToken;
    REQ_TOKEN = reqToken;
  }

  //Emulates the transfer function, but with adjustable gas transfer
  function dexTransfer(address payable addr, uint256 amount) internal {
    (bool success, ) = addr.call{gas: transferGas, value: amount}("");
    require(success, "dexTransfer failed");
  }

  // Splits a uint32 n into 4 bytes in array b, starting from position start.
  function push32ToBytes(
    uint32 n,
    bytes memory b,
    uint256 start
  ) internal pure {
    for (uint256 i = 0; i < 4; i++) {
      b[start + i] = bytes1(uint8(n / (2**(8 * (3 - i)))));
    }
  }

  function getBest() external view returns (uint256) {
    require(accessOB, "OB not accessible");
    return best;
  }

  function getOrderInfo(uint256 orderId) external view
  returns (uint96,uint96,uint24,uint24,uint48,address){
    require(accessOB); // to prevent frontrunning attacks
    Order memory order = orders[orderId];
    if (isOrder(order)){
      OrderDetail memory orderDetail = orderDetails[orderId];
      return (
        order.wants,
        order.gives,
        orderDetail.gasWanted,
        orderDetail.minFinishGas, // global minFinishGas at order creation time
        orderDetail.penaltyPerGas, // global penaltyPerGas at order creation time
        orderDetail.maker) ;
      }
    else {
      return (0,0,0,0,0,address(0));
    }
  }

  function push32PairToBytes(
    uint32 n,
    uint32 m,
    bytes memory b,
    uint256 start
  ) internal pure {
    push32ToBytes(n, b, 8 * start);
    push32ToBytes(m, b, 8 * start + 4);
  }

  function pull32FromBytes(bytes memory b, uint256 start)
    internal
    pure
    returns (uint32 n)
  {
    for (uint256 i = 0; i < 4; i++) {
      n = n + uint32(uint8(b[start + i]) * (2**(8 * (3 - i))));
    }
  }

  function pull32PairFromBytes(bytes memory b, uint256 start)
    internal
    pure
    returns (uint32 n, uint32 m)
  {
    n = pull32FromBytes(b, 8 * start);
    m = pull32FromBytes(b, 8 * start + 4);
  }

  function isAdmin(address maybeAdmin) internal view returns (bool) {
    return maybeAdmin == admin;
  }

  function updateAdmin(address newValue) external {
    if (isAdmin(msg.sender)) {
      admin = newValue;
    }
  }

  function updateTransferGas(uint256 gas) external {
    if (isAdmin(msg.sender)) {
      transferGas = gas;
    }
  }

  function closeMarket() external {
    if (isAdmin(msg.sender)) {
      open = false;
    }
  }

  function setDustPerGasWanted(uint256 newValue) internal {
    require(newValue > 0, "dustPerGasWanted must be > 0");
    require(uint32(newValue) == newValue);
    dustPerGasWanted = newValue;
  }

  function setTakerFee(uint256 newValue) internal {
    require(newValue <= 10000, "takerFee is in bps, must be <= 10000"); // at most 14 bits
    takerFee = newValue;
  }

  function setMinFinishGas(uint256 newValue) internal {
    require(uint24(newValue) == newValue, "minFinishGas is 24 bits wide");
    minFinishGas = newValue;
  }

  function setPenaltyPerGas(uint256 newValue) internal {
    require(uint48(newValue) == newValue, "penaltyPerGas is 48 bits wide");
    penaltyPerGas = newValue;
  }

  function setMinGasWanted(uint256 newValue) internal {
    require(uint32(newValue) == newValue, "minGasWanted is 32 bits wide");
    minGasWanted = newValue;
  }

  function updateDustPerGasWanted(uint256 newValue) external {
    if (isAdmin(msg.sender)) {
      setDustPerGasWanted(newValue);
    }
  }

  function updateTakerFee(uint256 newValue) external {
    if (isAdmin(msg.sender)) {
      setTakerFee(newValue);
    }
  }

  function updateMinFinishGas(uint256 newValue) external {
    if (isAdmin(msg.sender)) {
      setMinFinishGas(newValue);
    }
  }

  function updatePenaltyPerGas(uint256 newValue) external {
    if (isAdmin(msg.sender)) {
      setPenaltyPerGas(newValue);
    }
  }

  function updateMinGasWanted(uint256 newValue) external {
    if (isAdmin(msg.sender)) {
      setMinGasWanted(newValue);
    }
  }

  function isOrder(Order memory order) internal pure returns (bool) {
    return order.gives > 0;
  }

  function balanceOf(address maker) external view returns (uint256) {
    return freeWei[maker];
  }

  receive() external payable {
    freeWei[msg.sender] += msg.value;
  }

  function withdraw(uint256 amount) external {
    require(
      freeWei[msg.sender] >= amount,
      "cannot withdraw more than available in freeWei"
    );
    freeWei[msg.sender] -= amount;
    dexTransfer(msg.sender, amount);
  }

  function cancelOrder(uint256 orderId) external returns (uint256) {
    require(accessOB, "OB not accessible");
    OrderDetail memory orderDetail = orderDetails[orderId];
    if (msg.sender == orderDetail.maker) {
      Order memory order = orders[orderId];
      deleteOrder(order, orderId);
      // Freeing provisioned penalty for maker
      uint256 provision = orderDetail.penaltyPerGas * orderDetail.gasWanted;
      freeWei[msg.sender] += provision;
      return provision;
    }
    return 0;
  }

  function newOrder(
    uint256 wants,
    uint256 gives,
    uint256 gasWanted,
    uint256 pivotId
  ) external returns (uint256) {
    require(open, "no new order on closed market");
    require(accessOB, "OB not modifiable");
    require(gives >= gasWanted * dustPerGasWanted, "offering below dust limit");
    require(uint96(wants) == wants, "wants is 96 bits wide");
    require(uint96(gives) == gives, "gives is 96 bits wide");
    require(uint24(gasWanted) == gasWanted, "gasWanted is 24 bits wide");
    require(gasWanted > 0, "gasWanted > 0"); // division by gasWanted occurs later
    require(uint32(pivotId) == pivotId, "pivotId is 32 bits wide");

    (uint32 prev, uint32 next) = findPosition(wants, gives, pivotId);

    uint256 maxPenalty = (gasWanted + minFinishGas) * penaltyPerGas;
    //require(freeWei[msg.sender] >= maxPenalty, "insufficient penalty provision to create order");
    freeWei[msg.sender] -= maxPenalty;

    uint32 orderId = uint32(++lastId);

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
    uint256 wants1,
    uint256 gives1,
    uint256 wants2,
    uint256 gives2
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
    uint256 wants,
    uint256 gives,
    uint256 pivotId
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

  function min(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
  }

  function evmRevert(bytes memory data) internal pure {
    uint256 length = data.length;
    assembly {
      revert(data, add(length, 32))
    }
  }

  // ask for a volume by setting takerWants to however much you want and
  // takerGive to max_uint. Any price will be accepted.

  // ask for an average price by setting takerGives such that gives/wants is the price

  // there is no limit price setting

  // setting takerWants to max_int and takergives to however much you're ready to spend will
  // not work, you'll just be asking for a ~0 price.
  function marketOrderFrom(
    uint256 takerWants,
    uint256 takerGives,
    uint256 snipeLength,
    uint256 orderId,
    address payable sender
  ) public returns (bytes memory) {
    require(uint32(orderId) == orderId, "orderId is 32 bits wide");
    require(uint96(takerWants) == takerWants, "takerWants is 96 bits wide");
    require(uint96(takerGives) == takerGives, "takerGives is 96 bits wide");

    uint256 localTakerWants;
    uint256 localTakerGives;
    Order memory order = orders[orderId];
    require(isOrder(order), "invalid order");
    uint256 pastOrderId = order.prev;

    bytes memory failures = new bytes(8 * snipeLength);
    uint256 failureIndex;

    accessOB = false;
    // inlining (minTakerWants = dustPerGasWanted*minGasWanted) to avoid stack too deep
    while (takerWants >= dustPerGasWanted * minGasWanted && orderId != 0) {
      // is the taker ready to take less per unit than the maker is ready to give per unit?
      // takerWants/takerGives <= order.ofrAmount / order.reqAmount
      // here we normalize how much the maker would ask for takerWant

      uint256 makerWouldWant = (takerWants * order.wants) / order.gives;
      if (makerWouldWant <= takerGives) {
        // price is OK for taker
        localTakerWants = min(order.gives, takerWants); // the result of this determines the next line
        localTakerGives = min(order.wants, makerWouldWant);

        //if success, gasUsedForFailure == 0
        //Warning: orderId is deleted *after* execution
        (bool success, uint256 gasUsedForFailure) = executeOrder(
          order,
          orderId,
          localTakerWants,
          localTakerGives,
          sender
        );
        _deleteOrder(orderId);

        if (success) {
          //proceeding with market order
          takerWants -= localTakerWants;
          takerGives -= localTakerGives;
        } else if (failureIndex < snipeLength) {
          // storing orderId and gas used for cancellation
          push32PairToBytes(
            uint32(orderId),
            uint32(gasUsedForFailure),
            failures,
            failureIndex++
          );
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
    return failures;
  }

  function _snipingMarketOrderFrom(
    uint256 orderId,
    uint256 takerWants,
    uint256 takerGives,
    uint256 snipeLength,
    address payable sender
  ) external returns (bytes memory) {
    require(msg.sender == THIS, "caller must be dex");
    // must wrap this to avoid bubbling up "fake failures" from other calls.
    try
      this.marketOrderFrom(takerWants, takerGives, snipeLength, orderId, sender)
    returns (bytes memory failures) {
      // MarketOrder finished w/o reverting
      // Failing orders have been collected in [failures]
      evmRevert(failures);
    } catch (bytes memory e) {
      return e; // Market order failed to complete.
    }
  }

  // run and revert a market order so as to collect orderId's that are failing
  // snipeLength is the number of failing orders one is trying to catch
  function snipingMarketOrderFrom(
    uint256 fromOrderId,
    uint256 takerWants,
    uint256 takerGives,
    uint256 snipeLength
  ) external {
    try
      this._snipingMarketOrderFrom(
        fromOrderId,
        takerWants,
        takerGives,
        snipeLength,
        msg.sender
      )
    returns (bytes memory error) {
      evmRevert(error);
    } catch (bytes memory failures) {
      uint256 failureIndex;
      while (failureIndex < failures.length) {
        (uint32 snipedOrderId, uint32 gasUsed) = pull32PairFromBytes(
          failures,
          failureIndex++
        );
        Order memory order = orders[snipedOrderId];
        OrderDetail memory orderDetail = orderDetails[snipedOrderId];
        deleteOrder(order, snipedOrderId);
        applyPenalty(msg.sender, gasUsed, orderDetail);
      }
    }
  }

  // implements a market order with condition on the minimal delivered volume
  function conditionalMarketOrder(uint256 takerWants, uint256 takerGives)
    external
  {
    marketOrderFrom(takerWants, takerGives, 0, best, msg.sender);
  }

  function stitchOrders(uint256 past, uint256 future) internal {
    if (past != 0) {
      orders[past].next = uint32(future);
    } else {
      best = future;
    }

    if (future != 0) {
      orders[future].prev = uint32(past);
    }
  }

  function _deleteOrder(uint256 orderId) internal {
    delete orders[orderId];
    delete orderDetails[orderId];
  }

  function deleteOrder(Order memory order, uint256 orderId) internal {
    _deleteOrder(orderId);
    stitchOrders(order.prev, order.next);
  }

  function externalExecuteOrder(
    //snipe order
    uint256 orderId,
    uint256 takerWants
  ) external {
    require(open, "no new order on closed market");
    require(accessOB, "OB not modifiable");
    require(uint32(orderId) == orderId, "orderId is 32 bits wide");
    require(uint96(takerWants) == takerWants, "takerWants is 96 bits wide");

    Order memory order = orders[orderId];
    require(isOrder(order), "invalid order");

    uint256 localTakerWants = min(order.gives, takerWants);
    uint256 localTakerGives = (localTakerWants * order.wants) / order.gives;

    modifyOB = false;
    (bool success, ) = executeOrder(
      order,
      orderId,
      localTakerGives,
      localTakerWants,
      msg.sender
    );
    require(success, "maker could not complete trade");
    modifyOB = true;

    deleteOrder(order, orderId);
  }

  function applyPenalty(
    address payable sender,
    uint256 gasUsed,
    OrderDetail memory orderDetail
  ) internal {
    uint256 maxPenalty = (orderDetail.gasWanted + orderDetail.minFinishGas) *
      orderDetail.penaltyPerGas;

    //is gasUsed covering enough operation?
    uint256 penalty = min(gasUsed * orderDetail.penaltyPerGas, maxPenalty);

    freeWei[orderDetail.maker] += maxPenalty - penalty;
    dexTransfer(sender, penalty);
  }

  function executeOrder(
    Order memory order,
    uint256 orderId,
    uint256 takerGives,
    uint256 takerWants,
    address payable sender
  ) internal returns (bool, uint256) {
    OrderDetail memory orderDetail = orderDetails[orderId];

    // Execute order
    uint256 oldGas = gasleft();

    require(
      oldGas >= orderDetail.gasWanted + minFinishGas,
      "not enough gas left to safely execute order"
    );

    uint256 dexFee = (takerFee +
      (takerFee * dustPerGasWanted * orderDetail.gasWanted) /
      order.gives) / 2;

    try
      this._executeOrder(
        orderId,
        sender,
        takerGives,
        takerWants,
        orderDetail.gasWanted,
        orderDetail.maker,
        dexFee
      )
    returns (bool flashSuccess) {
      uint256 gasUsed = oldGas - gasleft();
      require(flashSuccess, "taker failed to send tokens to maker");
      applyPenalty(sender, 0, orderDetail);
      return (true, gasUsed);
    } catch (
      bytes memory /*reason*/
    ) {
      uint256 gasUsed = oldGas - gasleft();
      applyPenalty(sender, gasUsed, orderDetail);
      return (false, gasUsed);
    }
  }

  function _executeOrder(
    uint256 orderId,
    address taker,
    uint256 takerGives,
    uint256 takerWants,
    uint32 orderGasWanted,
//    uint64 orderPenaltyPerGas,
    address orderMaker,
    uint256 dexFee
  ) external returns (bool) {
    require(msg.sender == THIS, "caller must be dex");

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
          THIS,
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

  // Avoid "no return value" bug
  // https://soliditydeveloper.com/safe-erc20
  function transferToken(
    IERC20 token,
    address from,
    address to,
    uint256 value
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
