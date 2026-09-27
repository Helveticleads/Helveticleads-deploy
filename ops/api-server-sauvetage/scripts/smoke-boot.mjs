#!/usr/bin/env node
/**
 * Local smoke: boot bundled dist with HOST_PROFILE, hit /api/health, exit.
 * Does not send mail or touch CRM.
 */
import { spawn } from "node:child_process";
import { setTimeout as sleep } from "node:timers/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dist = join(root, "dist/index.mjs");
const port = String(18547 + Math.floor(Math.random() * 100));
const profile = process.env.HOST_PROFILE || "ionos";

const child = spawn(
  process.execPath,
  ["--enable-source-maps", dist],
  {
    env: {
      ...process.env,
      PORT: port,
      HOST_PROFILE: profile,
      LOG_LEVEL: "info",
      NODE_ENV: "test",
    },
    stdio: ["ignore", "pipe", "pipe"],
  },
);

let out = "";
child.stdout.on("data", (b) => {
  out += b.toString();
});
child.stderr.on("data", (b) => {
  out += b.toString();
});

let ok = false;
try {
  for (let i = 0; i < 40; i++) {
    await sleep(100);
    try {
      const res = await fetch(`http://127.0.0.1:${port}/api/health`);
      if (res.ok) {
        const body = await res.json();
        if (body?.status === "ok") {
          ok = true;
          break;
        }
      }
    } catch {
      /* not up yet */
    }
  }
} finally {
  child.kill("SIGTERM");
  await sleep(200);
  if (!child.killed) child.kill("SIGKILL");
}

if (!ok) {
  console.error("smoke-boot FAILED\n", out.slice(-2000));
  process.exit(1);
}
if (!out.includes(profile) && !out.includes("Server listening")) {
  // logger may be silent; health alone is enough
}
console.log(`smoke-boot OK hostProfile=${profile} port=${port}`);
