import { createLogger, BetterLogger, format } from "@giry/commonlib-js";
import os from "os";
import config from "./config";

const consoleLogFormat = format.printf(
  ({ level, message, timestamp, ...metadata }) => {
    let msg = `${timestamp} [${level}] `;
    if (metadata.market) {
      msg += `[(${metadata.market.base.name}, ${metadata.market.quote.name})] `;
    }
    if (metadata.bookSide) {
      msg += `[${metadata.bookSide}`;
      if (metadata.offer) {
        msg += `#${metadata.offer.id}`;
      }
      msg += "] ";
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
// export const logger: BetterLogger = createLogger(consoleLogFormat, logLevel);
// FIXME logging somehow causes an out of memory exception when running under test - this needs fixing
export const logger = {
  info: (...args: any[]) => {},
  warn: (...args: any[]) => {},
  debug: (...args: any[]) => {},
  error: (...args: any[]) => {},
  exception: (...args: any[]) => {},
};

export default logger;
