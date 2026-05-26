function loadCore() {
  return import("@patrickjs/port-manager");
}

async function getPort(options = {}) {
  const { findAvailablePort } = await loadCore();
  const result = await findAvailablePort({
    port: options.port,
    ports: options.ports,
    portRange: options.portRange || options.alternativePortRange,
    host: options.host,
    random: options.random,
  });
  return result.port;
}

async function checkPort(port, host) {
  const { checkPort: coreCheckPort } = await loadCore();
  const result = await coreCheckPort({ port, host });
  return result.inUse ? false : result.port;
}

async function waitForPort(port, options = {}) {
  const { waitForPort: coreWaitForPort } = await loadCore();
  const result = await coreWaitForPort({
    port,
    host: options.host,
    status: "open",
    retryTimeMs: options.retryTimeMs,
    timeoutMs: options.timeoutMs,
  });
  return result.inUse ? result.port : false;
}

async function getRandomPort(host) {
  return getPort({ random: true, host });
}

async function getSocketAddress(options = {}) {
  const { reservePort } = await loadCore();
  const reservation = await reservePort({ port: options.port || 0, host: options.host });
  const address = { port: reservation.port, host: reservation.host };
  await reservation.release();
  return address;
}

function isSocketSupported() {
  return true;
}

function cleanSocket() {}

module.exports = {
  getPort,
  checkPort,
  waitForPort,
  getRandomPort,
  getSocketAddress,
  isSocketSupported,
  cleanSocket,
};

