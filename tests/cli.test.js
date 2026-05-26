import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

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

  assert.equal([0, 1].includes(result.status), true, result.stderr);
  const payload = JSON.parse(result.stdout);
  assert.equal(payload.schemaVersion, "2026-05-26.port-manager.cli.v1");
  assert.equal(payload.ok, true);
  assert.equal(payload.command, "explain");
  assert.equal(payload.result.query.port, 9);
});

