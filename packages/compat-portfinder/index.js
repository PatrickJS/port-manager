import { findAvailablePort } from "@patrickjs/port-manager";

let basePort = 8000;
let highestPort = 65535;

export function setBasePort(port) {
  basePort = Number(port);
}

export function setHighestPort(port) {
  highestPort = Number(port);
}

export function getPort(options, callback) {
  const { normalizedOptions, normalizedCallback } = normalizeInvocation(options, callback);
  const promise = getPortPromise(normalizedOptions);

  if (normalizedCallback) {
    promise.then(
      (port) => normalizedCallback(null, port),
      (error) => normalizedCallback(error),
    );
  }

  return promise;
}

export async function getPortPromise(options = {}) {
  const result = await findAvailablePort({
    port: options.port ?? basePort,
    stopPort: options.stopPort ?? highestPort,
    host: options.host,
  });
  return result.port;
}

export default {
  getPort,
  getPortPromise,
  setBasePort,
  setHighestPort,
};

function normalizeInvocation(options, callback) {
  if (typeof options === "function") {
    return { normalizedOptions: {}, normalizedCallback: options };
  }
  return { normalizedOptions: options ?? {}, normalizedCallback: callback };
}

