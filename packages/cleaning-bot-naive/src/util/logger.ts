import { config } from "./config";
import { createLogger, format, transports } from "winston";
const consoleLogFormat = format.printf(
  ({ level, message, timestamp, ...metadata }) => {
    let msg = `${timestamp} [${level}] `;
    if (metadata.market) {
      msg += `[(${metadata.market.base.name}, ${metadata.market.quote.name})] `;
    }
    msg += message;
    if (metadata.data) {
      msg += ` | ${JSON.stringify(metadata.data)}`;
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
