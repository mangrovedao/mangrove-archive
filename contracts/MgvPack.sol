// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import {
  MgvInternal
} from "./MgvCommon.sol";

library MgvPack {

  // fields should be accessed with `name_of`, `type_of`, `read_type`, `bits_of` (see `preproc.js`).

  // $for ns in structs

  // $def sname ns[0]
  // $def scontents ns[1]
  /* $def arguments
    join(map(scontents,(field) => `$${read_type(field)} __$${name_of(field)}`),', ')
  */

  /* $def params
     map(scontents, (field) => [name_of(field),`__$${name_of(field)}`])
  */

  function $$(sname)_pack($$(arguments)) internal pure returns ($$(sol_type(sname))) {
    return $$(make(
      sname,
      scontents,
      map(scontents, (field) =>
    [name_of(field),`__$${name_of(field)}`])));
  }

  function $$(sname)_unpack($$(sol_type(sname)) __packed) internal pure returns ($$(arguments)) {
    // $for field in scontents
    __$$(name_of(field)) = $$(get('__packed',scontents,field));
    // $done
  }

  // $for field in scontents
  function $$(sname)_unpack_$$(name_of(field))($$(sol_type(sname)) __packed) internal pure returns($$(read_type(field))) {
    return $$(get('__packed',scontents,field));
  }
  // $done

  // $done
}
