const decimals = new Map();

function assertEqualBN(value1, value2, msg) {
  errorMsg =
    msg +
    ("(Received: " +
      value1.toString() +
      ", Expected: " +
      value2.toString() +
      ")");
  assert(value1.eq(value2), errorMsg);
}

async function nextOfferId(base, quote, ctr) {
  offerId = await ctr.callStatic.newOffer(
    base,
    quote,
    parseToken("1.0"),
    0,
    0,
    0,
    0
  );
  return offerId;
}

async function synch(promises) {
  for (let i = 0; i < promises.length; i++) {
    await promises[i].wait();
  }
}

function netOf(bn, fee) {
  return bn.sub(bn.mul(fee).div(10000));
}

function assertAlmost(bignum_expected, bignum_obs, decimal, msg) {
    error = bignum_expected.div(ethers.utils.parseUnits("1.0", decimal));
    if (bignum_expected.lte(bignum_obs)) {
      assert(
        bignum_obs.sub(bignum_expected).lte(error),
        msg +
          ":\n " +
          "\x1b[32mExpected: " +
          formatToken(bignum_expected, 18) +
          "\n\x1b[31mGiven: " +
          formatToken(bignum_obs, 18) +
          "\x1b[0m\n"
      );
    } else {
      assert(
        bignum_expected.sub(bignum_obs).lte(error),
        msg +
          ":\n" +
          "\x1b[32mExpected: " +
          formatToken(bignum_expected, 18) +
          "\n\x1b[31mGiven: " +
          formatToken(bignum_obs, 18) +
          "\x1b[0m\n"
      );
    }
  }
  
  async function logCompoundStatus(contract, symbols) {
    function logPosition(s, x, y, z) {
      console.log(
        s,
        ":",
        " (\x1b[32m",
        x,
        "\x1b[0m|\x1b[31m",
        y,
        "\x1b[0m) + \x1b[34m",
        z,
        "\x1b[0m"
      );
    }
    [, liquidity] = await comp.getAccountLiquidity(contract.address);
    console.log();
    console.log(
      "**** Account borrow power (USD): \x1b[35m",
      formatToken(liquidity, 18),
      "\x1b[0m ****"
    );
    for (const symbol of symbols) {
      switch (symbol) {
        case "DAI":
          [, redeemableDai] = await contract.maxGettableUnderlying(cDai.address);
          [, , borrowBalance] = await cDai.getAccountSnapshot(contract.address);
          daiBalance = await dai.balanceOf(contract.address);
          logPosition(
            "DAI",
            formatToken(redeemableDai, "DAI"),
            formatToken(borrowBalance, "DAI"),
            formatToken(daiBalance, "DAI")
          );
          break;
        case "WETH":
          [, redeemableWeth] = await contract.maxGettableUnderlying(cEth.address);
          [, , borrowBalance] = await cEth.getAccountSnapshot(contract.address);
          wethBalance = await wEth.balanceOf(contract.address);
          logPosition(
            "WETH",
            formatToken(redeemableWeth, "DAI"),
            formatToken(borrowBalance, "DAI"),
            formatToken(wethBalance, "DAI")
          );
          break;
        default:
          console.log("Unimplemented");
      }
    }
    console.log();
  }
  
  async function newOffer(contract, base_sym, quote_sym, wants, gives) {
    function getAddress(sym) {
      switch (sym) {
        case "WETH":
          return wEth.address;
        default:
          return dai.address;
      }
    }
    base = getAddress(base_sym);
    quote = getAddress(quote_sym);
    offerTx = await contract.newOffer(
      base,
      quote,
      wants,
      gives,
      ethers.constants.MaxUint256,
      ethers.constants.MaxUint256,
      ethers.constants.MaxUint256
    );
    await offerTx.wait();
    console.log(
      "\t \x1b[44m\x1b[37m OFFER \x1b[0m[\x1b[32m" +
        formatToken(wants, base_sym) +
        base_sym +
        "\x1b[0m | \x1b[31m" +
        formatToken(gives, quote_sym) +
        quote_sym +
        "\x1b[0m]"
    );
  }
  
  async function snipe(mgv, base_sym, quote_sym, offerId, wants, gives) {
    function getAddress(sym) {
      switch (sym) {
        case "WETH":
          return wEth.address;
        default:
          return dai.address;
      }
    }
    base = getAddress(base_sym);
    quote = getAddress(quote_sym);
  
    snipeTx = await mgv.snipe(
      base,
      quote,
      offerId,
      wants,
      gives,
      ethers.constants.MaxUint256, // max gas
      true //fillWants
    );
    receipt = await snipeTx.wait(0);
    //    console.log(receipt.gasUsed.toString());
  
    console.log(
      "\t \x1b[44m\x1b[37m TAKE \x1b[0m[\x1b[32m" +
        formatToken(wants, base_sym) +
        base_sym +
        "\x1b[0m | \x1b[31m" +
        formatToken(gives, quote_sym) +
        quote_sym +
        "\x1b[0m]"
    );
  }
  
  // describe("Access to compound", function() {
  //     it("Should access comptroller implementation", async function () {
  //         let oracle = await comp.oracle();
  //         assert(oracle != ethers.constants.AddressZero, "Could not access oracle implementaion");
  //     })
  // });
  
  async function setDecimals() {
    decimals.set("DAI", await dai.decimals());
    decimals.set("ETH", 18);
    decimals.set("WETH", await wEth.decimals());
    decimals.set("cETH", await cEth.decimals());
    decimals.set("cDAI", await cDai.decimals());
  }
  
  function parseToken(amount, symbol) {
    return ethers.utils.parseUnits(amount, decimals.get(symbol));
  }
  function formatToken(amount, symbol) {
    return ethers.utils.formatUnits(amount, decimals.get(symbol));
  }