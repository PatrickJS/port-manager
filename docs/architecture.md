# Architecture

Port Manager has two layers:

1. A canonical local port API in `@patrickjs/port-manager`.
2. Thin compatibility adapters that expose familiar package contracts while delegating to the canonical API.

The canonical API avoids runtime dependencies and uses Node built-ins:

- `node:net` for TCP availability, reservation, and wait checks.
- `node:child_process` for macOS ownership inspection through `lsof` and `ps`.

The CLI is intentionally JSON-first for agents. Every command supports `--json`, and JSON payloads include a `schemaVersion` field so future changes can be versioned.

## Naming

The GitHub repository is `port-manager` because that is the working product name. The publishable npm package is scoped as `@patrickjs/port-manager` because the unscoped `port-manager` name is already occupied.

## Compatibility Packages

The adapter packages are deliberately thin:

- `@patrickjs/port-manager-compat-get-port`
- `@patrickjs/port-manager-compat-portfinder`
- `@patrickjs/port-manager-compat-detect-port`
- `@patrickjs/port-manager-compat-get-port-please`

They are meant for controlled opt-in replacement through package aliases/overrides, not global mutation of an environment.

