import {
  Action,
  ActionPanel,
  Alert,
  Clipboard,
  Color,
  confirmAlert,
  Icon,
  List,
  showToast,
  Toast,
} from "@raycast/api";
import { useEffect, useMemo, useState } from "react";
import {
  bindingLabel,
  canKill,
  killPort,
  listListeningPorts,
  ListeningPortEntry,
  portSubtitle,
  portTitle,
} from "./port-manager";

type State = {
  isLoading: boolean;
  ports: ListeningPortEntry[];
  error?: Error;
};

export default function Command() {
  const [state, setState] = useState<State>({ isLoading: true, ports: [] });

  async function refresh() {
    setState((current) => ({ ...current, isLoading: true, error: undefined }));
    try {
      const result = await listListeningPorts();
      setState({ isLoading: false, ports: result.ports });
    } catch (error) {
      setState({ isLoading: false, ports: [], error: error as Error });
    }
  }

  useEffect(() => {
    refresh();
  }, []);

  const sections = useMemo(() => {
    const listening = state.ports.filter((entry) => entry.status !== "reserved");
    const reserved = state.ports.filter((entry) => entry.status === "reserved");
    return { listening, reserved };
  }, [state.ports]);

  return (
    <List isLoading={state.isLoading} searchBarPlaceholder="Search ports, apps, users, paths">
      {state.error ? (
        <List.EmptyView icon={Icon.Warning} title="Port Manager failed" description={state.error.message} />
      ) : null}
      <List.Section title="Listening" subtitle={`${sections.listening.length}`}>
        {sections.listening.map((entry) => (
          <PortItem key={`${entry.owner.pid}-${entry.host}-${entry.port}`} entry={entry} onRefresh={refresh} />
        ))}
      </List.Section>
      <List.Section title="Reserved" subtitle={`${sections.reserved.length}`}>
        {sections.reserved.map((entry) => (
          <PortItem key={`${entry.owner.pid}-${entry.host}-${entry.port}`} entry={entry} onRefresh={refresh} />
        ))}
      </List.Section>
    </List>
  );
}

function PortItem(props: { entry: ListeningPortEntry; onRefresh: () => Promise<void> }) {
  const { entry, onRefresh } = props;
  const accessories: List.Item.Accessory[] = [
    { text: entry.commonPort?.name },
    {
      tag: {
        value: entry.status === "reserved" ? "Reserved" : "Listening",
        color: entry.status === "reserved" ? Color.Orange : Color.Green,
      },
    },
  ];

  async function killSelected() {
    const confirmed = await confirmAlert({
      title: "Kill Port?",
      message: `Send SIGTERM to ${portTitle(entry)} (PID ${entry.owner.pid}) for ${bindingLabel(entry)}.`,
      primaryAction: {
        title: "Kill Port",
        style: Alert.ActionStyle.Destructive,
      },
    });

    if (!confirmed) {
      return;
    }

    const toast = await showToast({ style: Toast.Style.Animated, title: "Killing port owner" });
    try {
      const result = await killPort({ port: entry.port, host: entry.host, pid: entry.owner.pid });
      toast.style = Toast.Style.Success;
      toast.title = result.killed.length > 0 ? "Kill signal sent" : "No process killed";
      toast.message = result.killed.map((process) => process.name ?? `PID ${process.pid}`).join(", ");
      await onRefresh();
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = "Failed to kill port";
      toast.message = error instanceof Error ? error.message : String(error);
    }
  }

  return (
    <List.Item
      title={portTitle(entry)}
      subtitle={portSubtitle(entry)}
      icon={entry.status === "reserved" ? Icon.Lock : Icon.Network}
      accessories={accessories}
      detail={
        <List.Item.Detail
          markdown={[
            `# ${portTitle(entry)}`,
            "",
            `**Binding:** ${bindingLabel(entry)}`,
            `**PID:** ${entry.owner.pid}`,
            `**User:** ${entry.owner.user ?? "unknown"}`,
            `**Command:** ${entry.owner.command ?? "unknown"}`,
            `**Working Directory:** ${entry.owner.cwd ?? "unknown"}`,
            "",
            "## Evidence",
            ...entry.owner.ownership.evidence.map((line) => `- ${line}`),
          ].join("\n")}
        />
      }
      actions={
        <ActionPanel>
          <Action.CopyToClipboard title="Copy Binding" content={bindingLabel(entry)} />
          <Action
            title="Copy JSON"
            icon={Icon.Clipboard}
            onAction={() => Clipboard.copy(JSON.stringify(entry, null, 2))}
          />
          {canKill(entry) ? (
            <Action
              title="Kill Port"
              icon={Icon.XMarkCircle}
              style={Action.Style.Destructive}
              onAction={killSelected}
              shortcut={{ modifiers: ["cmd", "shift"], key: "k" }}
            />
          ) : null}
          <Action title="Refresh" icon={Icon.ArrowClockwise} onAction={onRefresh} shortcut={{ modifiers: ["cmd"], key: "r" }} />
        </ActionPanel>
      }
    />
  );
}
