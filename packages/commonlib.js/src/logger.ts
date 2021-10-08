import { config } from "./config";
import {
  createLogger as winstonCreateLogger,
  format,
  transports,
  Logger,
} from "winston";
import os from "os";
import { ErrorWithData } from "./errorWithData";
import { Format } from "logform";

export type LogMetadata = {
  data?: Object;
  stack?: String;
};

export interface BetterLogger extends Logger {
  exception: (error: Error, data?: Object) => BetterLogger;
}

export const createLogger = (consoleFormatLogger: Format) => {
  var theLogger = winstonCreateLogger({
    transports: [
      new transports.Console({
        level: config.get("log.logLevel"),
        handleExceptions: true,
        format: format.combine(
          format.colorize(),
          format.splat(),
          format.timestamp(),
          consoleFormatLogger
        ),
      }),
    ],
  }) as BetterLogger;

  theLogger.exception = function (error: Error, data?: Object) {
    const message = error.message;
    const stack = error.stack;

    if (error instanceof ErrorWithData) {
      data = error.data;
    }

    return this.error(message, { stack: stack, data: data }) as BetterLogger;
  };

  return theLogger as BetterLogger;
};

export default createLogger;
