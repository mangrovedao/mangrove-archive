// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

interface ERC20 {
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface Maker {
  // Maker should check msg.sender is Dex[REQ_TOKEN][OFR_TOKEN] or remember its orders
  function execute(uint takerWants, uint takerGives) payable external ;
}
//TODO recheck insert on empty OB


contract Dex {

  struct Order {
    uint32 prev;      // better order
    uint32 next;      // worse order
    uint32 gasWanted; // gas requested
    uint128 penaltyPerGas; // in wei
    uint128 wants;     // amount requested
    uint128 gives;     // amount on order
    address maker;  // market maker
  }

  address admin;
  uint best; // (32)
  uint minFinishGas; // (32) min gas available
  uint dustPerGasWanted; // (128) min amount to offer per gas requested
  uint minGasWanted; // (32) minimal amount of gas you can ask for; also used for market order's dust estimation
  // TODO Do not remove offer when partially filled
  uint penaltyPerGas; // (128)
  address immutable REQ_TOKEN; // req_token is the token orders wants
  address immutable OFR_TOKEN; // ofr_token is the token orders give

  bool open = true; // a closed market cannot make/take orders
  bool modifyOB = true ; // whether a modification of the OB is permitted
  uint lastId = 0; // (32)
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
    setDustPerGasWanted(initialDustPerGasWanted);
    setMinFinishGas(initialMinFinishGas);
    setPenaltyPerGas(initialPenaltyPerGas);
    setMinGasWanted(initialMinGasWanted);
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

  function setDustPerGasWanted(uint newValue) internal {
    require(newValue > 0);
    require(uint64(newValue) == newValue);
    dustPerGasWanted = newValue;
  }

  function setMinFinishGas(uint newValue) internal {
    require(uint32(newValue) == newValue);
    minFinishGas = newValue;
  }

  function setPenaltyPerGas(uint newValue) internal {
    require(uint128(newValue) == newValue);
    penaltyPerGas = newValue;
  }

  function setMinGasWanted(uint newValue) internal {
    require(uint32(newValue) == newValue);
    minGasWanted = newValue;
  }

  function updateDustPerGasWanted(uint newValue) external {
    if (isAdmin(msg.sender)) { setDustPerGasWanted(newValue); }
  }

  function updateMinFinishGas(uint newValue) external {
    if (isAdmin(msg.sender)) { setMinFinishGas(newValue); }
  }

  function updatePenaltyPerGas(uint newValue) external {
    if (isAdmin(msg.sender)) { setPenaltyPerGas(newValue); }
  }

  function updateMinGasWanted(uint newValue) external {
    if (isAdmin(msg.sender)) { setMinGasWanted(newValue); }
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
      require(modifyOB);
      Order memory order = orders[orderId];
      if (msg.sender == order.maker) {
	  deleteOrder(order, orderId);
	  freeWei[msg.sender] += order.penaltyPerGas * order.gasWanted;
      }
  }

  function newOrder(uint wants, uint gives, uint gasWanted, uint pivotId) external {
    require(open);
    require(modifyOB);
    require(uint128(wants) == wants);
    require(uint128(gives) == gives);
    require(uint128(gasWanted) == gasWanted);
    require(uint32(pivotId) == pivotId);
    require(gives >= gasWanted * dustPerGasWanted);

    (uint32 prev, uint32 next) = findPosition(wants, gives, pivotId);

    uint maxPenalty = gasWanted * penaltyPerGas;

    require(freeWei[msg.sender] >= maxPenalty);
    freeWei[msg.sender] -= maxPenalty;

    uint32 orderId = uint32(++lastId);

    orders[orderId] = Order({
      prev: prev,
      next: next,
      wants: uint128(wants),
      gives: uint128(gives),
      gasWanted: uint32(gasWanted),
      penaltyPerGas: uint128(penaltyPerGas),
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
  //    no analysis was done if garbage ids are allowed
  function findPosition(uint wants, uint gives, uint pivotId) internal view returns (uint32 ,uint32) {

    Order memory pivot = orders[pivotId];
    if (!isOrder(pivot)) { // in case pivotId is not or no longer a valid order
	    pivot = orders[best] ;
	    pivotId = best ;
	}

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
      return (uint32(pivotId), pivot.next); // this is also where we end up with an empty OB

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
  function marketOrderFrom(uint orderId, uint takerWants, uint takerGives) external {
    require(open);
    require(modifyOB);
    require(uint32(orderId) == orderId);
    require(uint128(takerWants) == takerWants);
    require(uint128(takerGives) == takerGives);

    uint localTakerWants;
    uint localTakerGives;
    Order memory order;

    uint minTakerWants = dustPerGasWanted * minGasWanted ;
    while (takerWants >= minTakerWants && orderId != 0) {
      order = orders[orderId];

      require(isOrder(order));

      // is the taker ready to take less per unit than the maker is ready to give per unit?
      // takerWants/takerGives <= order.ofrAmount / order.reqAmount
      // here we normalize how much the maker would ask for takerWant
      uint makerWouldWant = takerWants * order.wants / order.gives;
      if (makerWouldWant <= takerGives) {

        localTakerWants = min(order.gives, takerWants);
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

      }
      else {
	  break; // or revert depending on market order type (see price fill or kill order type of oasis)
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
    require(open);
    require(modifyOB);
    require(uint32(orderId) == orderId);
    require(uint128(takerGives) == takerGives);
    require(uint128(takerWants) == takerWants);

    Order memory order = orders[orderId];
    require(isOrder(order));
    executeOrder(order, orderId, takerGives, takerWants);
  }

  function executeOrder(Order memory order, uint orderId, uint takerGives, uint takerWants) internal returns (bool) {

    // Delete order (no partial fill yet)
    deleteOrder(order, orderId);

    // Execute order
    uint oldGas = gasleft();

    require(oldGas >= order.gasWanted + minFinishGas);

    uint maxPenalty = order.penaltyPerGas * order.gasWanted;

    try this._executeOrder(order.maker,msg.sender,order.gasWanted,takerGives,takerWants,maxPenalty) {
      freeWei[order.maker] += maxPenalty;
      return true;
    } catch {

      uint gasUsed = oldGas - gasleft(); 

      // penalty = (order.max_penalty/2) * (1 + gasUsed/order.gas)
      // nonpenalty = (1 - gasUsed/order.gas) * (order.max_penalty/2);
      // TODO check gasWanted > 0
      // subtraction breaks if gasUsed does not fit into 32 bits. Should be impossible.
      // maxPenalty fits into 160, and 32+128 = 192 we're fine
      uint nonPenalty = ((order.gasWanted - gasUsed) * maxPenalty) / (2 * order.gasWanted);

      freeWei[order.maker] += nonPenalty;
      // TODO goutte de sueur: should we not say freeWei[msg.sender] += maxPenalty-nonPenalty ?
      msg.sender.transfer(maxPenalty-nonPenalty);

      return false;
    }

  }


  function _executeOrder(address maker, address taker, uint gasWanted, uint takerGives, uint takerWants, uint maxPenalty) public {
      transferToken(REQ_TOKEN,taker,maker,takerGives); // Flash loan REQ_TOKEN
      Maker(maker).execute{value: maxPenalty, gas:gasWanted}(takerWants,takerGives); // Flash loan penalty --check if gas costly
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
