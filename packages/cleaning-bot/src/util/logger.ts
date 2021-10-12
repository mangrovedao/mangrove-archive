import { createLogger, BetterLogger, format } from "@giry/commonlib-js";
import os from "os";

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

export const logger: BetterLogger = createLogger(consoleLogFormat);

export default logger;
