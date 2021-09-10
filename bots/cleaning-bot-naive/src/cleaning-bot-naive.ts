import dotenvFlow from "dotenv-flow";
dotenvFlow.config();
if (!process.env["NODE_CONFIG_DIR"]) {
  process.env["NODE_CONFIG_DIR"] = __dirname + "/config/";
}
import config from "config";

import Mangrove from "../../../mangrove.js/src/index";

const main = async () => {
  const mgv = await Mangrove.connect("http://127.0.0.1:8545");

  const cfg = await mgv.config();
  console.dir(cfg);
}

main();