// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

library MgvPack {

  // fields are of the form [name,bits,type]

  // $for ns in structs

  // $def sname ns[0]
  // $def scontents ns[1]
  /* $def arguments
    join(map(scontents,(field) => `$${field[2]} __$${field[0]}`),', ')
  */

  /* $def params
     map(scontents, (field) => [field[0],`__$${field[0]}`])
  */

  function $$(sname)_pack($$(arguments)) internal pure returns (bytes32) {
    return $$(make(
      scontents,
      map(scontents, (field) =>
    [field[0],`__$${field[0]}`])));
  }

  function $$(sname)_unpack(bytes32 __packed) internal pure returns ($$(arguments)) {
    // $for field in scontents
    __$$(field[0]) = $$(get('__packed',scontents,field[0]));
    // $done
  }

  // $for field in scontents
  function $$(sname)_unpack_$$(field[0])(bytes32 __packed) internal pure returns($$(field[2])) {
    return $$(get('__packed',scontents,field[0]));
  }
  // $done

  // $done
}
