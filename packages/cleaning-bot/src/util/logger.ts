import { createLogger, BetterLogger, format } from "@giry/commonlib-js";
import os from "os";
import config from "./config";

const consoleLogFormat = format.printf(
  ({ level, message, timestamp, ...metadata }) => {
    let msg = `${timestamp} [${level}] `;
    if (metadata.market) {
      msg += `[(${metadata.market.base.name}, ${metadata.market.quote.name})] `;
    }
    msg += message;
    if (metadata.data !== undefined) {
      msg += ` | data: ${JSON.stringify(metadata.data)}`;
    }
    if (metadata.stack) {
      msg += `${os.EOL}${metadata.stack}`;
    }
    return msg;
  }
);

const logLevel = config.get<string>("log.logLevel");
export const logger: BetterLogger = createLogger(consoleLogFormat, logLevel);

export default logger;
