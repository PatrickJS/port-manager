declare module "@patrickjs/port-manager" {
  export type PortOwner = {
    pid: number;
    name: string | null;
    user: string | null;
    uid: number | null;
    parentPid: number | null;
    command: string | null;
    args: string | null;
    cwd: string | null;
    launchd: { originator: string | null };
    ownership: {
      confidence: string;
      summary: string;
      evidence: string[];
    };
  };

  export type CommonPort = {
    name: string;
    expectedApps: string[];
  } | null;

  export type ListeningPortEntry = {
    port: number;
    host: string;
    protocol: string;
    status?: "listening" | "reserved";
    owner: PortOwner;
    commonPort: CommonPort;
  };

  export type PortGroupBinding = {
    host: string;
    port: number;
    protocol: string;
    label: string;
    ownerPid: number | null;
    ownerName: string | null;
    status?: "listening" | "reserved";
    commonPort: CommonPort;
  };

  export type ListeningPortGroup = {
    id: string;
    port: number;
    status: "listening" | "reserved" | "mixed";
    protocols: string[];
    title: string;
    reason: string;
    commonPort: CommonPort;
    owners: PortOwner[];
    bindings: PortGroupBinding[];
    entries: ListeningPortEntry[];
  };

  export function listListeningPorts(): Promise<{
    schemaVersion: string;
    generatedAt: string;
    ports: ListeningPortEntry[];
    portGroups: ListeningPortGroup[];
  }>;

  export function groupPortEntries(entries: ListeningPortEntry[]): ListeningPortGroup[];

  export function explainPort(options: { port: number; host?: string }): Promise<{
    schemaVersion: string;
    generatedAt: string;
    query: { port: number; host: string | null };
    status: "free" | "inUse" | "reserved";
    commonPort: CommonPort;
    owners: PortOwner[];
    reservations: unknown[];
  }>;

  export function findAvailablePort(options?: {
    port?: number;
    host?: string;
    stopPort?: number;
    reserve?: boolean;
  }): Promise<{
    schemaVersion: string;
    host: string;
    port: number;
    requestedPort: number | undefined;
    changed: boolean;
    reserved?: boolean;
  }>;

  export function killPort(options: {
    port: number;
    host?: string;
    pid?: number;
    signal?: string;
  }): Promise<{
    schemaVersion: string;
    port: number;
    host: string | null;
    pid: number | null;
    signal: string;
    killed: { pid: number; name: string | null; signal: string }[];
    failed: { pid: number; name: string | null; code: string; message: string }[];
    ok: boolean;
  }>;
}
