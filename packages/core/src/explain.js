import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const COMMON_PORTS = new Map([
  [80, { name: "HTTP", expectedApps: ["web server", "reverse proxy"] }],
  [443, { name: "HTTPS / QUIC", expectedApps: ["web server", "reverse proxy", "VPN"] }],
  [3000, { name: "Common dev server", expectedApps: ["Next.js", "React", "Node.js"] }],
  [3306, { name: "MySQL", expectedApps: ["mysqld"] }],
  [5173, { name: "Vite dev server", expectedApps: ["Vite", "Node.js"] }],
  [5432, { name: "PostgreSQL", expectedApps: ["postgres"] }],
  [6379, { name: "Redis", expectedApps: ["redis-server"] }],
  [7860, { name: "Gradio / ML demo", expectedApps: ["Python", "Gradio"] }],
  [8000, { name: "Common local web server", expectedApps: ["Python", "Node.js"] }],
  [8080, { name: "Common alternate HTTP", expectedApps: ["web server", "proxy"] }],
  [8888, { name: "Jupyter", expectedApps: ["Jupyter", "Python"] }],
  [9222, { name: "Chrome DevTools", expectedApps: ["Chrome", "Chromium"] }],
  [11434, { name: "Ollama", expectedApps: ["ollama"] }],
  [27017, { name: "MongoDB", expectedApps: ["mongod"] }],
]);

export async function explainPort(options) {
  const port = normalizePort(typeof options === "number" ? options : options?.port);
  const host = typeof options === "object" ? options.host : undefined;
  const owners = await inspectPortOwners(port);
  const filteredOwners = host ? owners.filter((owner) => owner.binds.some((bind) => bind.host === host)) : owners;

  return {
    schemaVersion: "2026-05-26.port-manager.explain.v1",
    generatedAt: new Date().toISOString(),
    query: { port, host: host ?? null },
    status: filteredOwners.length > 0 ? "inUse" : "free",
    commonPort: COMMON_PORTS.get(port) ?? null,
    owners: filteredOwners,
  };
}

export async function listListeningPorts() {
  const records = await runLsof(["-nP", "-iTCP", "-sTCP:LISTEN", "-FpcRuLPn"]);
  const owners = await enrichProcesses(parseLsof(records));
  const ports = [];

  for (const owner of owners) {
    for (const bind of owner.binds) {
      ports.push({
        port: bind.port,
        host: bind.host,
        protocol: bind.protocol,
        owner,
        commonPort: COMMON_PORTS.get(bind.port) ?? null,
      });
    }
  }

  return {
    schemaVersion: "2026-05-26.port-manager.list.v1",
    generatedAt: new Date().toISOString(),
    ports: ports.sort((a, b) => a.port - b.port || a.host.localeCompare(b.host)),
  };
}

async function inspectPortOwners(port) {
  const output = await runLsof(["-nP", `-iTCP:${port}`, "-sTCP:LISTEN", "-FpcRuLPn"]);
  return enrichProcesses(parseLsof(output));
}

async function enrichProcesses(processes) {
  const enriched = [];
  for (const process of processes) {
    const [ps, cwd, launch] = await Promise.all([
      getPsInfo(process.pid),
      getCwd(process.pid),
      getLaunchInfo(process.pid),
    ]);
    const name = process.name ?? ps.commandName ?? null;
    const evidence = [
      `lsof reported PID ${process.pid}`,
      ...process.binds.map((bind) => `bound ${bind.protocol} ${bind.host}:${bind.port}`),
    ];

    if (ps.args) {
      evidence.push(`ps args: ${ps.args}`);
    }
    if (launch.originator) {
      evidence.push(`launchd originator: ${launch.originator}`);
    }

    enriched.push({
      pid: process.pid,
      name,
      user: process.user ?? ps.user ?? null,
      uid: process.uid ?? null,
      parentPid: process.parentPid ?? ps.parentPid ?? null,
      command: ps.command ?? null,
      args: ps.args ?? null,
      cwd,
      launchd: launch,
      binds: process.binds,
      ownership: {
        confidence: ps.command || launch.originator ? "high" : "medium",
        summary: `${name ?? "PID " + process.pid} owns ${process.binds.map((bind) => `${bind.host}:${bind.port}`).join(", ")}`,
        evidence,
      },
    });
  }
  return enriched;
}

function parseLsof(output) {
  const processes = [];
  let current = null;
  let currentProtocol = "TCP";

  for (const line of output.split("\n")) {
    if (!line) {
      continue;
    }
    const prefix = line[0];
    const value = line.slice(1);

    if (prefix === "p") {
      current = {
        pid: Number(value),
        binds: [],
      };
      processes.push(current);
      continue;
    }

    if (!current) {
      continue;
    }

    switch (prefix) {
      case "c":
        current.name = value;
        break;
      case "R":
        current.parentPid = Number(value);
        break;
      case "u":
        current.uid = Number(value);
        break;
      case "L":
        current.user = value;
        break;
      case "P":
        currentProtocol = value;
        break;
      case "n": {
        const bind = parseBind(value, currentProtocol);
        if (bind) {
          current.binds.push(bind);
        }
        break;
      }
      default:
        break;
    }
  }

  return processes.filter((process) => process.binds.length > 0);
}

function parseBind(value, protocol) {
  const index = value.lastIndexOf(":");
  if (index === -1) {
    return null;
  }
  const host = value.slice(0, index);
  const port = Number(value.slice(index + 1));
  if (!Number.isInteger(port)) {
    return null;
  }
  return { host, port, protocol };
}

async function getPsInfo(pid) {
  const [parentPid, user, command, args] = await Promise.all([
    runPs(pid, "ppid="),
    runPs(pid, "user="),
    runPs(pid, "comm="),
    runPs(pid, "args="),
  ]);

  return {
    parentPid: parentPid ? Number(parentPid) : null,
    user: user || null,
    command: command || null,
    commandName: command ? command.split("/").at(-1) : null,
    args: args || null,
  };
}

async function runPs(pid, field) {
  try {
    const { stdout } = await execFileAsync("/bin/ps", ["-p", String(pid), "-o", field], {
      maxBuffer: 1024 * 1024,
    });
    return stdout.trim();
  } catch {
    return "";
  }
}

async function getCwd(pid) {
  try {
    const { stdout } = await execFileAsync("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd", "-Fn"], {
      maxBuffer: 1024 * 1024,
    });
    return stdout
      .split("\n")
      .find((line) => line.startsWith("n"))
      ?.slice(1) ?? null;
  } catch {
    return null;
  }
}

async function getLaunchInfo(pid) {
  try {
    const { stdout } = await execFileAsync("/bin/launchctl", ["print", `pid/${pid}`], {
      maxBuffer: 1024 * 1024,
    });
    const originator = stdout.match(/originator = (.+)/)?.[1]?.trim() ?? null;
    return { originator };
  } catch {
    return { originator: null };
  }
}

async function runLsof(args) {
  try {
    const { stdout } = await execFileAsync("/usr/sbin/lsof", args, {
      maxBuffer: 4 * 1024 * 1024,
    });
    return stdout;
  } catch (error) {
    if (error && typeof error === "object" && "stdout" in error && error.stdout) {
      return String(error.stdout);
    }
    return "";
  }
}

function normalizePort(value) {
  const port = Number(value);
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    throw new RangeError("port must be an integer between 0 and 65535");
  }
  return port;
}

