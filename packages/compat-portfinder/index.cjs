let basePort = 8000;
let highestPort = 65535;

function loadCore() {
  return import("@patrickjs/port-manager");
}

function setBasePort(port) {
  basePort = Number(port);
}

function setHighestPort(port) {
  highestPort = Number(port);
}

function getPort(options, callback) {
  const normalized = normalizeInvocation(options, callback);
  const promise = getPortPromise(normalized.options);

  if (normalized.callback) {
    promise.then(
      (port) => normalized.callback(null, port),
      (error) => normalized.callback(error),
    );
  }

  return promise;
}

async function getPortPromise(options = {}) {
  const { findAvailablePort } = await loadCore();
  const result = await findAvailablePort({
    port: options.port ?? basePort,
    stopPort: options.stopPort ?? highestPort,
    host: options.host,
  });
  return result.port;
}

function normalizeInvocation(options, callback) {
  if (typeof options === "function") {
    return { options: {}, callback: options };
  }
  return { options: options ?? {}, callback };
}

module.exports = {
  getPort,
  getPortPromise,
  setBasePort,
  setHighestPort,
};

