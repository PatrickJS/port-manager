import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { test } from "node:test";
import getPort, {
  clearLockedPorts,
  portNumbers,
} from "@patrickjs/port-manager-compat-get-port";
import { detect } from "@patrickjs/port-manager-compat-detect-port";
import getPortPlease from "@patrickjs/port-manager-compat-get-port-please";
import { reservePort } from "@patrickjs/port-manager";

const require = createRequire(import.meta.url);

test("get-port adapter returns a number and supports portNumbers", async () => {
  clearLockedPorts();
  const ports = [...portNumbers(44000, 44002)];
  assert.deepEqual(ports, [44000, 44001, 44002]);

  const port = await getPort({ port: ports });
  assert.equal(ports.includes(port), true);
});

test("portfinder adapter supports promise and callback styles", async () => {
  const portfinder = require("@patrickjs/port-manager-compat-portfinder");
  portfinder.setBasePort(45000);
  portfinder.setHighestPort(45100);

  const promisePort = await portfinder.getPortPromise();
  assert.equal(promisePort >= 45000, true);

  const callbackPort = await new Promise((resolve, reject) => {
    portfinder.getPort({ port: 45000, stopPort: 45100 }, (error, port) => {
      if (error) {
        reject(error);
      } else {
        resolve(port);
      }
    });
  });
  assert.equal(callbackPort >= 45000, true);
});

test("detect-port adapter returns requested port or next available port", async () => {
  const port = await detect(46000);
  assert.equal(port >= 46000, true);

  const reservation = await reservePort({ port });
  try {
    const next = await detect(port);
    assert.equal(next > port, true);
  } finally {
    await reservation.release();
  }
});

test("get-port-please adapter supports getPort and checkPort", async () => {
  const port = await getPortPlease.getPort({ portRange: [47000, 47010] });
  assert.equal(port >= 47000, true);
  assert.equal(port <= 47010, true);

  const available = await getPortPlease.checkPort(port);
  assert.equal(available, port);
});

