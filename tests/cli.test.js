import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { test } from "node:test";
import { tmpdir } from "node:os";

const cli = new URL("../packages/cli/bin/port-manager.js", import.meta.url);

test("CLI find emits stable JSON", () => {
  const result = spawnSync(process.execPath, [cli.pathname, "find", "0", "--json"], {
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr);
  const payload = JSON.parse(result.stdout);
  assert.equal(payload.schemaVersion, "2026-05-26.port-manager.cli.v1");
  assert.equal(payload.ok, true);
  assert.equal(payload.command, "find");
  assert.equal(typeof payload.result.port, "number");
});

test("CLI explain emits stable JSON", () => {
  const result = spawnSync(process.execPath, [cli.pathname, "explain", "9", "--json"], {
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr);
  const payload = JSON.parse(result.stdout);
  assert.equal(payload.schemaVersion, "2026-05-26.port-manager.cli.v1");
  assert.equal(payload.ok, true);
  assert.equal(payload.command, "explain");
  assert.equal(payload.result.query.port, 9);
});

test("CLI list includes shared reserved ports", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "port-manager-cli-test-"));
  const env = {
    ...process.env,
    PORT_MANAGER_STATE_DIR: stateDir,
  };

  try {
    const reserved = spawnSync(process.execPath, [
      cli.pathname,
      "find",
      "45000",
      "--stop-port",
      "45010",
      "--reserve",
      "--json",
    ], { encoding: "utf8", env });

    assert.equal(reserved.status, 0, reserved.stderr);
    const reservedPayload = JSON.parse(reserved.stdout);

    const listed = spawnSync(process.execPath, [cli.pathname, "list", "--json"], {
      encoding: "utf8",
      env,
    });

    assert.equal(listed.status, 0, listed.stderr);
    const listedPayload = JSON.parse(listed.stdout);
    const port = reservedPayload.result.port;

    assert.equal(listedPayload.result.reservations.some((reservation) => reservation.port === port), true);
    assert.equal(listedPayload.result.ports.some((entry) => entry.port === port && entry.status === "reserved"), true);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("CLI kill reports missing owners as JSON", () => {
  const result = spawnSync(process.execPath, [cli.pathname, "kill", "9", "--json"], {
    encoding: "utf8",
  });

  assert.notEqual(result.status, 0);
  const payload = JSON.parse(result.stderr);
  assert.equal(payload.schemaVersion, "2026-05-26.port-manager.cli.v1");
  assert.equal(payload.ok, false);
  assert.equal(payload.error.code, "PORT_MANAGER_NO_OWNER");
});
