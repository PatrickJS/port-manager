import { readdir } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { join } from "node:path";

const roots = ["packages", "scripts", "tests"];
const files = [];

async function collect(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== "node_modules" && entry.name !== "dist") {
        await collect(path);
      }
    } else if (/\.(mjs|js|cjs)$/.test(entry.name)) {
      files.push(path);
    }
  }
}

for (const root of roots) {
  await collect(root);
}

for (const file of files) {
  const result = spawnSync(process.execPath, ["--check", file], { stdio: "inherit" });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

