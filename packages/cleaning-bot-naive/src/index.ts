import { URL } from "url";

if (!process.env["NODE_CONFIG_DIR"]) {
  process.env["NODE_CONFIG_DIR"] = __dirname + "/config/";
}

import dotenvFlow from "dotenv-flow";
dotenvFlow.config();
import config from "config";

const message = "Hello, World!";
console.log(message);
