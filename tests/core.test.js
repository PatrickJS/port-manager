import assert from "node:assert/strict";
import { test } from "node:test";
import {
  checkPort,
  clearLockedPorts,
  explainPort,
  findAvailablePort,
  isPortAvailable,
  reservePort,
} from "@patrickjs/port-manager";

test("findAvailablePort returns the requested free port", async () => {
  const result = await findAvailablePort({ port: 41000, stopPort: 41100 });

  assert.equal(result.host, "127.0.0.1");
  assert.equal(result.requestedPort, 41000);
  assert.equal(result.port >= 41000, true);
  assert.equal(result.port <= 41100, true);
});

test("findAvailablePort increments when the requested port is already reserved", async () => {
  const first = await findAvailablePort({ port: 42000, stopPort: 42100 });
  const reservation = await reservePort({ port: first.port });

  try {
    const second = await findAvailablePort({ port: first.port, stopPort: first.port + 5 });
    assert.equal(second.port > first.port, true);
  } finally {
    await reservation.release();
  }
});

test("reservePort holds the port until release", async () => {
  const reservation = await reservePort({ port: 0 });

  try {
    assert.equal(await isPortAvailable({ port: reservation.port }), false);
    const status = await checkPort({ port: reservation.port });
    assert.equal(status.inUse, true);
    assert.equal(status.status, "open");
  } finally {
    await reservation.release();
  }

  assert.equal(await isPortAvailable({ port: reservation.port }), true);
});

test("checkPort reports unavailable ports separately from in-use ports", async () => {
  const status = await checkPort({ port: 9 });

  if (status.status === "unavailable") {
    assert.equal(status.inUse, false);
    assert.equal(typeof status.errorCode, "string");
  } else {
    assert.ok(["closed", "open"].includes(status.status));
  }
});

test("reserved get-port style locks can be cleared", async () => {
  clearLockedPorts();
  const first = await findAvailablePort({ port: 43000, stopPort: 43010, reserve: true });
  const second = await findAvailablePort({ port: 43000, stopPort: 43010 });

  assert.notEqual(second.port, first.port);

  clearLockedPorts();
  const third = await findAvailablePort({ port: first.port, stopPort: first.port });
  assert.equal(third.port, first.port);
});

test("explainPort returns a stable JSON shape", async () => {
  const reservation = await reservePort({ port: 0 });

  try {
    const explanation = await explainPort({ port: reservation.port });
    assert.equal(explanation.schemaVersion, "2026-05-26.port-manager.explain.v1");
    assert.equal(explanation.query.port, reservation.port);
    assert.ok(["free", "inUse"].includes(explanation.status));
    assert.equal(Array.isArray(explanation.owners), true);
  } finally {
    await reservation.release();
  }
});
