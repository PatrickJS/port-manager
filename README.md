# Port Manager

Port Manager is a small local developer utility for finding TCP ports, explaining what owns them, and giving agents a stable CLI/JSON surface.

The first implementation slice is Node-first:

- `@patrickjs/port-manager`: canonical dependency-light Node API.
- `port-manager`: CLI for humans and AI coding agents.
- compatibility packages for common port-finding APIs: `get-port`, `portfinder`, `detect-port`, and `get-port-please`.
- a native macOS development app that reads the same CLI JSON contract.

The Node package owns discovery, explanation, and cooperative reservations. The CLI serializes that API as stable JSON, the npm compatibility packages delegate to it, and the macOS app shells through `port-manager list --json` so it does not maintain a separate scanner.

## CLI

```sh
pnpm install
pnpm --filter @patrickjs/port-manager-cli exec port-manager find 3000 --json
pnpm --filter @patrickjs/port-manager-cli exec port-manager check 3000 --json
pnpm --filter @patrickjs/port-manager-cli exec port-manager explain 3000 --json
pnpm --filter @patrickjs/port-manager-cli exec port-manager list --json
pnpm --filter @patrickjs/port-manager-cli exec port-manager kill 3000 --json
```

## API

```js
import {
  checkPort,
  explainPort,
  findAvailablePort,
  reservePort,
} from "@patrickjs/port-manager";

const result = await findAvailablePort({ port: 3000 });
console.log(result.port);

const reservation = await reservePort({ port: 3000 });
try {
  console.log(`Reserved ${reservation.port}`);
} finally {
  await reservation.release();
}
```

`listListeningPorts()` returns both raw and grouped views:

- `ports[]` is the exact scanner output, one entry per host/protocol binding.
- `portGroups[]` folds those entries by numeric port for UI and AI display, with `reason`, `owners`, and `bindings` explaining why a row has multiple underlying bindings.

## Shared Local Instance

Port Manager uses a small file-backed lease registry so cooperating CLI, UI, and npm package calls can see the same soft reservations. By default the registry lives under the current user's temp directory; set `PORT_MANAGER_STATE_DIR` to point multiple processes at an explicit registry during tests or agent runs.

- `findAvailablePort({ reserve: true })` creates a short-lived cooperative lease.
- `reservePort()` binds the TCP port and refreshes its lease until `release()`.
- `listListeningPorts()` and `port-manager list --json` include active leases alongside real listening sockets.
- This is not a firewall or port guard; non-cooperating processes can still bind ports normally.

## macOS App

For local development:

```sh
pnpm run verify:macos
```

The generated app bundle stores the workspace path and `pnpm` path in `PortManagerConfig.json`, then calls the workspace CLI. That keeps the UI, CLI, and package adapters on the same core implementation while the standalone packaging shape is still being developed.

The app includes a native Settings window for startup behavior:

- enable "Start at login and keep running" to install a per-user LaunchAgent,
- choose "This app" for a released/current app bundle,
- choose "Local dist build" when running from this repo's `dist/PortManager.app`.

The LaunchAgent runs the bundled `PortManagerLauncher` helper, not a shell
wrapper, so macOS background-item notices point at Port Manager code instead of
`zsh`. Settings also shows the selected app path, helper path, `launchctl`
status, and launchd stdout/stderr log tails for debugging failed startup
targets.

For source builds, the same LaunchAgent can be managed from the terminal:

```sh
script/install_launch_agent.sh
script/uninstall_launch_agent.sh
```

## Raycast

The local Raycast extension lives in `apps/raycast`. It provides:

- a list command for inspecting ports and killing a selected process,
- a menu bar command for a quick grouped open-port list,
- AI tools for listing, explaining, finding, and killing ports through Raycast AI.

From `apps/raycast`, run `npm install` and `npm run dev` to import it into Raycast during development. Use `npm run build` when you want Raycast to keep the local extension without the dev server.

## Replacement Strategy

This repo does not globally replace npm packages. Projects can opt into compatibility adapters through package-manager aliases or overrides once they want Port Manager behavior in place of a common package contract.
