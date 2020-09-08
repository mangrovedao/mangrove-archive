// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

interface ERC20 {
  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);
}

interface Maker {
  // Maker should check msg.sender is Dex[REQ_TOKEN][OFR_TOKEN] or remember its orders
  function execute(
    uint256 takerWants,
    uint256 takerGives,
    uint64 orderPenaltyPerGas
  ) external;
}

contract Dex {
  struct Order {
    uint32 prev; // better order
    uint32 next; // worse order
    uint96 wants; // amount requested in OFR_TOKEN
    uint96 gives; // amount on order in REQ_TOKEN
  }

  struct OrderDetail {
    uint32 gasWanted; // gas requested
    uint64 penaltyPerGas;
    address maker;
  }

  uint256 public takerFee; // in basis points
  uint256 public best; // (32)
  uint256 public minFinishGas; // (32) min gas available
  uint256 public dustPerGasWanted; // (32) min amount to offer per gas requested, in OFR_TOKEN;
  uint256 public minGasWanted; // (32) minimal amount of gas you can ask for; also used for market order's dust estimation
  bool public open = true; // a closed market cannot make/take orders
  // TODO Do not remove offer when partially filled
  uint256 public penaltyPerGas; // (32) in wei;
  address public immutable REQ_TOKEN; // req_token is the token orders wants
  address public immutable OFR_TOKEN; // ofr_token is the token orders give

  address private admin;
  address private immutable THIS; // prevent a delegatecall entry into _executeOrder.
  bool private modifyOB = true; // whether a modification of the OB is permitted
  uint256 private lastId = 0; // (32)
  uint256 private transferGas = 2300; //default amount of gas given for a transfer

  mapping(uint256 => Order) orders;
  mapping(uint256 => OrderDetail) orderDetails;
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
    address reqToken,
    address ofrToken
  ) {
    admin = initialAdmin;
    THIS = address(this);
    setDustPerGasWanted(initialDustPerGasWanted);
    setMinFinishGas(initialMinFinishGas);
    setPenaltyPerGas(initialPenaltyPerGas);
    setMinGasWanted(initialMinGasWanted);
    REQ_TOKEN = reqToken;
    OFR_TOKEN = ofrToken;
  }

  //Emulates the transfer function, but with adjustable gas transfer
  function dexTransfer(address payable addr, uint256 amount) internal {
    (bool success, ) = addr.call{gas: transferGas, value: amount}("");
    require(success);
  }

  function isAdmin(address maybeAdmin) internal view returns (bool) {
    return maybeAdmin == admin;
  }

  function updateOwner(address newValue) external {
    if (isAdmin(msg.sender)) {
      admin = newValue;
    }
  }

  function closeMarket() external {
    if (isAdmin(msg.sender)) {
      open = false;
    }
  }

  function setDustPerGasWanted(uint256 newValue) internal {
    require(newValue > 0);
    require(uint32(newValue) == newValue);
    dustPerGasWanted = newValue;
  }

  function setTakerFee(uint256 newValue) internal {
    require(newValue <= 10000); // at most 14 bits
    takerFee = newValue;
  }

  function setMinFinishGas(uint256 newValue) internal {
    require(uint32(newValue) == newValue);
    minFinishGas = newValue;
  }

  function setPenaltyPerGas(uint256 newValue) internal {
    require(uint64(newValue) == newValue);
    penaltyPerGas = newValue;
  }

  function setMinGasWanted(uint256 newValue) internal {
    require(uint32(newValue) == newValue);
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

  function balanceOf(address maker) external returns (uint256) {
    return freeWei[maker];
  }

  receive() external payable {
    freeWei[msg.sender] += msg.value;
  }

  function withdraw(uint256 amount) external {
    require(freeWei[msg.sender] >= amount);
    freeWei[msg.sender] -= amount;
    dexTransfer(msg.sender, amount);
  }

  function cancelOrder(uint256 orderId) external {
    require(modifyOB);
    OrderDetail memory orderDetail = orderDetails[orderId];
    if (msg.sender == orderDetail.maker) {
      Order memory order = orders[orderId];
      deleteOrder(order, orderId);
      freeWei[msg.sender] += orderDetail.penaltyPerGas * orderDetail.gasWanted;
    }
  }

  function newOrder(
    uint256 wants,
    uint256 gives,
    uint256 gasWanted,
    uint256 pivotId
  ) external returns (uint356) {
    require(open);
    require(modifyOB);
    require(gives >= gasWanted * dustPerGasWanted);
    require(uint96(wants) == wants);
    require(uint96(gives) == gives);
    require(uint32(gasWanted) == gasWanted);
    require(gasWanted > 0); // division by gasWanted occurs later
    require(uint32(pivotId) == pivotId);

    (uint32 prev, uint32 next) = findPosition(wants, gives, pivotId);

    uint256 maxPenalty = gasWanted * penaltyPerGas;

    require(freeWei[msg.sender] >= maxPenalty);
    freeWei[msg.sender] -= maxPenalty;

    uint32 orderId = uint32(++lastId);

    orders[orderId] = Order({
      prev: prev,
      next: next,
      wants: uint96(wants),
      gives: uint96(gives)
    });

    orderDetails[orderId] = OrderDetail({
      gasWanted: uint32(gasWanted),
      penaltyPerGas: uint64(penaltyPerGas),
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

  // ask for a volume by setting takerWants to however much you want and
  // takerGive to max_uint. Any price will be accepted.

  // ask for an average price by setting takerGives such that gives/wants is the price

  // there is no limit price setting

  // setting takerWants to max_int and takergives to however much you're ready to spend will
  // not work, you'll just be asking for a ~0 price.
  function marketOrderFrom(
    uint256 orderId,
    uint256 takerWants,
    uint256 takerGives
  ) internal {
    require(uint32(orderId) == orderId);
    require(uint96(takerWants) == takerWants);
    require(uint96(takerGives) == takerGives);

    uint256 localTakerWants;
    uint256 localTakerGives;
    Order memory order;

    uint256 minTakerWants = dustPerGasWanted * minGasWanted;
    while (takerWants >= minTakerWants && orderId != 0) {
      order = orders[orderId];

      require(isOrder(order));

      // is the taker ready to take less per unit than the maker is ready to give per unit?
      // takerWants/takerGives <= order.ofrAmount / order.reqAmount
      // here we normalize how much the maker would ask for takerWant
      uint256 makerWouldWant = (takerWants * order.wants) / order.gives;
      if (makerWouldWant <= takerGives) {
        localTakerWants = min(order.gives, takerWants); // the result of this determines the next line
        localTakerGives = min(order.wants, makerWouldWant);

        bool success = executeOrder(
          order,
          orderId,
          localTakerWants,
          localTakerGives
        );

        if (success) {
          takerWants -= localTakerWants;
          takerGives -= localTakerGives;
        }

        orderId = order.next;
      } else {
        break; // or revert depending on market order type (see price fill or kill order type of oasis)
      }
    }
  }

  // implements a market order with condition on the minimal delivered volume
  function conditionalMarketOrder(uint256 takerWants, uint256 takerGives)
    external
  {
    marketOrderFrom(best, takerWants, takerGives);
  }

  function deleteOrder(Order memory order, uint256 orderId) internal {
    delete orders[orderId];
    delete orderDetails[orderId];

    if (order.prev != 0) {
      orders[order.prev].next = order.next;
    } else {
      best = order.next;
    }

    if (order.next != 0) {
      orders[order.next].prev = order.prev;
    }
  }

  function externalExecuteOrder(
    //snipe order
    uint256 orderId,
    uint256 takerGives,
    uint256 takerWants
  ) external {
    require(open);
    require(modifyOB);
    require(uint32(orderId) == orderId);
    require(uint96(takerGives) == takerGives);
    require(uint96(takerWants) == takerWants);

    Order memory order = orders[orderId];
    require(isOrder(order));
    executeOrder(order, orderId, takerGives, takerWants);
  }

  function executeOrder(
    Order memory order,
    uint256 orderId,
    uint256 takerGives,
    uint256 takerWants
  ) internal returns (bool) {
    // Delete order (no partial fill yet)
    OrderDetail memory orderDetail = orderDetails[orderId];
    deleteOrder(order, orderId);

    // Execute order
    uint256 oldGas = gasleft();

    require(oldGas >= orderDetail.gasWanted + minFinishGas);

    uint256 maxPenalty = orderDetail.penaltyPerGas * orderDetail.gasWanted;

    try
      this._executeOrder(
        msg.sender,
        takerGives,
        takerWants,
        orderDetail.gasWanted,
        orderDetail.penaltyPerGas,
        orderDetail.maker
      )
     {
      freeWei[orderDetail.maker] += maxPenalty;
      return true;
    } catch {
      uint256 gasUsed = oldGas - gasleft();

      // penalty = (order.max_penalty/2) * (1 + gasUsed/order.gas)
      // nonpenalty = (1 - gasUsed/order.gas) * (order.max_penalty/2);
      // subtraction breaks if gasUsed does not fit into 32 bits. Should be impossible.
      // maxPenalty fits into 160, and 32+128 = 192 we're fine
      uint256 nonPenalty = ((orderDetail.gasWanted - gasUsed) * maxPenalty) /
        (2 * orderDetail.gasWanted);

      freeWei[orderDetail.maker] += nonPenalty;
      // TODO goutte de sueur: should we not say freeWei[msg.sender] += maxPenalty-nonPenalty ?
      dexTransfer(msg.sender, maxPenalty - nonPenalty);
      return false;
    }
  }

  function _executeOrder(
    address taker,
    uint256 takerGives,
    uint256 takerWants,
    uint32 orderGasWanted,
    uint64 orderPenaltyPerGas,
    address orderMaker
  ) external {
    require(msg.sender == THIS);
    modifyOB = false; // preventing reentrance
    transferToken(REQ_TOKEN, taker, orderMaker, takerGives);
    Maker(orderMaker).execute{gas: orderGasWanted}(
      takerWants,
      takerGives,
      orderPenaltyPerGas
    );
    transferToken(OFR_TOKEN, orderMaker, THIS, (takerWants * takerFee) / 10000);
    transferToken(
      OFR_TOKEN,
      orderMaker,
      taker,
      (takerWants * (10000 - takerFee)) / 10000
    );
    modifyOB = true; // end of critical zone
  }

  // Avoid "no return value" bug
  // https://soliditydeveloper.com/safe-erc20
  function transferToken(
    address token,
    address from,
    address to,
    uint256 value
  ) internal {
    bytes memory cd = abi.encodeWithSelector(
      ERC20(token).transferFrom.selector,
      from,
      to,
      value
    );
    (bool success, bytes memory data) = token.call(cd);
    require(
      success && (data.length == 0 || abi.decode(data, (bool))),
      "Failed to transfer token"
    );
  }
}
