// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

library MgvPack {

  // fields are of the form [name,bits,type]

  // $for ns in struct_defs

  // $def sname ns[0]
  // $def scontents ns[1]
  /* $def arguments
    join(map(scontents,(field) => `$${f_type(field)} __$${f_name(field)}`),', ')
  */

  /* $def params
     map(scontents, (field) => [f_name(field),`__$${f_name(field)}`])
  */

  function $$(sname)_pack($$(arguments)) internal pure returns (bytes32) {
    return $$(make(
      scontents,
      map(scontents, (field) =>
    [f_name(field),`__$${f_name(field)}`])));
  }

  function $$(sname)_unpack(bytes32 __packed) internal pure returns ($$(arguments)) {
    // $for field in scontents
    __$$(f_name(field)) = $$(get('__packed',scontents,f_name(field)));
    // $done
  }

  // $for field in scontents
  function $$(sname)_unpack_$$(f_name(field))(bytes32 __packed) internal pure returns($$(f_type(field))) {
    return $$(get('__packed',scontents,f_name(field)));
  }
  // $done

  // $done
}
