// SPDX-License-Identifier: Unlicense

// MgvPack.sol

// This is free and unencumbered software released into the public domain.

// Anyone is free to copy, modify, publish, use, compile, sell, or distribute this software, either in source code form or as a compiled binary, for any purpose, commercial or non-commercial, and by any means.

// In jurisdictions that recognize copyright laws, the author or authors of this software dedicate any and all copyright interest in the software to the public domain. We make this dedication for the benefit of the public at large and to the detriment of our heirs and successors. We intend this dedication to be an overt act of relinquishment in perpetuity of all present and future rights to this software under copyright law.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

// For more information, please refer to <https://unlicense.org/>
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