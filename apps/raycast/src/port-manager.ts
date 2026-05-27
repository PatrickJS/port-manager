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

export function portGroupSections(groups: ListeningPortGroup[]) {
  const sections = new Map<string, { id: string; name: string; rank: number; groups: ListeningPortGroup[] }>();
  for (const group of groups) {
    const displayGroup = group.displayGroup ?? { id: "other", name: "Other", rank: 100 };
    const section = sections.get(displayGroup.id) ?? {
      id: displayGroup.id,
      name: displayGroup.name,
      rank: displayGroup.rank,
      groups: [],
    };
    section.groups.push(group);
    sections.set(displayGroup.id, section);
  }

  return Array.from(sections.values())
    .map((section) => ({
      ...section,
      groups: section.groups.sort((a, b) => a.port - b.port),
    }))
    .sort((a, b) => a.rank - b.rank || a.name.localeCompare(b.name));
}

export function portGroupTitle(group: ListeningPortGroup) {
  return group.title || `Port ${group.port}`;
}

export type PortGroupCluster = {
  id: string;
  title: string;
  groups: ListeningPortGroup[];
};

export function portGroupClusters(groups: ListeningPortGroup[], namespace: string): PortGroupCluster[] {
  const clusters = new Map<string, PortGroupCluster>();
  for (const group of groups) {
    const title = normalizedPortGroupTitle(portGroupTitle(group));
    const key = normalizedPortGroupKey(title);
    const cluster = clusters.get(key) ?? { id: `${namespace}-${key}`, title, groups: [] };
    cluster.groups.push(group);
    clusters.set(key, cluster);
  }

  return Array.from(clusters.values())
    .map((cluster) => ({
      ...cluster,
      groups: cluster.groups.sort((a, b) => a.port - b.port),
    }))
    .sort((a, b) => (a.groups[0]?.port ?? 0) - (b.groups[0]?.port ?? 0) || a.title.localeCompare(b.title));
}

function normalizedPortGroupTitle(title: string) {
  const lowercased = title.toLowerCase();
  if (lowercased === "ollama") return "Ollama";
  if (lowercased === "cursor" || lowercased.startsWith("cursor helper")) return "Cursor";
  if (lowercased.startsWith("github desktop helper")) return "GitHub Desktop";
  if (lowercased.startsWith("discord helper")) return "Discord";
  if (lowercased === "raycast") return "Raycast";
  if (lowercased === "reflect") return "Reflect";
  if (lowercased === "spotify") return "Spotify";
  if (lowercased === "ipnextension") return "Tailscale";
  if (lowercased === "cloudflared") return "Cloudflare Tunnel";
  if (lowercased === "ngrok") return "ngrok";
  return title;
}

function normalizedPortGroupKey(title: string) {
  return title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
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
