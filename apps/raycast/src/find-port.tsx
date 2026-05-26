import { Clipboard, showHUD } from "@raycast/api";
import { findAvailablePort } from "./port-manager";

type Arguments = {
  port?: string;
};

export default async function Command(props: { arguments: Arguments }) {
  const requested = props.arguments.port ? Number(props.arguments.port) : undefined;
  const result = await findAvailablePort({ port: requested });
  await Clipboard.copy(String(result.port));
  await showHUD(`Available port ${result.port} copied`);
}
