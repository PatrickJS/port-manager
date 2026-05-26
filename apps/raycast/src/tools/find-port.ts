import { findAvailablePort } from "../port-manager";

type Input = {
  /**
   * Optional preferred starting TCP port.
   */
  port?: number;
  /**
   * Optional highest TCP port to scan through.
   */
  stopPort?: number;
  /**
   * Whether to create a short cooperative Port Manager reservation.
   */
  reserve?: boolean;
};

export default async function tool(input: Input) {
  return findAvailablePort({
    port: input.port,
    stopPort: input.stopPort,
    reserve: input.reserve,
  });
}
