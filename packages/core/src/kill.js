import { explainPort } from "./explain.js";

export async function killPort(options) {
  const port = normalizePort(typeof options === "number" ? options : options?.port);
  const host = typeof options === "object" ? options.host : undefined;
  const pid = typeof options === "object" && options.pid !== undefined ? normalizePid(options.pid) : undefined;
  const signal = typeof options === "object" && options.signal ? String(options.signal) : "SIGTERM";
  const explanation = await explainPort({ port, host });
  const owners = pid === undefined
    ? explanation.owners
    : explanation.owners.filter((owner) => owner.pid === pid);

  if (owners.length === 0) {
    throw Object.assign(new Error(`No process owner found for port ${port}`), {
      code: "PORT_MANAGER_NO_OWNER",
      port,
      pid,
    });
  }

  const killed = [];
  const failed = [];

  for (const owner of owners) {
    if (owner.pid === process.pid) {
      failed.push({
        pid: owner.pid,
        name: owner.name,
        code: "PORT_MANAGER_REFUSE_SELF_KILL",
        message: "Refusing to kill the current port-manager process",
      });
      continue;
    }

    try {
      process.kill(owner.pid, signal);
      killed.push({
        pid: owner.pid,
        name: owner.name,
        signal,
      });
    } catch (error) {
      failed.push({
        pid: owner.pid,
        name: owner.name,
        code: error?.code ?? "PORT_MANAGER_KILL_FAILED",
        message: error?.message ?? String(error),
      });
    }
  }

  return {
    schemaVersion: "2026-05-26.port-manager.kill.v1",
    port,
    host: host ?? null,
    pid: pid ?? null,
    signal,
    killed,
    failed,
    ok: killed.length > 0 && failed.length === 0,
  };
}

function normalizePort(value) {
  const port = Number(value);
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    throw new RangeError("port must be an integer between 0 and 65535");
  }
  return port;
}

function normalizePid(value) {
  const pid = Number(value);
  if (!Number.isInteger(pid) || pid <= 0) {
    throw new RangeError("pid must be a positive integer");
  }
  return pid;
}
