import { defineConfig } from "vitest/config";
import path from "node:path";

const target = process.env.CHAR_TARGET ?? "extract";
const host = process.env.CHAR_HOST; // optional filter

export default defineConfig({
  test: {
    environment: "node",
    include: ["characterization/**/*.test.ts"],
    testTimeout: 15000,
    env: {
      CHAR_TARGET: target,
      ...(host ? { CHAR_HOST: host } : {}),
      // quiet logger in tests
      LOG_LEVEL: "silent",
      NODE_ENV: "test",
    },
  },
  resolve: {
    alias: {
      // default for reconciled app imports; characterization overrides per-host via support
      "@workspace/lead-core": path.resolve(
        __dirname,
        target === "reconciled"
          ? "reconciled/lead-core/src/index.ts"
          : "from-hosts/hetzner/lead-core/src/index.ts",
      ),
    },
  },
});
