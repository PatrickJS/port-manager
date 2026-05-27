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
import { Fragment, useEffect, useState } from "react";
import {
  canKillGroup,
  groupedPorts,
  killOptionsForGroup,
  killPort,
  listListeningPorts,
  portGroupClusters,
  PortGroupCluster,
  ListeningPortGroup,
  portGroupBindings,
  portGroupSections,
  portGroupTitle,
} from "./port-manager";

type State = {
  isLoading: boolean;
  portGroups: ListeningPortGroup[];
  error?: Error;
};

export default function Command() {
  const [state, setState] = useState<State>({ isLoading: true, portGroups: [] });

  useEffect(() => {
    listListeningPorts()
      .then((result) => setState({ isLoading: false, portGroups: groupedPorts(result) }))
      .catch((error) => setState({ isLoading: false, portGroups: [], error: error as Error }));
  }, []);

  const visibleSections = portGroupSections(state.portGroups.slice(0, 40));
  const regularSections = visibleSections.filter((section) => !isSafeToIgnoreSection(section));
  const safeSections = visibleSections.filter(isSafeToIgnoreSection);

  return (
    <MenuBarExtra icon={Icon.Network} isLoading={state.isLoading}>
      <MenuBarExtra.Section>
        {state.error ? (
          <MenuBarExtra.Item title="Port scan failed" subtitle={truncate(state.error.message, 30)} />
        ) : null}
        {!state.error && visibleSections.length === 0 && !state.isLoading ? (
          <MenuBarExtra.Item title="No Open Ports" />
        ) : null}
      </MenuBarExtra.Section>
      {regularSections.map((section) => (
        <MenuBarExtra.Section key={section.id} title={section.name}>
          {portGroupClusters(section.groups, section.id).map((cluster) => (
            <PortClusterMenuItem key={cluster.id} cluster={cluster} />
          ))}
        </MenuBarExtra.Section>
      ))}
      {safeSections.length > 0 ? (
        <MenuBarExtra.Submenu title={`OS / Apple · Safe to ignore (${safeSections.reduce((count, section) => count + section.groups.length, 0)})`}>
          {portGroupClusters(safeSections.flatMap((section) => section.groups), "safe").map((cluster) => (
            <PortClusterMenuItem key={cluster.id} cluster={cluster} />
          ))}
        </MenuBarExtra.Submenu>
      ) : null}
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

function isSafeToIgnoreSection(section: { id: string }) {
  return section.id === "os-apple" || section.id === "system";
}

function PortClusterMenuItem(props: { cluster: PortGroupCluster }) {
  const { cluster } = props;
  if (cluster.groups.length === 1 && cluster.groups[0]) {
    return <PortMenuItem group={cluster.groups[0]} />;
  }

  const ports = cluster.groups.map((group) => group.port).join(", ");
  return (
    <Fragment>
      <MenuBarExtra.Item title={truncate(cluster.title, 30)} subtitle={truncate(`${cluster.groups.length} ports · ${ports}`, 30)} />
      {cluster.groups.map((group) => (
        <PortMenuItem key={group.id} group={group} />
      ))}
      <MenuBarExtra.Submenu title={truncate(`${cluster.title} Actions`, 30)}>
        <MenuBarExtra.Item title="Copy Ports" icon={Icon.Clipboard} onAction={() => Clipboard.copy(ports)} />
        <MenuBarExtra.Item
          title="Open Port List"
          icon={Icon.List}
          onAction={() => launchCommand({ name: "list-ports", type: LaunchType.UserInitiated })}
        />
      </MenuBarExtra.Submenu>
    </Fragment>
  );
}

function PortMenuItem(props: { group: ListeningPortGroup }) {
  const { group } = props;
  const title = truncate(`${group.port} • ${portGroupTitle(group)}`, 30);

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
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = "Failed to kill port";
      toast.message = error instanceof Error ? error.message : String(error);
    }
  }

  return (
    <MenuBarExtra.Submenu title={title}>
      <MenuBarExtra.Item title={truncate(portGroupTitle(group), 30)} />
      <MenuBarExtra.Item title={truncate(group.reason, 30)} />
      {group.bindings.map((binding) => (
        <MenuBarExtra.Item
          key={`${binding.protocol}-${binding.host}-${binding.port}-${binding.ownerPid ?? "owner"}`}
          title={truncate(bindingTitle(binding), 30)}
        />
      ))}
      {group.commonPort ? <MenuBarExtra.Item title={truncate(group.commonPort.name, 30)} /> : null}
      <MenuBarExtra.Separator />
      <MenuBarExtra.Item title={group.bindings.length === 1 ? "Copy Binding" : "Copy Bindings"} icon={Icon.Clipboard} onAction={() => Clipboard.copy(portGroupBindings(group))} />
      {canKillGroup(group) ? (
        <MenuBarExtra.Item title="Kill Port" icon={Icon.XMarkCircle} onAction={killSelected} />
      ) : null}
    </MenuBarExtra.Submenu>
  );
}

function bindingTitle(binding: ListeningPortGroup["bindings"][number]) {
  const owner = binding.ownerName && binding.ownerPid
    ? ` · ${binding.ownerName} (PID ${binding.ownerPid})`
    : "";
  return `${binding.label}${owner}`;
}

function truncate(value: string, maxLength: number) {
  if (value.length <= maxLength) {
    return value;
  }
  return `${value.slice(0, maxLength - 1)}…`;
}
