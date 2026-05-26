import { findAvailablePort } from "@patrickjs/port-manager";

export async function detect(port = 0, host) {
  const result = await findAvailablePort({ port, host });
  return result.port;
}

export default detect;

