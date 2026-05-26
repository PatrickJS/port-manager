import {
  explainPort,
  findAvailablePort,
  killPort,
  listListeningPorts,
} from "@patrickjs/port-manager";

export { explainPort, findAvailablePort, killPort, listListeningPorts };

export type ListeningPortsPayload = Awaited<ReturnType<typeof listListeningPorts>>;
export type ListeningPortEntry = ListeningPortsPayload["ports"][number];

export function portTitle(entry: ListeningPortEntry) {
  return entry.owner.name || `PID ${entry.owner.pid}`;
}

export function bindingLabel(entry: ListeningPortEntry) {
  return `${entry.host}:${entry.port}`;
}

export function portSubtitle(entry: ListeningPortEntry) {
  const status = entry.status === "reserved" ? "Reserved" : "Listening";
  const common = entry.commonPort ? ` · ${entry.commonPort.name}` : "";
  return `${status} · PID ${entry.owner.pid} · ${bindingLabel(entry)}${common}`;
}

export function canKill(entry: ListeningPortEntry) {
  return entry.status !== "reserved" && entry.owner.pid > 0;
}
