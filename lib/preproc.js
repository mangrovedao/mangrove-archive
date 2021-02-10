/* Dex methods */
// number of bits before a field
const before_of = (struct, _name) => {
  const stop = struct.findIndex(({ name }) => name == _name);
  if (stop < 0) {
    throw "preproc/before/not_found";
  }
  return struct.reduce((acc_bits, { bits }, index) => {
    return acc_bits + (index < stop ? bits : 0);
  }, 0);
};

// number of bits in a field
const bits_of = (struct, _name) =>
  struct.find(({ name }) => name == _name).bits;

// destination type of a field
const type_of = (struct, _name) =>
  struct.find(({ name }) => name == _name).type;

// cleanup-mask: 1's everywhere at field location, 0's elsewhere
const mask_of = (struct, _name) => {
  const bfr = before_of(struct, _name);
  const bts = bits_of(struct, _name);
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
const after_of = (struct, _name) => {
  return 256 - before_of(struct, _name) - bits_of(struct, _name);
};

// prints accessor for a field
const get = (ptr, struct, _name) => {
  const cast = type_of(struct, _name);
  const left = before_of(struct, _name);
  const right = before_of(struct, _name) + after_of(struct, _name);
  return `${cast}(uint((${ptr} << ${left})) >> ${right})`;
};

// prints setter for a single field
const set1 = (ptr, struct, _name, val) => {
  const mask = mask_of(struct, _name);
  const left = before_of(struct, _name) + after_of(struct, _name);
  const right = before_of(struct, _name);
  return `${ptr} & bytes32(${mask}) | bytes32((uint(${val}) << ${left}) >> ${right})`;
};

// prints setter for multiple fields
// set(set1,...) better than set1(set,...) because it keeps stack use constant
const set = (ptr, struct, values) => {
  const red = (acc, [_name, value]) => set1(acc, struct, _name, value);
  return values.reduce(red, ptr);
};

// !unsafe version! prints setter for a single field, without bitmask cleanup
const set1_unsafe = (ptr, struct, _name, val) => {
  const left = before_of(struct, _name) + after_of(struct, _name);
  const right = before_of(struct, _name);
  return `${ptr} | bytes32((uint(${val}) << ${left}) >> ${right})`;
};

const make = (struct, values) => {
  const red = (acc, [_name, value]) => set1_unsafe(acc, struct, _name, value);
  return values.reduce(red, "bytes32(0)");
};

const struct_obj_to_ary = (v) =>
  v.map(({ name, bits, type }) => {
    return [name, bits, type];
  });

const struct_ary_to_obj = (v) =>
  v.map(([name, bits, type]) => {
    return { name, bits, type };
  });

exports.structs_with_macros = (structs) => {
  const arrayed = Object.entries(structs).map(([k, v]) => [
    k,
    struct_obj_to_ary(v),
  ]);
  const ret = {
    structs: arrayed,
    make: (struct, values) => make(struct_ary_to_obj(struct), values),
    get: (ptr, struct, _name) => get(ptr, struct_ary_to_obj(struct), _name),
  };
  for (const [sname, struct] of Object.entries(structs)) {
    ret[`set_${sname}`] = (ptr, values) => set(ptr, struct, values);
    ret[`make_${sname}`] = (values) => make(struct, values);
    for (const { name } of struct) {
      ret[`${sname}_${name}`] = (ptr) => get(ptr, struct, name);
    }
  }
  return ret;
};
