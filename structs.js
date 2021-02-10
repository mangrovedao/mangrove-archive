const preproc = require("./lib/preproc.js");

const fields = {
  gives: { name: "gives", bits: 96, type: "uint" },
  wants: { name: "wants", bits: 96, type: "uint" },
  gasprice: { name: "gasprice", bits: 16, type: "uint" },
  gasreq: { name: "gasreq", bits: 24, type: "uint" },
  gasbase: { name: "gasbase", bits: 24, type: "uint" },
};

const id_field = (name) => {
  return { name, bits: 24, type: "uint" };
};

const structs = {
  offer: [
    id_field("prev"),
    id_field("next"),
    fields.gives,
    fields.wants,
    fields.gasprice,
  ],

  offerDetail: [
    { name: "maker", bits: 160, type: "address" },
    fields.gasreq,
    fields.gasbase,
  ],

  global: [
    { name: "monitor", bits: 160, type: "address" },
    fields.gasprice,
    { name: "gasmax", bits: 24, type: "uint" },
    { name: "dead", bits: 8, type: "uint" },
    { name: "useOracle", bits: 8, type: "uint" },
    { name: "notify", bits: 8, type: "uint" },
  ],

  local: [
    { name: "active", bits: 8, type: "uint" },
    { name: "fee", bits: 16, type: "uint" },
    { name: "density", bits: 32, type: "uint" },
    fields.gasbase,
    { name: "best", bits: 24, type: "uint" },
    { name: "lock", bits: 8, type: "uint" },
    { name: "lastId", bits: 24, type: "uint" },
  ],

  writeOffer: [
    fields.wants,
    fields.gives,
    fields.gasprice,
    fields.gasreq,
    id_field("id"),
  ],
};

module.exports = preproc.structs_with_macros(structs);
