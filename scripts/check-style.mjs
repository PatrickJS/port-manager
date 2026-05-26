import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";

const roots = [".github", "docs", "packages", "scripts", "tests"];
const files = [];

async function collect(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== "node_modules" && entry.name !== "dist") {
        await collect(path);
      }
    } else {
      files.push(path);
    }
  }
}

for (const root of roots) {
  await collect(root);
}

const failures = [];
for (const file of files) {
  const text = await readFile(file, "utf8");
  if (!text.endsWith("\n")) {
    failures.push(`${file}: missing trailing newline`);
  }
  const lines = text.split("\n");
  lines.forEach((line, index) => {
    if (/[ \t]$/.test(line)) {
      failures.push(`${file}:${index + 1}: trailing whitespace`);
    }
  });
}

if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exit(1);
}

