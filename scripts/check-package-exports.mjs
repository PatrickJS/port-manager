import { access, readFile } from "node:fs/promises";
import { join } from "node:path";

const packageDirs = [
  "packages/core",
  "packages/cli",
  "packages/compat-get-port",
  "packages/compat-portfinder",
  "packages/compat-detect-port",
  "packages/compat-get-port-please",
];

for (const dir of packageDirs) {
  const manifestPath = join(dir, "package.json");
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  if (!manifest.name || !manifest.version) {
    throw new Error(`${manifestPath} must include name and version`);
  }
  if (manifest.bin) {
    for (const target of Object.values(manifest.bin)) {
      await access(join(dir, target));
    }
  }
  if (manifest.exports) {
    await checkExportTarget(dir, manifest.exports);
  } else if (manifest.main) {
    await access(join(dir, manifest.main));
  }
}

async function checkExportTarget(dir, target) {
  if (typeof target === "string") {
    await access(join(dir, target));
    return;
  }
  for (const value of Object.values(target)) {
    if (typeof value === "string") {
      await access(join(dir, value));
    } else if (value && typeof value === "object") {
      await checkExportTarget(dir, value);
    }
  }
}

