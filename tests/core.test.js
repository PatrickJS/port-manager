import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { test } from "node:test";
import { tmpdir } from "node:os";
import {
  checkPort,
  clearLockedPorts,
  explainPort,
  findAvailablePort,
  isPortAvailable,
  killPort,
  groupPortEntries,
  listListeningPorts,
  listPortReservations,
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

test("reserved find locks are shared through the local registry", async (t) => {
  const previousStateDir = process.env.PORT_MANAGER_STATE_DIR;
  const stateDir = await mkdtemp(join(tmpdir(), "port-manager-test-"));
  process.env.PORT_MANAGER_STATE_DIR = stateDir;
  clearLockedPorts();

  t.after(async () => {
    clearLockedPorts();
    if (previousStateDir === undefined) {
      delete process.env.PORT_MANAGER_STATE_DIR;
    } else {
      process.env.PORT_MANAGER_STATE_DIR = previousStateDir;
    }
    await rm(stateDir, { recursive: true, force: true });
  });

  const first = await findAvailablePort({ port: 44000, stopPort: 44010, reserve: true });
  const status = await checkPort({ port: first.port });
  const reservations = await listPortReservations();
  const second = await findAvailablePort({ port: first.port, stopPort: first.port + 5 });

  assert.equal(status.status, "reserved");
  assert.equal(status.reserved, true);
  assert.equal(reservations.some((reservation) => reservation.port === first.port), true);
  assert.equal(second.port > first.port, true);

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
    assert.ok(["free", "inUse", "reserved"].includes(explanation.status));
    assert.equal(Array.isArray(explanation.owners), true);
  } finally {
    await reservation.release();
  }
});

test("groupPortEntries folds duplicate bindings under one numeric port", () => {
  const postgres = {
    pid: 101,
    name: "postgres",
    user: "patrickjs",
    uid: 501,
    parentPid: 1,
    command: "/opt/homebrew/bin/postgres",
    args: "postgres -D /opt/homebrew/var/postgresql",
    cwd: "/opt/homebrew/var/postgresql",
    launchd: { originator: null },
    binds: [
      { host: "[::1]", port: 5432, protocol: "TCP" },
      { host: "127.0.0.1", port: 5432, protocol: "TCP" },
    ],
    ownership: {
      confidence: "high",
      summary: "postgres owns [::1]:5432, 127.0.0.1:5432",
      evidence: ["lsof reported PID 101"],
    },
  };
  const vite = {
    ...postgres,
    pid: 202,
    name: "node",
    command: "node",
    args: "vite --host 0.0.0.0 --port 5178",
    cwd: "/work/app",
    binds: [{ host: "*", port: 5178, protocol: "TCP" }],
    ownership: {
      confidence: "high",
      summary: "node owns *:5178",
      evidence: ["lsof reported PID 202"],
    },
  };
  const staticServer = {
    ...vite,
    pid: 303,
    binds: [{ host: "127.0.0.1", port: 5178, protocol: "TCP" }],
    ownership: {
      confidence: "high",
      summary: "node owns 127.0.0.1:5178",
      evidence: ["lsof reported PID 303"],
    },
  };

  const groups = groupPortEntries([
    { port: 5432, host: "[::1]", protocol: "TCP", owner: postgres, commonPort: { name: "PostgreSQL", expectedApps: ["postgres"] } },
    { port: 5432, host: "127.0.0.1", protocol: "TCP", owner: postgres, commonPort: { name: "PostgreSQL", expectedApps: ["postgres"] } },
    { port: 5178, host: "*", protocol: "TCP", owner: vite, commonPort: null },
    { port: 5178, host: "127.0.0.1", protocol: "TCP", owner: staticServer, commonPort: null },
  ]);

  assert.deepEqual(groups.map((group) => group.port), [5178, 5432]);
  assert.equal(groups[0].entries.length, 2);
  assert.equal(groups[0].owners.length, 2);
  assert.equal(groups[0].title, "node + 1 more");
  assert.equal(groups[0].reason, "2 owners across 2 bindings");
  assert.equal(groups[1].entries.length, 2);
  assert.equal(groups[1].owners.length, 1);
  assert.equal(groups[1].title, "postgres");
  assert.equal(groups[1].reason, "1 owner across 2 bindings");
  assert.deepEqual(groups[1].bindings.map((bind) => bind.label), ["[::1]:5432", "127.0.0.1:5432"]);
});

test("groupPortEntries assigns default display groups", () => {
  const owner = (overrides) => ({
    pid: overrides.pid,
    name: overrides.name,
    user: "patrickjs",
    uid: 501,
    parentPid: 1,
    command: overrides.command ?? overrides.name,
    args: overrides.args ?? overrides.command ?? overrides.name,
    cwd: overrides.cwd ?? "/",
    launchd: { originator: overrides.originator ?? null },
    binds: [{ host: "127.0.0.1", port: overrides.port, protocol: "TCP" }],
    ownership: {
      confidence: "high",
      summary: `${overrides.name} owns 127.0.0.1:${overrides.port}`,
      evidence: [`lsof reported PID ${overrides.pid}`],
    },
  });

  const groups = groupPortEntries([
    { port: 5173, host: "127.0.0.1", protocol: "TCP", owner: owner({ pid: 10, name: "node", port: 5173, args: "vite --port 5173" }), commonPort: { name: "Vite dev server", expectedApps: ["Vite", "Node.js"] } },
    { port: 5432, host: "127.0.0.1", protocol: "TCP", owner: owner({ pid: 11, name: "postgres", port: 5432 }), commonPort: { name: "PostgreSQL", expectedApps: ["postgres"] } },
    { port: 11434, host: "127.0.0.1", protocol: "TCP", owner: owner({ pid: 12, name: "ollama", port: 11434 }), commonPort: { name: "Ollama", expectedApps: ["ollama"] } },
    { port: 443, host: "*", protocol: "TCP", owner: owner({ pid: 13, name: "IPNExtension", port: 443, command: "/Applications/Tailscale.app/Contents/PlugIns/IPNExtension.appex/Contents/MacOS/IPNExtension" }), commonPort: { name: "HTTPS / QUIC", expectedApps: ["web server", "reverse proxy", "VPN"] } },
    { port: 5000, host: "*", protocol: "TCP", owner: owner({ pid: 14, name: "ControlCenter", port: 5000, command: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter", originator: "/System/Library/CoreServices/ControlCenter.app" }), commonPort: null },
    { port: 7265, host: "127.0.0.1", protocol: "TCP", owner: owner({ pid: 15, name: "Raycast", port: 7265, command: "/Applications/Raycast.app/Contents/MacOS/Raycast" }), commonPort: null },
    { port: 7676, host: "127.0.0.1", protocol: "TCP", owner: owner({ pid: 16, name: "Reflect", port: 7676, command: "/Applications/Reflect.app/Contents/MacOS/Reflect" }), commonPort: null },
    { port: 7768, host: "127.0.0.1", protocol: "TCP", owner: owner({ pid: 17, name: "Spotify", port: 7768, command: "/Applications/Spotify.app/Contents/MacOS/Spotify" }), commonPort: null },
    { port: 6463, host: "127.0.0.1", protocol: "TCP", owner: owner({ pid: 18, name: "Discord Helper (Renderer)", port: 6463, command: "/Applications/Discord.app/Contents/Frameworks/Discord Helper (Renderer).app/Contents/MacOS/Discord Helper (Renderer)" }), commonPort: null },
    { port: 49350, host: "127.0.0.1", protocol: "TCP", owner: owner({ pid: 19, name: "GitHub Desktop Helper (Renderer)", port: 49350, command: "/Applications/GitHub Desktop.app/Contents/Frameworks/GitHub Desktop Helper (Renderer).app/Contents/MacOS/GitHub Desktop Helper (Renderer)" }), commonPort: null },
    { port: 40423, host: "127.0.0.1", protocol: "TCP", owner: owner({ pid: 20, name: "Cursor Helper (Plugin)", port: 40423, command: "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper (Plugin).app/Contents/MacOS/Cursor Helper (Plugin)" }), commonPort: null },
    { port: 41737, host: "127.0.0.1", protocol: "TCP", owner: owner({ pid: 21, name: "node", port: 41737, args: "node /Users/patrickjs/.codex/plugins/goalbuddy/server.js", cwd: "/Users/patrickjs/.codex/plugins/goalbuddy" }), commonPort: null },
  ]);

  const displayGroupByPort = new Map(groups.map((group) => [group.port, group.displayGroup.name]));
  const displayRankByPort = new Map(groups.map((group) => [group.port, group.displayGroup.rank]));
  const titleByPort = new Map(groups.map((group) => [group.port, group.title]));

  assert.equal(displayGroupByPort.get(5173), "Web Dev");
  assert.equal(displayGroupByPort.get(5432), "Databases");
  assert.equal(displayGroupByPort.get(11434), "AI");
  assert.equal(displayGroupByPort.get(40423), "AI");
  assert.equal(displayGroupByPort.get(41737), "Web Dev");
  assert.equal(titleByPort.get(41737), "GoalBuddy");
  assert.equal(displayGroupByPort.get(443), "Tunnels");
  assert.equal(displayGroupByPort.get(5000), "OS / Apple");
  assert.equal(displayRankByPort.get(5000) > displayRankByPort.get(40423), true);
  assert.equal(displayGroupByPort.get(7265), "Apps");
  assert.equal(displayGroupByPort.get(7676), "Apps");
  assert.equal(displayGroupByPort.get(7768), "Apps");
  assert.equal(displayGroupByPort.get(6463), "Apps");
  assert.equal(displayGroupByPort.get(49350), "Apps");
});

test("listListeningPorts includes grouped display rows", async () => {
  const result = await listListeningPorts();

  assert.equal(Array.isArray(result.ports), true);
  assert.equal(Array.isArray(result.portGroups), true);
  assert.equal(result.portGroups.length <= result.ports.length, true);
});

test("killPort rejects a port with no process owner", async () => {
  await assert.rejects(
    () => killPort({ port: 9 }),
    (error) => error.code === "PORT_MANAGER_NO_OWNER",
  );
});
