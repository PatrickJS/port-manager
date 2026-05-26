import { explainPort } from "../port-manager";

type Input = {
  /**
   * The TCP port to explain.
   */
  port: number;
  /**
   * Optional host address to filter by, for example 127.0.0.1.
   */
  host?: string;
};

export default async function tool(input: Input) {
  return explainPort({ port: input.port, host: input.host });
}
