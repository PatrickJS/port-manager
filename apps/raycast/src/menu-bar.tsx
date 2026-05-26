import {
  Alert,
  Clipboard,
  confirmAlert,
  Icon,
  launchCommand,
  LaunchType,
  MenuBarExtra,
  openCommandPreferences,
  openExtensionPreferences,
  showToast,
  Toast,
} from "@raycast/api";
import { useEffect, useState } from "react";
import {
  bindingLabel,
  canKill,
  killPort,
  listListeningPorts,
  ListeningPortEntry,
  portTitle,
} from "./port-manager";

type State = {
  isLoading: boolean;
  ports: ListeningPortEntry[];
  error?: Error;
};

export default function Command() {
  const [state, setState] = useState<State>({ isLoading: true, ports: [] });

  useEffect(() => {
    listListeningPorts()
      .then((result) => setState({ isLoading: false, ports: result.ports }))
      .catch((error) => setState({ isLoading: false, ports: [], error: error as Error }));
  }, []);

  const visiblePorts = state.ports.slice(0, 30);

  return (
    <MenuBarExtra icon={Icon.Network} isLoading={state.isLoading}>
      <MenuBarExtra.Section title="Open Ports">
        {state.error ? (
          <MenuBarExtra.Item title="Port scan failed" subtitle={truncate(state.error.message, 30)} />
        ) : null}
        {visiblePorts.map((entry) => (
          <PortMenuItem key={`${entry.owner.pid}-${entry.host}-${entry.port}`} entry={entry} />
        ))}
        {!state.error && visiblePorts.length === 0 && !state.isLoading ? (
          <MenuBarExtra.Item title="No Open Ports" />
        ) : null}
      </MenuBarExtra.Section>
      <MenuBarExtra.Item
        title="Open Port List"
        icon={Icon.List}
        onAction={() => launchCommand({ name: "list-ports", type: LaunchType.UserInitiated })}
      />
      <MenuBarExtra.Section title="Preferences">
        <MenuBarExtra.Item title="Command Preferences" onAction={openCommandPreferences} />
        <MenuBarExtra.Item title="Extension Preferences" onAction={openExtensionPreferences} />
      </MenuBarExtra.Section>
    </MenuBarExtra>
  );
}

function PortMenuItem(props: { entry: ListeningPortEntry }) {
  const { entry } = props;
  const title = truncate(`${entry.port} • ${portTitle(entry)}`, 30);

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
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = "Failed to kill port";
      toast.message = error instanceof Error ? error.message : String(error);
    }
  }

  return (
    <MenuBarExtra.Submenu title={title}>
      <MenuBarExtra.Item title={truncate(portTitle(entry), 30)} />
      <MenuBarExtra.Item title={truncate(bindingLabel(entry), 30)} />
      <MenuBarExtra.Item title={truncate(`PID ${entry.owner.pid}`, 30)} />
      {entry.commonPort ? <MenuBarExtra.Item title={truncate(entry.commonPort.name, 30)} /> : null}
      <MenuBarExtra.Separator />
      <MenuBarExtra.Item title="Copy Binding" icon={Icon.Clipboard} onAction={() => Clipboard.copy(bindingLabel(entry))} />
      {canKill(entry) ? (
        <MenuBarExtra.Item title="Kill Port" icon={Icon.XMarkCircle} onAction={killSelected} />
      ) : null}
    </MenuBarExtra.Submenu>
  );
}

function truncate(value: string, maxLength: number) {
  if (value.length <= maxLength) {
    return value;
  }
  return `${value.slice(0, maxLength - 1)}…`;
}
