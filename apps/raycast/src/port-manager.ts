import {
  explainPort,
  findAvailablePort,
  groupPortEntries,
  killPort,
  listListeningPorts,
} from "@patrickjs/port-manager";

export { explainPort, findAvailablePort, killPort, groupPortEntries, listListeningPorts };

export type ListeningPortsPayload = Awaited<ReturnType<typeof listListeningPorts>>;
export type ListeningPortEntry = ListeningPortsPayload["ports"][number];
export type ListeningPortGroup = ListeningPortsPayload["portGroups"][number];

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

export function groupedPorts(result: ListeningPortsPayload) {
  return result.portGroups ?? groupPortEntries(result.ports);
}

export function portGroupTitle(group: ListeningPortGroup) {
  return group.title || `Port ${group.port}`;
}

export function portGroupSubtitle(group: ListeningPortGroup) {
  const common = group.commonPort ? ` · ${group.commonPort.name}` : "";
  return `${group.reason}${common}`;
}

export function portGroupBindings(group: ListeningPortGroup) {
  return group.bindings.map((binding) => binding.label).join(", ");
}

export function canKillGroup(group: ListeningPortGroup) {
  return group.status !== "reserved" && group.owners.some((owner) => owner.pid > 0);
}

export function killOptionsForGroup(group: ListeningPortGroup) {
  if (group.owners.length === 1 && group.owners[0]?.pid > 0) {
    return { port: group.port, pid: group.owners[0].pid };
  }
  return { port: group.port };
}
