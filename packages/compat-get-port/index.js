import {
  clearLockedPorts,
  findAvailablePort,
  portNumbers,
} from "@patrickjs/port-manager";

export default async function getPort(options = {}) {
  const result = await findAvailablePort({
    port: options.port,
    exclude: options.exclude,
    host: options.host,
    reserve: options.reserve,
  });
  return result.port;
}

export { clearLockedPorts, portNumbers };

