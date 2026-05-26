import {
  checkPort as coreCheckPort,
  findAvailablePort,
  reservePort,
  waitForPort as coreWaitForPort,
} from "@patrickjs/port-manager";

export async function getPort(options = {}) {
  const result = await findAvailablePort({
    port: options.port,
    ports: options.ports,
    portRange: options.portRange ?? options.alternativePortRange,
    host: options.host,
    random: options.random,
  });
  return result.port;
}

export async function checkPort(port, host) {
  const result = await coreCheckPort({ port, host });
  return result.inUse ? false : result.port;
}

export async function waitForPort(port, options = {}) {
  const result = await coreWaitForPort({
    port,
    host: options.host,
    status: "open",
    retryTimeMs: options.retryTimeMs,
    timeoutMs: options.timeoutMs,
  });
  return result.inUse ? result.port : false;
}

export async function getRandomPort(host) {
  return getPort({ random: true, host });
}

export async function getSocketAddress(options = {}) {
  const reservation = await reservePort({ port: options.port ?? 0, host: options.host });
  const address = { port: reservation.port, host: reservation.host };
  await reservation.release();
  return address;
}

export function isSocketSupported() {
  return true;
}

export function cleanSocket() {}

export default {
  getPort,
  checkPort,
  waitForPort,
  getRandomPort,
  getSocketAddress,
  isSocketSupported,
  cleanSocket,
};

