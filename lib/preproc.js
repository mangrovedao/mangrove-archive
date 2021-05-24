/* Dex methods */

// getters for array. In preprocessor code, .accessors don't work so we route through getter functions.
const name_of = (field) => field.name;
const type_of = (field) => field.type;

// access index, raise if not found
const field_index = (struct,_name) => {

  const stop = struct.findIndex(({name}) => name == _name);
  if (stop < 0) {
    throw new Error("preproc/before/not_found");
  }
  return stop;
}

// get info related to a field in a struct
const field = (struct,_name) => struct[field_index(struct,_name)];

// extract type info
// - read_type is the type to cast to for use in code
// - bits is the number of bits occupied when packed
// - currently supported: uintXX, address
const type_info = (type) => {
  let match = type.match(/^uint(\d+)$/);
  if (match) {
    return { read_type: "uint", bits: parseInt(match[1]) };
  }

  match = type.match(/^address$/);
  if (match) {
    return { read_type: "address", bits: 160 };
  }

  throw new Error(`Unknown type: ${type}.`);
};


// number of bits in a field
const bits_of = (field) => type_info(type_of(field)).bits;

// destination type of a field
const read_type = (field) => type_info(type_of(field)).read_type;

/* struct fields are of the form [name:string,type:string] */
// number of bits before a field
const before = (struct, _name) => {
  const stop = field_index(struct,_name);
  return struct.reduce((acc_bits, field, index) => {
    return acc_bits + (index < stop ? bits_of(field) : 0);
  }, 0);
};

// capitalize for struct name
const sol_name = (sname) => sname.replace(/^\w/, (c) => c.toUpperCase());

// cleanup-mask: 1's everywhere at field location, 0's elsewhere
const mask = (struct, _name) => {
  const bfr = before(struct, _name);
  const bts = bits_of(field(struct, _name));
  if (bfr % 4 != 0 || bts % 4 != 0) {
    throw "preproc/mask/misaligned";
  }
  return (
    "0x" +
    "f".repeat(bfr / 4) +
    "0".repeat(bts / 4) +
    "f".repeat((256 - bfr - bts) / 4)
  );
};

// number of bits after a field
const after = (struct, _name) => {
  return 256 - before(struct, _name) - bits_of(field(struct, _name));
};

// prints accessor for a field
const get_pack = (ptr, struct, field) => {
  const cast = read_type(field);
  const left = before(struct, name_of(field));
  const right = before(struct, name_of(field)) + after(struct, name_of(field));
  return `${cast}(uint((${ptr} << ${left})) >> ${right})`;
};


const get_struct = (ptr, struct, field) => {
  const cast = read_type(field);
  return `${cast}(${ptr}.${name_of(field)})`;
};

// prints setter for a single field
const set1 = (ptr, struct, _name, val) => {
  const msk = mask(struct, _name);
  const left = before(struct, _name) + after(struct, _name);
  const right = before(struct, _name);
  return `(${ptr} & bytes32(${msk}) | bytes32((uint(${val}) << ${left}) >> ${right}))`;
};

// prints setter for multiple fields
// set(set1,...) better than set1(set,...) because it keeps stack use constant
const set = (ptr, struct, values) => {
  const red = (acc, [_name, value]) => set1(acc, struct, _name, value);
  return values.reduce(red, ptr);
};

// updates a variable with the same name for multiple fields
// set(set1,...) better than set1(set,...) because it keeps stack use constant
const upd_pack = (ptr, struct, values) => {
  return `${ptr} = ${set(ptr,struct,values)}`;
};

const upd_struct = (ptr,struct,values) => {
    const assign = ([name,value]) => `${ptr}.${name} = ${type_of(field(struct,name))}(${value})`
    return values.map(assign).join('; ');
}
//
// update a var, taking values from another var
const upd_from_pack = (ptr_to, ptr_from, struct, values) => {
  return `${ptr_to} = ${set(ptr_from,struct,values)}`;
};

// noop for compatibility with _pack version
const upd_from_struct = (ptr_to,ptr_from,struct,values) => upd_struct(ptr_to,struct,values);

// !unsafe version! prints setter for a single field, without bitmask cleanup
const set1_unsafe = (ptr, struct, _name, val) => {
  const left = before(struct, _name) + after(struct, _name);
  const right = before(struct, _name);
  return `(${ptr} | bytes32((uint(${val}) << ${left}) >> ${right}))`;
};

// unsafe version is ok here since we start from all zeroes
const make_pack = (lib_name) => {
  return (sname, struct, values) => {
    const red = (acc, [_name, value]) => set1_unsafe(acc, struct, _name, value);
    return values.reduce(red, "bytes32(0)");
  };
};

const make_struct = (lib_name) => {
  return (sname, struct,values) => {
    const inner = values.map(([name,value]) => {
      return `${name}: ${type_of(field(struct,name))}(${value})`;
    });
    return `${lib_name}.${sol_name(sname)}({${inner.join(' ,')}})`;
  }
};;

// extract field from js hex string
const js_get = (str, struct, _name) => {
  const cast = read_type(field(struct, _name));
  const left = before(struct, _name) / 4;
  const size = bits_of(field(struct,_name)) / 4;
  const extract = str.slice(2 + left, 2 + left + size);
  if (cast === "address") {
    return ("0x" + extract);
  } else if (cast === "uint") {
    return ("0x" + "0".repeat(64 - size) + extract);
  } else {
    throw new Error(`preproc: unknown read type: ${cast}`);
  }
};

// TODO: validate struct: total size is <256 bits, each bitsize is divisible by 4 (so bitmasks work at the nibble granularity level).

exports.structs_with_macros = (structs,{lib_name,packing}) => {
  const ret = {
    name_of,
    type_of,
    read_type,
    lib_name: lib_name || "Preproc",
    structs: Object.entries(structs),
    js: {}
  };

  const inner = field => `${type_of(field)} ${name_of(field)};\n`;
  const to_sol = ([sname,fields]) => `struct ${sol_name(sname)} {\n${fields.map(inner).join('')}\n}`;

  ret.sol_struct_defs = `library ${lib_name} {\n${ret.structs.map(to_sol).join('\n\n')}\n}`;

  if (packing) {
    ret.sol_type = sname => 'bytes32';
    ret.sol_type_decl = sname => 'bytes32';
    ret.make = make_pack(lib_name);
    ret.get = get_pack;
    ret.upd = upd_pack;
    ret.upd_from = upd_from_pack;
  } else {
    ret.sol_type = sname => `${lib_name}.${sol_name(sname)} memory`;
    ret.sol_type_decl = sname => `${lib_name}.${sol_name(sname)}`;
    ret.make = make_struct(lib_name);
    ret.get = get_struct;
    ret.upd = upd_struct;
    ret.upd_from = upd_from_struct;
  }

  for (const [sname, struct] of Object.entries(structs)) {
    // Next 2 are values so should be inserted with $(...) not $$(...)
    ret[`sol_type_${sname}`] = ret.sol_type(sname);
    ret[`sol_type_decl_${sname}`] = ret.sol_type_decl(sname);

    ret[`make_${sname}`] = (values) => ret.make(sname, struct, values);
    ret[`upd_${sname}`] = (ptr,values) => ret.upd(ptr,struct,values);
    ret[`upd_from_${sname}`] = (ptr_to,ptr_from,values) => ret.upd_from(ptr_to,ptr_from,struct,values);

    for (const field of struct) {
      ret[`${sname}_${name_of(field)}`] = (ptr) => ret.get(ptr,struct,field)
    }

  }
  return ret;
};
