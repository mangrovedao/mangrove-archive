const ethers = require("ethers");

exports.sleep = (ms) => {
  return new Promise((cb) => setTimeout(cb, ms));
};

/* Returns a promise with resolve/reject accessible from the outside. */
exports.asyncQueue = () => {
  const promises = [],
    elements = [];
  return {
    put: (elem) => {
      if (promises.length > 0) {
        promises.shift()(elem);
      } else {
        elements.push(elem);
      }
    },
    get: () => {
      if (elements.length > 0) {
        return Promise.resolve(elements.shift());
      } else {
        return new Promise((ok) => promises.push(ok));
      }
    },
  };
};

exports.toWei = (v, u = "ether") => ethers.utils.parseUnits(v.toString(), u);
