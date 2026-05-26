# Port Manager

Port Manager is a small local developer utility for finding TCP ports, explaining what owns them, and giving agents a stable CLI/JSON surface.

The first implementation slice is Node-first:

- `@patrickjs/port-manager`: canonical dependency-light Node API.
- `port-manager`: CLI for humans and AI coding agents.
- compatibility packages for common port-finding APIs: `get-port`, `portfinder`, `detect-port`, and `get-port-please`.

The native macOS menu bar app will build on the same ownership and explanation contract after the Node/CLI surface is stable.

## CLI

```sh
pnpm install
pnpm --filter @patrickjs/port-manager-cli exec port-manager find 3000 --json
pnpm --filter @patrickjs/port-manager-cli exec port-manager check 3000 --json
pnpm --filter @patrickjs/port-manager-cli exec port-manager explain 3000 --json
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

## Replacement Strategy

This repo does not globally replace npm packages. Projects can opt into compatibility adapters through package-manager aliases or overrides once they want Port Manager behavior in place of a common package contract.

