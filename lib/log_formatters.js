module.exports = (hre, formatArg) => {
  const ethers = hre.ethers;

  const logFormatters = {
    MakerFail: (log, rawLog, originator) => {
      const statusCode = hre.ethers.utils.parseBytes32String(
        log.args.statusCode
      );
      console.log("");
      console.log(`╭ Offer ${formatArg(log.args.offerId)} failed`);
      console.log(`┊ takerWants ${formatArg(log.args.takerWants)}`);
      console.log(`┊ takerGives ${formatArg(log.args.takerGives)}`);
      console.log(`╰ statusCode ${statusCode}`);
      console.log("");
    },
    Success: (log, rawLog, originator, formatArg) => {
      console.log("");
      console.log(`┏ Offer ${formatArg(log.args.offerId)} consumed`);
      console.log(`┃ takerWants ${formatArg(log.args.takerWants)}`);
      console.log(`┗ takerGives ${formatArg(log.args.takerGives)}`);
      console.log("");
    },
    ERC20Balances: (log, rawLog, originator, formatArg) => {
      /* Reminder:

      event ERC20Balances(
      address[] tokens,
      address[] accounts,
      uint[] balances,
    );

      */

      const tokens = {};

      log.args.tokens.forEach((token, i) => {
        tokens[token] = [];
      });

      log.args.tokens.forEach((token, i) => {
        const pad = i * log.args.accounts.length;
        log.args.accounts.forEach((account, j) => {
          if (!tokens[token]) tokens[token] = [];
          tokens[token].push({
            account: formatArg(account, "address"),
            balance: formatArg(log.args.balances[pad + j]),
          });
        });
      });

      const lineA = ({ account, balance }) => {
        const p = (s, n) =>
          (s.length > n ? s.slice(0, n - 1) + "…" : s).padEnd(n);
        const ps = (s, n) =>
          (s.length > n ? s.slice(0, n - 1) + "…" : s).padStart(n);
        return ` ${ps(account, 15)} │ ${p(balance, 10)}`;
      };

      console.log("");
      Object.entries(tokens).forEach(([token, balances]) => {
        console.log(formatArg(token, "address").padStart(19));
        console.log("─".repeat(17) + "┬" + "─".repeat(14));
        balances.forEach((info) => {
          console.log(lineA(info));
        });
      });
      console.log("");
    },
    OBState: (log, rawLog, originator, formatArg) => {
      /* Reminder:

      event OBState(
      address base,
      address quote,
      uint[] offerIds,
      uint[] wants,
      uint[] gives,
      address[] makerAddr
    );

      */

      const ob = log.args.offerIds.map((id, i) => {
        return {
          id: formatArg(id),
          wants: formatArg(log.args.wants[i]),
          gives: formatArg(log.args.gives[i]),
          maker: formatArg(log.args.makerAddr[i], "address"),
          gas: formatArg(log.args.gasreqs[i]),
        };
      });

      const lineA = ({ id, wants, gives, maker, gas }) => {
        const p = (s, n) =>
          (s.length > n ? s.slice(0, n - 1) + "…" : s).padEnd(n);
        return ` ${p(id, 3)}: ${p(wants, 15)}${p(gives, 15)}${p(gas, 15)}${p(
          maker,
          15
        )}`;
      };
      //const lineB = ({gas,gasprice});

      lineLength = 1 + 3 + 2 + 15 + 15 + 15 + 15;
      console.log("");
      console.log(
        `┃ ${formatArg(log.args.base)}/${formatArg(log.args.quote)} pair`
      );
      console.log("┡" + "━".repeat(lineLength) + "┑");
      console.log(
        "│" +
          lineA({
            id: "id",
            wants: "wants",
            gives: "gives",
            gas: "gasreq",
            maker: "maker",
          }) +
          "│"
      );
      console.log("├" + "─".repeat(lineLength) + "┤");
      ob.forEach((o) => console.log("│" + lineA(o) + "│"));
      console.log("└" + "─".repeat(lineLength) + "┘");
      console.log("");
    },
  };

  // construct logFormatters for regular logging with multiple arguments (up to 3)

  const basis = ["String", "Uint"];
  const next = (n) => basis.flatMap((x) => n.map((xs) => [x, ...xs]));
  const p1 = next([[]]);
  const p2 = next(p1);
  const p3 = next(p2);

  for (const types of [...p1, ...p2, ...p3]) {
    logFormatters[`Log${types.join("")}`] = (log, rawLog, originator) => {
      console.log("");
      console.log("➤ " + types.map((t, i) => formatArg(log.args[i])).join(" "));
      console.log("");
    };
  }

  return logFormatters;
};
