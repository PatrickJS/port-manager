import { listListeningPorts } from "../port-manager";

export default async function tool() {
  return listListeningPorts();
}
