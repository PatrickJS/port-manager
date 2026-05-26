import net from "node:net";
import {
  acquirePortLease,
  clearHeldPortLeasesSync,
  hasActivePortLease,
} from "./leases.js";

const DEFAULT_HOST = "127.0.0.1";
const MIN_PORT = 0;
const MAX_PORT = 65535;
const DEFAULT_LOCK_MS = 25_000;

const lockedPorts = new Map();

export function portNumbers(from, to) {
  const start = normalizePort(from, "from");
  const end = normalizePort(to, "to");
  if (start < 1024) {
    throw new RangeError("from must be 1024 or greater");
  }
  if (end < start) {
    throw new RangeError("to must be greater than or equal to from");
  }

  return {
    *[Symbol.iterator]() {
      for (let port = start; port <= end; port += 1) {
        yield port;
      }
    },
  };
}

export function clearLockedPorts() {
  for (const timeout of lockedPorts.values()) {
    clearTimeout(timeout);
  }
  lockedPorts.clear();
  clearHeldPortLeasesSync();
}

export async function isPortAvailable(options) {
  const { port, host = DEFAULT_HOST, exclude = [] } = normalizeOptions(options);
  const excludedPorts = new Set(Array.from(exclude, Number));

  if (excludedPorts.has(port) || lockedPorts.has(port)) {
    return false;
  }
  if (await hasActivePortLease({ port, host })) {
    return false;
  }

  const status = await getPortStatus({ port, host });
  return status.status === "closed";
}

export async function checkPort(options) {
  const normalized = normalizeOptions(options);
  const status = await getPortStatus(normalized);

  return {
    schemaVersion: "2026-05-26.port-manager.check.v1",
    host: normalized.host,
    port: normalized.port,
    inUse: status.status === "open" || status.status === "reserved",
    status: status.status,
    reserved: status.status === "reserved",
    errorCode: status.errorCode ?? null,
  };
}

export async function findAvailablePort(options = {}) {
  const host = options.host ?? DEFAULT_HOST;
  const exclude = new Set(Array.from(options.exclude ?? [], Number));
  const shared = options.shared !== false;
  let requestedPort = undefined;

  for (const port of candidatePorts(options)) {
    if (requestedPort === undefined) {
      requestedPort = port;
    }
    if (exclude.has(port) || lockedPorts.has(port)) {
      continue;
    }
    if (shared && await hasActivePortLease({ port, host })) {
      continue;
    }

    const attempt = await listen({ port, host, keepOpen: false });
    if (attempt.ok) {
      if (options.reserve === true) {
        if (shared) {
          const lease = await acquirePortLease({
            host,
            port: attempt.port,
            ttlMs: options.leaseMs ?? DEFAULT_LOCK_MS,
            reason: "findAvailablePort",
          });
          if (!lease) {
            continue;
          }
        } else {
          lockPort(attempt.port);
        }
      }
      return {
        schemaVersion: "2026-05-26.port-manager.find.v1",
        host,
        port: attempt.port,
        requestedPort,
        changed: requestedPort !== undefined && requestedPort !== attempt.port,
        reserved: options.reserve === true,
      };
    }
  }

  throw Object.assign(new Error("No available port found"), {
    code: "PORT_MANAGER_NO_AVAILABLE_PORT",
    host,
    requestedPort,
  });
}

export async function reservePort(options = {}) {
  const host = options.host ?? DEFAULT_HOST;
  const exclude = new Set(Array.from(options.exclude ?? [], Number));
  const shared = options.shared !== false;
  let requestedPort = undefined;

  for (const port of candidatePorts(options)) {
    if (requestedPort === undefined) {
      requestedPort = port;
    }
    if (exclude.has(port) || lockedPorts.has(port)) {
      continue;
    }
    if (shared && await hasActivePortLease({ port, host })) {
      continue;
    }

    const attempt = await listen({ port, host, keepOpen: true });
    if (attempt.ok) {
      const lease = shared
        ? await acquirePortLease({
          host,
          port: attempt.port,
          ttlMs: options.leaseMs ?? DEFAULT_LOCK_MS,
          reason: "reservePort",
          refresh: true,
        })
        : null;

      if (shared && !lease) {
        await closeServer(attempt.server);
        continue;
      }

      let released = false;
      return {
        schemaVersion: "2026-05-26.port-manager.reserve.v1",
        host,
        port: attempt.port,
        requestedPort,
        changed: requestedPort !== undefined && requestedPort !== attempt.port,
        async release() {
          if (released) {
            return;
          }
          released = true;
          await closeServer(attempt.server);
          await lease?.release();
        },
      };
    }
  }

  throw Object.assign(new Error("No reservable port found"), {
    code: "PORT_MANAGER_NO_RESERVABLE_PORT",
    host,
    requestedPort,
  });
}

export async function waitForPort(options) {
  const {
    port,
    host = DEFAULT_HOST,
    status = "open",
    retryTimeMs = 100,
    timeoutMs = 2_000,
  } = normalizeOptions(options);
  const deadline = Date.now() + timeoutMs;
  const wantOpen = status === "open" || status === true || status === "used";

  while (Date.now() <= deadline) {
    const result = await checkPort({ port, host });
    if (result.inUse === wantOpen) {
      return result;
    }
    await delay(retryTimeMs);
  }

  throw Object.assign(new Error(`Timed out waiting for port ${port} to become ${wantOpen ? "open" : "closed"}`), {
    code: "PORT_MANAGER_WAIT_TIMEOUT",
    host,
    port,
    status,
    timeoutMs,
  });
}

async function getPortStatus({ port, host = DEFAULT_HOST }) {
  const attempt = await listen({ port, host, keepOpen: false });
  if (attempt.ok) {
    if (lockedPorts.has(port) || await hasActivePortLease({ port, host })) {
      return { status: "reserved" };
    }
    return { status: "closed" };
  }
  if (attempt.error?.code === "EADDRINUSE") {
    return { status: "open", errorCode: attempt.error.code };
  }
  return { status: "unavailable", errorCode: attempt.error?.code ?? "UNKNOWN" };
}

function normalizeOptions(options) {
  if (typeof options === "number") {
    return { port: normalizePort(options, "port"), host: DEFAULT_HOST };
  }
  if (!options || typeof options !== "object") {
    throw new TypeError("Expected a port number or options object");
  }
  return {
    ...options,
    host: options.host ?? DEFAULT_HOST,
    port: normalizePort(options.port, "port"),
  };
}

function* candidatePorts(options) {
  if (options.random === true) {
    for (let i = 0; i < 50; i += 1) {
      yield randomEphemeralPort();
    }
    return;
  }

  if (options.port !== undefined) {
    if (isIterable(options.port) && typeof options.port !== "string") {
      for (const port of options.port) {
        yield normalizePort(port, "port");
      }
    } else {
      const start = normalizePort(options.port, "port");
      if (start === 0) {
        yield 0;
      } else {
        const stop = normalizePort(options.stopPort ?? options.highestPort ?? MAX_PORT, "stopPort");
        for (let port = start; port <= stop; port += 1) {
          yield port;
        }
      }
    }
  }

  if (options.ports !== undefined) {
    for (const port of options.ports) {
      yield normalizePort(port, "ports item");
    }
  }

  if (options.portRange !== undefined) {
    const [from, to] = options.portRange;
    const start = normalizePort(from, "portRange[0]");
    const end = normalizePort(to, "portRange[1]");
    for (let port = start; port <= end; port += 1) {
      yield port;
    }
  }

  if (options.port === undefined && options.ports === undefined && options.portRange === undefined) {
    yield 0;
  }
}

function lockPort(port) {
  const existing = lockedPorts.get(port);
  if (existing) {
    clearTimeout(existing);
  }
  const timeout = setTimeout(() => lockedPorts.delete(port), DEFAULT_LOCK_MS);
  timeout.unref?.();
  lockedPorts.set(port, timeout);
}

function listen({ port, host, keepOpen }) {
  return new Promise((resolve) => {
    const server = net.createServer();
    let settled = false;

    server.once("error", (error) => {
      if (settled) {
        return;
      }
      settled = true;
      resolve({ ok: false, error });
    });

    server.listen({ port, host, exclusive: true }, async () => {
      if (settled) {
        return;
      }
      settled = true;
      const address = server.address();
      const actualPort = typeof address === "object" && address ? address.port : port;
      if (keepOpen) {
        resolve({ ok: true, server, port: actualPort });
      } else {
        await closeServer(server);
        resolve({ ok: true, port: actualPort });
      }
    });
  });
}

function closeServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => {
      if (error && error.code !== "ERR_SERVER_NOT_RUNNING") {
        reject(error);
      } else {
        resolve();
      }
    });
  });
}

function normalizePort(value, label) {
  const port = Number(value);
  if (!Number.isInteger(port) || port < MIN_PORT || port > MAX_PORT) {
    throw new RangeError(`${label} must be an integer between ${MIN_PORT} and ${MAX_PORT}`);
  }
  return port;
}

function isIterable(value) {
  return value != null && typeof value[Symbol.iterator] === "function";
}

function randomEphemeralPort() {
  return Math.floor(Math.random() * (65535 - 49152 + 1)) + 49152;
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
