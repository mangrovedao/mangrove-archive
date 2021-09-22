import dotenvFlow from "dotenv-flow";
dotenvFlow.config();
if (!process.env["NODE_CONFIG_DIR"]) {
  process.env["NODE_CONFIG_DIR"] = __dirname + "/config/";
}
import config from "config";
console.dir(config);

import Mangrove from "@mangrove-exchange/mangrove-js";

const main = async () => {
  const mgv = await Mangrove.connect("http://127.0.0.1:8545"); // TODO move connection string / network name to configuration

  //FIXME Currently doesn't work
  const cfg = await mgv.config();

  console.log(`Mangrove config: ${cfg}`);
};

main();
