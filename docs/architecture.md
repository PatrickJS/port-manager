# Architecture

Port Manager has three layers:

1. A canonical local port API in `@patrickjs/port-manager`.
2. A JSON-first CLI that exposes the canonical API to humans, agents, and the native UI.
3. Thin compatibility adapters that expose familiar package contracts while delegating to the canonical API.

The canonical API avoids runtime dependencies and uses Node built-ins:

- `node:net` for TCP availability, reservation, and wait checks.
- `node:child_process` for macOS ownership inspection through `lsof` and `ps`.
- a file-backed local lease registry for cooperative reservations shared by CLI, UI, and npm package calls.

The CLI is intentionally JSON-first for agents. Every command supports `--json`, and JSON payloads include a `schemaVersion` field so future changes can be versioned.

## Shared Contract

The macOS app does not run a separate native scanner. In development it invokes:

```sh
pnpm --filter @patrickjs/port-manager-cli exec port-manager list --json
```

That keeps ownership detection, common-port labels, reservation leases, and schema versions in the Node core/CLI contract. The npm adapters also import `@patrickjs/port-manager`, so replacement packages and the UI observe the same cooperative reservation registry.

The registry is controlled by `PORT_MANAGER_STATE_DIR` when an explicit shared location is needed. Without that environment variable it uses a per-user temp directory. These leases coordinate cooperating Port Manager clients only; they are not a security boundary and do not prevent unrelated software from binding ports.

## Naming

The GitHub repository is `port-manager` because that is the working product name. The publishable npm package is scoped as `@patrickjs/port-manager` because the unscoped `port-manager` name is already occupied.

## Compatibility Packages

The adapter packages are deliberately thin:

- `@patrickjs/port-manager-compat-get-port`
- `@patrickjs/port-manager-compat-portfinder`
- `@patrickjs/port-manager-compat-detect-port`
- `@patrickjs/port-manager-compat-get-port-please`

They are meant for controlled opt-in replacement through package aliases/overrides, not global mutation of an environment.
