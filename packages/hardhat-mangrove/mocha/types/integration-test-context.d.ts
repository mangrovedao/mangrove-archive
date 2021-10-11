// Extension of Mocha Context for Integration tests
import { Provider } from "@ethersproject/abstract-provider";

declare module "mocha" {
  export interface Context {
    provider: Provider;
  }
}
