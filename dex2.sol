pragma solidity ^0.7.0;

interface ERC20 {
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface Maker {
  // Maker should check msg.sender is Dex[REQ_TOKEN][OFR_TOKEN] or remember its orders
  function execute(uint takerWants, uint takerGives) external;
}
//TODO recheck insert on empty OB


contract Dex {

  struct Order {
    uint prev;      // better order
    uint next;      // worse order
    uint wants;     // amount requested
    uint gives;     // amount on order
    uint gasWanted; // gas requested
    uint maxPenalty;
    address maker;  // market maker
  }

  address admin;
  uint best;
  uint dustPerGasWanted; // min amount to offer per gas requested
  uint minGasWanted; // minimal amount of gas you can ask for; also used for market order's dust estimation
  uint minFinishGas; // min gas available
  // TODO Do not remove offer when partially filled
  uint penaltyPerGas;
  address immutable REQ_TOKEN; // req_token is the token orders wants
  address immutable OFR_TOKEN; // ofr_token is the token orders give

  bool open = true; // a closed market cannot make/take orders
  uint lastId = 0;
  mapping (uint => Order) orders;
  mapping (address => uint) freeWei;

  // TODO low gascost bookkeeping methods
  //updateOrder(constant price)
  //updateOrder(change price)

  constructor(
    address initialAdmin, 
    uint initialDustPerGasWanted, 
    uint initialMinFinishGas, 
    uint initialPenaltyPerGas, 
    uint initialMinGasWanted, 
    address reqToken, 
    address ofrToken
  ) {
    admin = initialAdmin;
    dustPerGasWanted = initialDustPerGasWanted;
    minFinishGas = initialMinFinishGas;
    penaltyPerGas = initialPenaltyPerGas;
    minGasWanted = initialMinGasWanted;
    REQ_TOKEN = reqToken;
    OFR_TOKEN = ofrToken;
  }

  function isAdmin(address maybeAdmin) internal view returns (bool) {
    return maybeAdmin == admin;
  }

  function updateOwner(address newValue) external {
    if (isAdmin(msg.sender)) { admin = newValue; }
  }

  function closeMarket() external {
    if (isAdmin(msg.sender)) { open = false; }
  }

  function updateDustPerGasWanted(uint newValue) external {
    require(newValue > 0);
    if (isAdmin(msg.sender)) { dustPerGasWanted = newValue; }
  }

  function updateMinFinishGas(uint newValue) external {
    if (isAdmin(msg.sender)) { minFinishGas = newValue; }
  }

  function updatePenaltyPerGas(uint newValue) external {
    if (isAdmin(msg.sender)) { penaltyPerGas = newValue; }
  }

  function isOrder(Order memory order) internal pure returns (bool) {
    return order.gives > 0;
  }

  receive() external payable {
    freeWei[msg.sender] += msg.value;
  }

  function withdraw(uint amount) external {
    require(freeWei[msg.sender] >= amount);
    freeWei[msg.sender] -= amount;
    msg.sender.transfer(amount);
  }

  function cancelOrder(uint orderId) external {
    Order memory order = orders[orderId];
    if (msg.sender == order.maker) {
      deleteOrder(order, orderId);
      freeWei[msg.sender] += order.maxPenalty;
    }
  }

  function newOrder(uint wants, uint gives, uint gasWanted, uint pivotId) external {
    require(open);
    require(gives >= gasWanted*dustPerGasWanted);

    uint orderId = lastId + 1;

    (uint prev, uint next) = findPosition(wants, gives, pivotId);

    uint maxPenalty = gasWanted * penaltyPerGas;

    require(freeWei[msg.sender] >= maxPenalty);
    freeWei[msg.sender] -= maxPenalty;

    orders[orderId] = Order({
      prev: prev,
      next: next,
      wants: wants,
      gives: gives,
      gasWanted: gasWanted,
      maxPenalty: maxPenalty,
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

    lastId = orderId;

  }

  // returns false iff (wants1,gives1) is strictly worse than (wants2,gives2)
  function better(uint wants1, uint gives1, uint wants2, uint gives2) internal pure returns (bool) {
    return wants1 * gives2 <= wants2 * gives1;
  }

  // 1. add a ghost order orderId with (want,gives) in the right position
  //    you should make sure that the order orderId has the correct price
  // 2. not trying to be a stable sort
  //    but giving privilege to earlier orders
  // 3. to use the least gas, consider which orders would surround yours (with older orders being sorted first)
  //    give any of those as _refId
  function findPosition(uint wants, uint gives, uint pivotId) internal view returns (uint,uint) {

    Order memory pivot = orders[pivotId];

    if (better(pivot.wants, pivot.gives, wants, gives)) { // o is better or as good, we follow next

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
      return (pivotId, pivot.next);

    } else { // o is strictly worse, we follow prev

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
      return (pivot.prev, pivotId);
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
  function marketOrder(uint orderId, uint takerWants, uint takerGives) external {
    require(open);

    uint localTakerWants;
    uint localTakerGives;
    Order memory order;

    while (takerWants >= dustPerGasWanted * minGasWanted && orderId != 0) {
      order = orders[orderId];

      require(isOrder(order));

      // is the taker ready to take less per unit than the maker is ready to give per unit?
      // takerWants/takerGives <= order.ofrAmount / order.reqAmount
      // here we normalize how much the maker would ask for takerWant
      uint makerWouldWant = takerWants * order.wants / order.gives;
      if (makerWouldWant <= takerGives) {

        localTakerWants = min(order.gives, takerWants);
        localTakerGives = min(makerWouldWant, takerGives);

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

      }
    }
  }

  function deleteOrder(Order memory order, uint orderId) internal {

    delete orders[orderId];

    if (order.prev != 0) {
      orders[order.prev].next = order.next;
    } else {
      best = order.next;
    }

    if (order.next != 0) {
      orders[order.next].prev = order.prev;
    }
  }


  function externalExecuteOrder(uint orderId, uint takerGives, uint takerWants) external {
    Order memory order = orders[orderId];
    require(isOrder(order));
    executeOrder(order, orderId, takerGives, takerWants);
  }

  function executeOrder(Order memory order, uint orderId, uint takerGives, uint takerWants) internal returns (bool) {
    require(open);

    // Delete order (no partial fill yet)
    deleteOrder(order, orderId);

    // Execute order
    uint oldGas = gasleft();

    require(oldGas >= order.gasWanted + minFinishGas);

    try this._executeOrder(order.maker,msg.sender,order.gasWanted,takerGives,takerWants) {
      freeWei[order.maker] += order.maxPenalty;
      return true;
    } catch {

      uint gasUsed = oldGas - gasleft();

      // penalty = (order.max_penalty/2) * (1 + gasUsed/order.gas)
      // nonpenalty = (1 - gasUsed/order.gas) * (order.max_penalty/2);
      // TODO check gasWanted > 0
      uint nonPenalty = ((order.gasWanted - gasUsed) * order.maxPenalty) / (2 * order.gasWanted);

      freeWei[order.maker] += nonPenalty;
      // TODO goutte de sueur: should we not say freeWei[msg.sender] += order.maxPenalty-nonPenalty ?
      msg.sender.transfer(order.maxPenalty-nonPenalty);

      return false;
    }

  }


  function _executeOrder(address maker, address taker, uint gasWanted, uint takerGives, uint takerWants) public {
    transferToken(REQ_TOKEN,taker,maker,takerGives);
    Maker(maker).execute{gas:gasWanted}(takerWants,takerGives);
    transferToken(OFR_TOKEN,maker,taker,takerWants);
  }

  // Avoid "no return value" bug
  // https://soliditydeveloper.com/safe-erc20
  function transferToken(address token, address from, address to, uint value) internal {
    bytes memory cd = abi.encodeWithSelector(ERC20(token).transferFrom.selector, from, to, value);
    (bool success, bytes memory data) = token.call(cd);
    require(success && (data.length == 0 || abi.decode(data, (bool))), 'Failed to transfer token');
  }

}
