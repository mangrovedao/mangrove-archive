pragma solidity ^0.7.0;

// SPDX-License-Identifier: UNLICENSED


library MgvPack {

  // fields are of the form [name,bits,type]

  function offer_pack(uint __prev, uint __next, uint __gives, uint __wants, uint __gasprice) internal pure returns (bytes32) {
    return (((((bytes32(0) | bytes32((uint(__prev) << 232) >> 0)) | bytes32((uint(__next) << 232) >> 24)) | bytes32((uint(__gives) << 160) >> 48)) | bytes32((uint(__wants) << 160) >> 144)) | bytes32((uint(__gasprice) << 240) >> 240));
  }

  function offer_unpack(bytes32 __packed) internal pure returns (uint __prev, uint __next, uint __gives, uint __wants, uint __gasprice) {
    __prev = uint(uint((__packed << 0)) >> 232);
    __next = uint(uint((__packed << 24)) >> 232);
    __gives = uint(uint((__packed << 48)) >> 160);
    __wants = uint(uint((__packed << 144)) >> 160);
    __gasprice = uint(uint((__packed << 240)) >> 240);
  }

  function offer_unpack_prev(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 0)) >> 232);
  }
  function offer_unpack_next(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 24)) >> 232);
  }
  function offer_unpack_gives(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 48)) >> 160);
  }
  function offer_unpack_wants(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 144)) >> 160);
  }
  function offer_unpack_gasprice(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 240)) >> 240);
  }

  function offerDetail_pack(address __maker, uint __gasreq, uint __overhead_gasbase, uint __offer_gasbase) internal pure returns (bytes32) {
    return ((((bytes32(0) | bytes32((uint(__maker) << 96) >> 0)) | bytes32((uint(__gasreq) << 232) >> 160)) | bytes32((uint(__overhead_gasbase) << 232) >> 184)) | bytes32((uint(__offer_gasbase) << 232) >> 208));
  }

  function offerDetail_unpack(bytes32 __packed) internal pure returns (address __maker, uint __gasreq, uint __overhead_gasbase, uint __offer_gasbase) {
    __maker = address(uint((__packed << 0)) >> 96);
    __gasreq = uint(uint((__packed << 160)) >> 232);
    __overhead_gasbase = uint(uint((__packed << 184)) >> 232);
    __offer_gasbase = uint(uint((__packed << 208)) >> 232);
  }

  function offerDetail_unpack_maker(bytes32 __packed) internal pure returns(address) {
    return address(uint((__packed << 0)) >> 96);
  }
  function offerDetail_unpack_gasreq(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 160)) >> 232);
  }
  function offerDetail_unpack_overhead_gasbase(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 184)) >> 232);
  }
  function offerDetail_unpack_offer_gasbase(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 208)) >> 232);
  }

  function global_pack(address __monitor, uint __useOracle, uint __notify, uint __gasprice, uint __gasmax, uint __dead) internal pure returns (bytes32) {
    return ((((((bytes32(0) | bytes32((uint(__monitor) << 96) >> 0)) | bytes32((uint(__useOracle) << 248) >> 160)) | bytes32((uint(__notify) << 248) >> 168)) | bytes32((uint(__gasprice) << 240) >> 176)) | bytes32((uint(__gasmax) << 232) >> 192)) | bytes32((uint(__dead) << 248) >> 216));
  }

  function global_unpack(bytes32 __packed) internal pure returns (address __monitor, uint __useOracle, uint __notify, uint __gasprice, uint __gasmax, uint __dead) {
    __monitor = address(uint((__packed << 0)) >> 96);
    __useOracle = uint(uint((__packed << 160)) >> 248);
    __notify = uint(uint((__packed << 168)) >> 248);
    __gasprice = uint(uint((__packed << 176)) >> 240);
    __gasmax = uint(uint((__packed << 192)) >> 232);
    __dead = uint(uint((__packed << 216)) >> 248);
  }

  function global_unpack_monitor(bytes32 __packed) internal pure returns(address) {
    return address(uint((__packed << 0)) >> 96);
  }
  function global_unpack_useOracle(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 160)) >> 248);
  }
  function global_unpack_notify(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 168)) >> 248);
  }
  function global_unpack_gasprice(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 176)) >> 240);
  }
  function global_unpack_gasmax(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 192)) >> 232);
  }
  function global_unpack_dead(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 216)) >> 248);
  }
  
  function local_pack(uint __active, uint __fee, uint __density, uint __overhead_gasbase, uint __offer_gasbase, uint __lock, uint __best, uint __last) internal pure returns (bytes32) {
    return ((((((((bytes32(0) | bytes32((uint(__active) << 248) >> 0)) | bytes32((uint(__fee) << 240) >> 8)) | bytes32((uint(__density) << 224) >> 24)) | bytes32((uint(__overhead_gasbase) << 232) >> 56)) | bytes32((uint(__offer_gasbase) << 232) >> 80)) | bytes32((uint(__lock) << 248) >> 104)) | bytes32((uint(__best) << 232) >> 112)) | bytes32((uint(__last) << 232) >> 136));
  }

  function local_unpack(bytes32 __packed) internal pure returns (uint __active, uint __fee, uint __density, uint __overhead_gasbase, uint __offer_gasbase, uint __lock, uint __best, uint __last) {
    __active = uint(uint((__packed << 0)) >> 248);
    __fee = uint(uint((__packed << 8)) >> 240);
    __density = uint(uint((__packed << 24)) >> 224);
    __overhead_gasbase = uint(uint((__packed << 56)) >> 232);
    __offer_gasbase = uint(uint((__packed << 80)) >> 232);
    __lock = uint(uint((__packed << 104)) >> 248);
    __best = uint(uint((__packed << 112)) >> 232);
    __last = uint(uint((__packed << 136)) >> 232);
  }

  function local_unpack_active(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 0)) >> 248);
  }
  function local_unpack_fee(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 8)) >> 240);
  }
  function local_unpack_density(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 24)) >> 224);
  }
  function local_unpack_overhead_gasbase(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 56)) >> 232);
  }
  function local_unpack_offer_gasbase(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 80)) >> 232);
  }
  function local_unpack_lock(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 104)) >> 248);
  }
  function local_unpack_best(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 112)) >> 232);
  }
  function local_unpack_last(bytes32 __packed) internal pure returns(uint) {
    return uint(uint((__packed << 136)) >> 232);
  }

}
