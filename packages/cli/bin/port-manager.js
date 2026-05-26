#!/usr/bin/env node
import {
  checkPort,
  explainPort,
  findAvailablePort,
  killPort,
  listListeningPorts,
  reservePort,
} from "@patrickjs/port-manager";

const SCHEMA_VERSION = "2026-05-26.port-manager.cli.v1";

try {
  await main(process.argv.slice(2));
} catch (error) {
  const payload = {
    schemaVersion: SCHEMA_VERSION,
    ok: false,
    error: {
      code: error?.code ?? "PORT_MANAGER_ERROR",
      message: error?.message ?? String(error),
    },
  };
  console.error(JSON.stringify(payload, null, 2));
  process.exitCode = 1;
}

async function main(argv) {
  const command = argv[0] ?? "help";
  const args = parseArgs(argv.slice(1));

  if (command === "help" || args.help) {
    printHelp();
    return;
  }

  if (command === "find") {
    const result = await findAvailablePort({
      port: args.positionals[0] === undefined ? undefined : Number(args.positionals[0]),
      host: args.host,
      stopPort: args.stopPort === undefined ? undefined : Number(args.stopPort),
      reserve: args.reserve === true,
    });
    printResult({ ok: true, command, result }, args.json);
    return;
  }

  if (command === "check") {
    const port = requiredPort(args.positionals[0], command);
    const result = await checkPort({ port, host: args.host });
    printResult({ ok: true, command, result }, args.json);
    return;
  }

  if (command === "explain") {
    const port = requiredPort(args.positionals[0], command);
    const result = await explainPort({ port, host: args.host });
    printResult({ ok: true, command, result }, args.json);
    return;
  }

  if (command === "list") {
    const result = await listListeningPorts();
    printResult({ ok: true, command, result }, args.json);
    return;
  }

  if (command === "kill") {
    const port = requiredPort(args.positionals[0], command);
    const result = await killPort({
      port,
      host: args.host,
      pid: args.pid === undefined ? undefined : Number(args.pid),
      signal: args.signal ?? (args.force ? "SIGKILL" : "SIGTERM"),
    });
    printResult({ ok: result.ok, command, result }, args.json);
    if (!result.ok) {
      process.exitCode = 1;
    }
    return;
  }

  if (command === "reserve") {
    const port = requiredPort(args.positionals[0], command);
    const reservation = await reservePort({ port, host: args.host });
    const holdMs = args.holdMs === undefined ? 0 : Number(args.holdMs);
    printResult({
      ok: true,
      command,
      result: publicReservation(reservation, holdMs),
    }, args.json);

    if (holdMs > 0) {
      await delay(holdMs);
    }
    await reservation.release();
    return;
  }

  throw Object.assign(new Error(`Unknown command: ${command}`), {
    code: "PORT_MANAGER_UNKNOWN_COMMAND",
  });
}

function parseArgs(argv) {
  const parsed = {
    positionals: [],
    json: false,
    help: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--json") {
      parsed.json = true;
    } else if (arg === "--help" || arg === "-h") {
      parsed.help = true;
    } else if (arg.startsWith("--host=")) {
      parsed.host = arg.slice("--host=".length);
    } else if (arg === "--host") {
      parsed.host = argv[++index];
    } else if (arg.startsWith("--stop-port=")) {
      parsed.stopPort = arg.slice("--stop-port=".length);
    } else if (arg === "--stop-port") {
      parsed.stopPort = argv[++index];
    } else if (arg === "--reserve") {
      parsed.reserve = true;
    } else if (arg.startsWith("--hold-ms=")) {
      parsed.holdMs = arg.slice("--hold-ms=".length);
    } else if (arg === "--hold-ms") {
      parsed.holdMs = argv[++index];
    } else if (arg.startsWith("--pid=")) {
      parsed.pid = arg.slice("--pid=".length);
    } else if (arg === "--pid") {
      parsed.pid = argv[++index];
    } else if (arg.startsWith("--signal=")) {
      parsed.signal = arg.slice("--signal=".length);
    } else if (arg === "--signal") {
      parsed.signal = argv[++index];
    } else if (arg === "--force") {
      parsed.force = true;
    } else {
      parsed.positionals.push(arg);
    }
  }

  return parsed;
}

function requiredPort(value, command) {
  if (value === undefined) {
    throw Object.assign(new Error(`Command "${command}" requires a port`), {
      code: "PORT_MANAGER_MISSING_PORT",
    });
  }
  const port = Number(value);
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    throw Object.assign(new Error("Port must be an integer between 0 and 65535"), {
      code: "PORT_MANAGER_BAD_PORT",
    });
  }
  return port;
}

function printResult(payload, asJson) {
  const output = {
    schemaVersion: SCHEMA_VERSION,
    ...payload,
  };
  if (asJson) {
    console.log(JSON.stringify(output, null, 2));
  } else if (payload.result?.port !== undefined) {
    console.log(payload.result.port);
  } else {
    console.log(JSON.stringify(output, null, 2));
  }
}

function publicReservation(reservation, holdMs) {
  return {
    schemaVersion: reservation.schemaVersion,
    host: reservation.host,
    port: reservation.port,
    requestedPort: reservation.requestedPort,
    changed: reservation.changed,
    holdMs,
  };
}

function printHelp() {
  console.log(`Usage:
  port-manager find [port] [--json] [--host 127.0.0.1] [--stop-port 3100]
  port-manager check <port> [--json]
  port-manager explain <port> [--json]
  port-manager list [--json]
  port-manager kill <port> [--pid 123] [--signal SIGTERM] [--force] [--json]
  port-manager reserve <port> [--json] [--hold-ms 1000]
`);
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
