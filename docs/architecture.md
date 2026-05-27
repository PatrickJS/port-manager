# Architecture

Port Manager has four layers:

1. A canonical local port API in `@patrickjs/port-manager`.
2. A JSON-first CLI that exposes the canonical API to humans, agents, and the native UI.
3. Native/local clients, including the macOS app and Raycast extension, that delegate to the same core or CLI contract.
4. Thin compatibility adapters that expose familiar package contracts while delegating to the canonical API.

The canonical API avoids runtime dependencies and uses Node built-ins:

- `node:net` for TCP availability, reservation, and wait checks.
- `node:child_process` for macOS ownership inspection through `lsof` and `ps`.
- a file-backed local lease registry for cooperative reservations shared by CLI, UI, and npm package calls.

The CLI is intentionally JSON-first for agents. Every command supports `--json`, and JSON payloads include a `schemaVersion` field so future changes can be versioned.

`listListeningPorts()` keeps two views in the same payload. `ports[]` is the raw scanner surface, so agents can inspect exact host/protocol bindings. `portGroups[]` is the display surface, folding raw entries by numeric port and carrying `reason`, `owners`, and `bindings` fields so UI rows can stay de-duplicated without hiding the underlying explanation.

## Shared Contract

The macOS app does not run a separate native scanner. In development it invokes:

```sh
pnpm --filter @patrickjs/port-manager-cli exec port-manager list --json
```

That keeps ownership detection, common-port labels, reservation leases, and schema versions in the Node core/CLI contract. The npm adapters also import `@patrickjs/port-manager`, so replacement packages and the UI observe the same cooperative reservation registry.

Startup behavior is owned by a per-user LaunchAgent named `dev.patrickjs.PortManager`. The native Settings window can install or remove it and choose whether it points at the current app bundle ("This app", for released builds) or the repository's `dist/PortManager.app` ("Local dist build", for source development). The LaunchAgent uses `RunAtLoad` and `KeepAlive` so the menu-bar app starts at login and relaunches after exit. It runs the bundled `PortManagerLauncher` helper rather than a shell wrapper, and Settings exposes the selected app path, helper path, `launchctl` status, and launchd stdout/stderr log tails when a target fails to start.

The registry is controlled by `PORT_MANAGER_STATE_DIR` when an explicit shared location is needed. Without that environment variable it uses a per-user temp directory. These leases coordinate cooperating Port Manager clients only; they are not a security boundary and do not prevent unrelated software from binding ports.

Raycast support lives under `apps/raycast`. Its visible commands and AI tools import `@patrickjs/port-manager`, so Raycast does not get a forked scanner or a separate kill implementation.

## Naming

The GitHub repository is `port-manager` because that is the working product name. The publishable npm package is scoped as `@patrickjs/port-manager` because the unscoped `port-manager` name is already occupied.

## Compatibility Packages

The adapter packages are deliberately thin:

- `@patrickjs/port-manager-compat-get-port`
- `@patrickjs/port-manager-compat-portfinder`
- `@patrickjs/port-manager-compat-detect-port`
- `@patrickjs/port-manager-compat-get-port-please`

They are meant for controlled opt-in replacement through package aliases/overrides, not global mutation of an environment.
