import { config } from "./config";
import { createLogger, format, transports, Logger } from "winston";
import os from "os";
import { ErrorWithData } from "./errorWithData";

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

export type LogMetadata = {
  data?: Object;
  stack?: String;
};

export interface BetterLogger extends Logger {
  exception: (error: Error, data?: Object) => BetterLogger;
}

export const logger: BetterLogger = createLogger({
  transports: [
    new transports.Console({
      level: config.get("log.logLevel"),
      handleExceptions: true,
      format: format.combine(
        format.colorize(),
        format.splat(),
        format.timestamp(),
        consoleLogFormat
      ),
    }),
  ],
}) as BetterLogger;

// Monkey patching Winston because it incorrectly logs `Error` instances even in 2021
// Related issue: https://github.com/winstonjs/winston/issues/1498
logger.exception = function (error: Error, data?: Object) {
  const message = error.message;
  const stack = error.stack;

  if (error instanceof ErrorWithData) {
    data = error.data;
  }

  return this.error(message, { stack: stack, data: data }) as BetterLogger;
};

export default logger;
