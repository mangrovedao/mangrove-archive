import { config } from "./config";
import { createLogger, format, transports } from "winston";
const consoleLogFormat = format.printf(
  ({ level, message, timestamp, ...metadata }) => {
    let msg = `${timestamp} [${level}] : ${message} `;
    if (metadata) {
      msg += JSON.stringify(metadata);
    }
    return msg;
  }
);

export const logger = createLogger({
  transports: [
    new transports.Console({
      level: config.get("log.logLevel"),
      format: format.combine(
        format.colorize(),
        format.splat(),
        format.timestamp(),
        consoleLogFormat
      ),
    }),
  ],
});
