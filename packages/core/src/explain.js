import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { listPortReservations } from "./leases.js";

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

const DISPLAY_GROUPS = {
  webDev: { id: "web-dev", name: "Web Dev", rank: 10 },
  databases: { id: "databases", name: "Databases", rank: 20 },
  ai: { id: "ai", name: "AI", rank: 30 },
  tunnels: { id: "tunnels", name: "Tunnels", rank: 40 },
  system: { id: "system", name: "System", rank: 90 },
  other: { id: "other", name: "Other", rank: 100 },
};

export async function explainPort(options) {
  const port = normalizePort(typeof options === "number" ? options : options?.port);
  const host = typeof options === "object" ? options.host : undefined;
  const [owners, reservations] = await Promise.all([
    inspectPortOwners(port),
    listPortReservations(),
  ]);
  const filteredOwners = host ? owners.filter((owner) => owner.binds.some((bind) => bind.host === host)) : owners;
  const filteredReservations = reservations.filter((reservation) => {
    return reservation.port === port && (!host || reservation.host === host);
  });

  return {
    schemaVersion: "2026-05-26.port-manager.explain.v1",
    generatedAt: new Date().toISOString(),
    query: { port, host: host ?? null },
    status: filteredOwners.length > 0 ? "inUse" : filteredReservations.length > 0 ? "reserved" : "free",
    commonPort: COMMON_PORTS.get(port) ?? null,
    owners: filteredOwners,
    reservations: filteredReservations,
  };
}

export async function listListeningPorts() {
  const [records, reservations] = await Promise.all([
    runLsof(["-nP", "-iTCP", "-sTCP:LISTEN", "-FpcRuLPn"]),
    listPortReservations(),
  ]);
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

  for (const reservation of reservations) {
    if (ports.some((entry) => entry.port === reservation.port)) {
      continue;
    }
    ports.push({
      port: reservation.port,
      host: reservation.host,
      protocol: reservation.protocol,
      status: "reserved",
      owner: reservationOwner(reservation),
      commonPort: COMMON_PORTS.get(reservation.port) ?? null,
    });
  }

  const sortedPorts = ports.sort((a, b) => a.port - b.port || a.host.localeCompare(b.host));

  return {
    schemaVersion: "2026-05-26.port-manager.list.v1",
    generatedAt: new Date().toISOString(),
    reservations,
    ports: sortedPorts,
    portGroups: groupPortEntries(sortedPorts),
  };
}

export function groupPortEntries(entries) {
  const groups = new Map();

  for (const entry of entries) {
    let group = groups.get(entry.port);
    if (!group) {
      group = {
        port: entry.port,
        entries: [],
        ownersByKey: new Map(),
        bindingsByKey: new Map(),
        protocols: new Set(),
        statuses: new Set(),
        commonPort: null,
      };
      groups.set(entry.port, group);
    }

    group.entries.push(entry);
    group.protocols.add(entry.protocol);
    group.statuses.add(entry.status ?? "listening");
    group.commonPort ??= entry.commonPort ?? null;

    const ownerKey = ownerGroupKey(entry.owner);
    if (!group.ownersByKey.has(ownerKey)) {
      group.ownersByKey.set(ownerKey, entry.owner);
    }

    const bindingKey = `${entry.protocol}:${entry.host}:${entry.port}`;
    if (!group.bindingsByKey.has(bindingKey)) {
      group.bindingsByKey.set(bindingKey, {
        host: entry.host,
        port: entry.port,
        protocol: entry.protocol,
        label: `${entry.host}:${entry.port}`,
        ownerPid: entry.owner.pid,
        ownerName: ownerTitle(entry.owner),
        status: entry.status ?? "listening",
        commonPort: entry.commonPort ?? null,
      });
    }
  }

  return Array.from(groups.values())
    .sort((a, b) => a.port - b.port)
    .map(finalizePortGroup);
}

function finalizePortGroup(group) {
  const owners = Array.from(group.ownersByKey.values())
    .sort((a, b) => a.pid - b.pid || ownerTitle(a).localeCompare(ownerTitle(b)));
  const bindings = Array.from(group.bindingsByKey.values())
    .sort((a, b) => a.host.localeCompare(b.host) || a.protocol.localeCompare(b.protocol));
  const entries = [...group.entries]
    .sort((a, b) => a.host.localeCompare(b.host) || a.owner.pid - b.owner.pid);
  const statuses = Array.from(group.statuses).sort();

  return {
    id: `port-${group.port}`,
    port: group.port,
    status: statuses.length === 1 ? statuses[0] : "mixed",
    protocols: Array.from(group.protocols).sort(),
    title: groupTitle(owners),
    reason: `${owners.length} ${pluralize("owner", owners.length)} across ${bindings.length} ${pluralize("binding", bindings.length)}`,
    commonPort: group.commonPort,
    displayGroup: classifyDisplayGroup({ port: group.port, commonPort: group.commonPort, owners }),
    owners,
    bindings,
    entries,
  };
}

function classifyDisplayGroup({ port, commonPort, owners }) {
  const text = [
    commonPort?.name,
    ...(commonPort?.expectedApps ?? []),
    ...owners.flatMap((owner) => [
      owner.name,
      owner.command,
      owner.args,
      owner.cwd,
      owner.launchd?.originator,
    ]),
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  if (isSystemOwned(owners)) {
    return DISPLAY_GROUPS.system;
  }
  if (/\b(postgres|postgresql|mysql|mariadb|redis|mongo|mongodb|mongod)\b/.test(text)) {
    return DISPLAY_GROUPS.databases;
  }
  if (/\b(ollama|lm studio|llama|gradio|jupyter|notebook)\b/.test(text) || [7860, 8888, 11434].includes(port)) {
    return DISPLAY_GROUPS.ai;
  }
  if (/\b(tailscale|ipnextension|ngrok|cloudflared|cloudflare|tunnel|trycloudflare)\b/.test(text)) {
    return DISPLAY_GROUPS.tunnels;
  }
  if (isLikelyWebDevPort(port) || isWebDevOwned(owners)) {
    return DISPLAY_GROUPS.webDev;
  }
  return DISPLAY_GROUPS.other;
}

function isWebDevOwned(owners) {
  return owners.some((owner) => {
    const name = (owner.name ?? "").toLowerCase();
    const commandText = [
      owner.command,
      owner.args,
      owner.cwd,
    ].filter(Boolean).join(" ").toLowerCase();
    return /^(node|bun|deno)$/.test(name)
      || /\b(vite|next dev|astro|remix|webpack-dev-server|nuxt|svelte-kit|pnpm|npm run|yarn)\b/.test(commandText);
  });
}

function isSystemOwned(owners) {
  return owners.some((owner) => {
    const text = [
      owner.name,
      owner.command,
      owner.launchd?.originator,
    ].filter(Boolean).join(" ");
    return text.startsWith("/System/")
      || text.includes("/System/Library/")
      || /\b(ControlCenter|rapportd|sharingd|mDNSResponder|AirPlayXPCHelper)\b/.test(text);
  });
}

function isLikelyWebDevPort(port) {
  return (port >= 3000 && port <= 3010)
    || (port >= 4173 && port <= 4180)
    || (port >= 5173 && port <= 5180)
    || [8000, 8080].includes(port);
}

function ownerGroupKey(owner) {
  return owner.pid > 0 ? `pid:${owner.pid}` : `${owner.name ?? "owner"}:${owner.command ?? ""}`;
}

function groupTitle(owners) {
  if (owners.length === 0) {
    return "Unknown";
  }
  const first = ownerTitle(owners[0]);
  if (owners.length === 1) {
    return first;
  }
  return `${first} + ${owners.length - 1} more`;
}

function ownerTitle(owner) {
  return owner.name || `PID ${owner.pid}`;
}

function pluralize(word, count) {
  return count === 1 ? word : `${word}s`;
}

async function inspectPortOwners(port) {
  const output = await runLsof(["-nP", `-iTCP:${port}`, "-sTCP:LISTEN", "-FpcRuLPn"]);
  return enrichProcesses(parseLsof(output));
}

async function enrichProcesses(processes) {
  const enriched = [];
  for (const process of processes) {
    const binds = uniqueBinds(process.binds);
    const [ps, cwd, launch] = await Promise.all([
      getPsInfo(process.pid),
      getCwd(process.pid),
      getLaunchInfo(process.pid),
    ]);
    const name = process.name ?? ps.commandName ?? null;
    const evidence = [
      `lsof reported PID ${process.pid}`,
      ...binds.map((bind) => `bound ${bind.protocol} ${bind.host}:${bind.port}`),
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
      binds,
      ownership: {
        confidence: ps.command || launch.originator ? "high" : "medium",
        summary: `${name ?? "PID " + process.pid} owns ${binds.map((bind) => `${bind.host}:${bind.port}`).join(", ")}`,
        evidence,
      },
    });
  }
  return enriched;
}

function uniqueBinds(binds) {
  const seen = new Set();
  const unique = [];
  for (const bind of binds) {
    const key = `${bind.protocol}:${bind.host}:${bind.port}`;
    if (!seen.has(key)) {
      seen.add(key);
      unique.push(bind);
    }
  }
  return unique;
}

function reservationOwner(reservation) {
  const bind = {
    host: reservation.host,
    port: reservation.port,
    protocol: reservation.protocol,
  };

  return {
    pid: reservation.pid,
    name: "Port Manager reservation",
    user: null,
    uid: reservation.uid,
    parentPid: null,
    command: reservation.argv0,
    args: null,
    cwd: reservation.cwd,
    launchd: { originator: null },
    binds: [bind],
    reservation,
    ownership: {
      confidence: "high",
      summary: `Port Manager reserved ${reservation.host}:${reservation.port}`,
      evidence: [
        `port-manager lease ${reservation.id}`,
        `lease reason: ${reservation.reason}`,
        `expires at ${reservation.expiresAt}`,
      ],
    },
  };
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
