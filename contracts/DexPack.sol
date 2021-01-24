// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

library DexPack {

  // $for ns in [['writeOffer',writeOffer],['offer',offer],['offerDetail',offerDetail],['global',global],['local',local]]
  // prettier-ignore
  function $$(ns[0])_pack($$(join(map(ns[1],(fb) => `$${fb[2]} __$${fb[0]}`),', '))) internal pure returns (bytes32) {
    return $$(set_unsafe('bytes32(0)',ns[1],map(ns[1], (fb) => [fb[0],`__$${fb[0]}`])));
  }

  // prettier-ignore
  function $$(ns[0])_unpack(bytes32 __packed) internal pure returns ($$(join(map(ns[1],(fb) => `$${fb[2]} __$${fb[0]}`),', '))) {
    // $for fb in ns[1]
    __$$(fb[0]) = $$(get('__packed',ns[1],fb[0]));
    // $done
  }

  // $for fb in ns[1]
  function $$(ns[0])_unpack_$$(fb[0])(bytes32 __packed) internal pure returns($$(fb[2])) {
    return $$(get('__packed',ns[1],fb[0]));
  }
  // $done

  // $done
}
