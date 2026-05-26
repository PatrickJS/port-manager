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
  canKillGroup,
  groupedPorts,
  killOptionsForGroup,
  killPort,
  listListeningPorts,
  ListeningPortGroup,
  portGroupBindings,
  portGroupSubtitle,
  portGroupTitle,
} from "./port-manager";

type State = {
  isLoading: boolean;
  portGroups: ListeningPortGroup[];
  error?: Error;
};

export default function Command() {
  const [state, setState] = useState<State>({ isLoading: true, portGroups: [] });

  async function refresh() {
    setState((current) => ({ ...current, isLoading: true, error: undefined }));
    try {
      const result = await listListeningPorts();
      setState({ isLoading: false, portGroups: groupedPorts(result) });
    } catch (error) {
      setState({ isLoading: false, portGroups: [], error: error as Error });
    }
  }

  useEffect(() => {
    refresh();
  }, []);

  const sections = useMemo(() => {
    const listening = state.portGroups.filter((group) => group.status !== "reserved");
    const reserved = state.portGroups.filter((group) => group.status === "reserved");
    return { listening, reserved };
  }, [state.portGroups]);

  return (
    <List isLoading={state.isLoading} searchBarPlaceholder="Search ports, apps, users, paths">
      {state.error ? (
        <List.EmptyView icon={Icon.Warning} title="Port Manager failed" description={state.error.message} />
      ) : null}
      <List.Section title="Listening" subtitle={`${sections.listening.length}`}>
        {sections.listening.map((group) => (
          <PortItem key={group.id} group={group} onRefresh={refresh} />
        ))}
      </List.Section>
      <List.Section title="Reserved" subtitle={`${sections.reserved.length}`}>
        {sections.reserved.map((group) => (
          <PortItem key={group.id} group={group} onRefresh={refresh} />
        ))}
      </List.Section>
    </List>
  );
}

function PortItem(props: { group: ListeningPortGroup; onRefresh: () => Promise<void> }) {
  const { group, onRefresh } = props;
  const accessories: List.Item.Accessory[] = [
    { text: group.commonPort?.name },
    {
      tag: {
        value: group.status === "reserved" ? "Reserved" : "Listening",
        color: group.status === "reserved" ? Color.Orange : Color.Green,
      },
    },
  ];

  async function killSelected() {
    const confirmed = await confirmAlert({
      title: "Kill Port?",
      message: `Send SIGTERM to ${group.owners.length === 1 ? portGroupTitle(group) : `${group.owners.length} owners`} for port ${group.port}.`,
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
      const result = await killPort(killOptionsForGroup(group));
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
      title={portGroupTitle(group)}
      subtitle={portGroupSubtitle(group)}
      icon={group.status === "reserved" ? Icon.Lock : Icon.Network}
      accessories={accessories}
      detail={
        <List.Item.Detail
          markdown={[
            `# ${group.port} - ${portGroupTitle(group)}`,
            "",
            `**Reason:** ${group.reason}`,
            `**Bindings:** ${portGroupBindings(group)}`,
            "",
            "## Owners",
            ...group.owners.map((owner) => `- ${owner.name ?? `PID ${owner.pid}`} (PID ${owner.pid})`),
            "",
            "## Bindings",
            ...group.bindings.map((binding) => `- ${bindingTitle(binding)}`),
            "",
            "## Evidence",
            ...group.entries.flatMap((entry) => entry.owner.ownership.evidence.map((line) => `- ${line}`)),
          ].join("\n")}
        />
      }
      actions={
        <ActionPanel>
          <Action.CopyToClipboard title={group.bindings.length === 1 ? "Copy Binding" : "Copy Bindings"} content={portGroupBindings(group)} />
          <Action
            title="Copy JSON"
            icon={Icon.Clipboard}
            onAction={() => Clipboard.copy(JSON.stringify(group, null, 2))}
          />
          {canKillGroup(group) ? (
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

function bindingTitle(binding: ListeningPortGroup["bindings"][number]) {
  const owner = binding.ownerName && binding.ownerPid
    ? ` - ${binding.ownerName} (PID ${binding.ownerPid})`
    : "";
  return `${binding.label}${owner}`;
}
