import { Action, Tool } from "@raycast/api";
import { killPort } from "../port-manager";

type Input = {
  /**
   * The TCP port whose owning process should receive SIGTERM.
   */
  port: number;
  /**
   * Optional exact process id to kill. Prefer passing this after list-ports or explain-port.
   */
  pid?: number;
  /**
   * Optional host address to filter by, for example 127.0.0.1.
   */
  host?: string;
};

export const confirmation: Tool.Confirmation<Input> = async (input) => {
  return {
    style: Action.Style.Destructive,
    message: `Send SIGTERM to the process owning port ${input.port}?`,
    info: [
      { name: "Port", value: String(input.port) },
      { name: "PID", value: input.pid === undefined ? undefined : String(input.pid) },
      { name: "Host", value: input.host },
    ],
  };
};

export default async function tool(input: Input) {
  return killPort({
    port: input.port,
    pid: input.pid,
    host: input.host,
  });
}
