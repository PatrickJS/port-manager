import { existsSync, readFileSync, rmSync } from "node:fs";
import { mkdir, open, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import os from "node:os";

const LEASE_SCHEMA_VERSION = "2026-05-26.port-manager.lease.v1";
const DEFAULT_LEASE_MS = 25_000;
const PROCESS_INSTANCE_ID = randomUUID();
const heldLeases = new Map();

export async function acquirePortLease(options) {
  const host = options.host ?? "127.0.0.1";
  const port = Number(options.port);
  const ttlMs = Number(options.ttlMs ?? DEFAULT_LEASE_MS);
  const refresh = options.refresh === true;
  const path = leasePath(host, port);

  await mkdir(stateDir(), { recursive: true, mode: 0o700 });

  while (true) {
    try {
      const handle = await open(path, "wx", 0o600);
      const record = createLeaseRecord({ host, port, ttlMs, reason: options.reason });
      try {
        await handle.writeFile(JSON.stringify(record, null, 2));
      } finally {
        await handle.close();
      }
      return holdLease(path, record, refresh);
    } catch (error) {
      if (error?.code !== "EEXIST") {
        throw error;
      }

      const existing = await readLeasePath(path);
      if (existing && !isExpired(existing)) {
        return null;
      }

      await rm(path, { force: true });
    }
  }
}

export async function hasActivePortLease(options) {
  const lease = await readLease(options);
  return lease !== null;
}

export async function listPortReservations() {
  let entries = [];
  try {
    entries = await readdir(stateDir());
  } catch (error) {
    if (error?.code === "ENOENT") {
      return [];
    }
    throw error;
  }

  const reservations = [];
  for (const entry of entries) {
    if (!entry.endsWith(".json")) {
      continue;
    }
    const path = join(stateDir(), entry);
    const lease = await readLeasePath(path);
    if (!lease) {
      continue;
    }
    reservations.push(lease);
  }

  return reservations.sort((a, b) => a.port - b.port || a.host.localeCompare(b.host));
}

export function clearHeldPortLeasesSync() {
  for (const lease of heldLeases.values()) {
    lease.releaseSync();
  }
  heldLeases.clear();
}

async function readLease({ host = "127.0.0.1", port }) {
  return readLeasePath(leasePath(host, Number(port)));
}

async function readLeasePath(path) {
  let record;
  try {
    record = JSON.parse(await readFile(path, "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") {
      return null;
    }
    await rm(path, { force: true });
    return null;
  }

  if (!isValidLease(record) || isExpired(record)) {
    await rm(path, { force: true });
    return null;
  }

  return record;
}

function holdLease(path, record, refresh) {
  const lease = {
    path,
    record,
    interval: null,
    async release() {
      if (lease.interval) {
        clearInterval(lease.interval);
        lease.interval = null;
      }
      heldLeases.delete(record.id);
      await releasePathIfOwned(path, record.id);
    },
    releaseSync() {
      if (lease.interval) {
        clearInterval(lease.interval);
        lease.interval = null;
      }
      heldLeases.delete(record.id);
      try {
        if (existsSync(path)) {
          const existing = JSON.parse(readFileSync(path, "utf8"));
          if (existing.id === record.id) {
            rmSync(path, { force: true });
          }
        }
      } catch {
        // Best-effort cleanup for a process-local developer lock.
      }
    },
  };

  if (refresh) {
    lease.interval = setInterval(() => {
      refreshLease(path, record).catch(() => {});
    }, Math.max(1_000, Math.floor(record.ttlMs / 2)));
    lease.interval.unref?.();
  }

  heldLeases.set(record.id, lease);
  return lease;
}

async function refreshLease(path, record) {
  const existing = await readLeasePath(path);
  if (!existing || existing.id !== record.id) {
    return;
  }

  const next = {
    ...record,
    expiresAt: new Date(Date.now() + record.ttlMs).toISOString(),
  };
  record.expiresAt = next.expiresAt;
  await writeFile(path, JSON.stringify(next, null, 2));
}

async function releasePathIfOwned(path, id) {
  try {
    const existing = JSON.parse(await readFile(path, "utf8"));
    if (existing.id === id) {
      await rm(path, { force: true });
    }
  } catch {
    // The lease may already have expired or been cleaned up.
  }
}

function createLeaseRecord({ host, port, ttlMs, reason }) {
  const now = Date.now();
  return {
    schemaVersion: LEASE_SCHEMA_VERSION,
    id: randomUUID(),
    instanceId: PROCESS_INSTANCE_ID,
    host,
    port,
    protocol: "TCP",
    reason: reason ?? "reservation",
    pid: process.pid,
    argv0: process.argv[1] ?? process.argv[0] ?? null,
    cwd: process.cwd(),
    uid: typeof process.getuid === "function" ? process.getuid() : null,
    createdAt: new Date(now).toISOString(),
    expiresAt: new Date(now + ttlMs).toISOString(),
    ttlMs,
  };
}

function isValidLease(record) {
  return record?.schemaVersion === LEASE_SCHEMA_VERSION
    && typeof record.id === "string"
    && typeof record.host === "string"
    && Number.isInteger(record.port)
    && typeof record.expiresAt === "string";
}

function isExpired(record) {
  const expiresAt = Date.parse(record.expiresAt);
  return !Number.isFinite(expiresAt) || expiresAt <= Date.now();
}

function leasePath(host, port) {
  return join(stateDir(), `${port}-${Buffer.from(host).toString("base64url")}.json`);
}

function stateDir() {
  return process.env.PORT_MANAGER_STATE_DIR
    ?? join(os.tmpdir(), "patrickjs-port-manager", String(process.getuid?.() ?? "user"));
}
