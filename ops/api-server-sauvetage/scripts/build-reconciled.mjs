#!/usr/bin/env node
/**
 * Bundle reconciled/ → dist/index.mjs (+ .map), same shape as production
 * ExecStart: node --enable-source-maps dist/index.mjs
 */
import * as esbuild from "esbuild";
import { mkdirSync, rmSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const outdir = join(root, "dist");
const outfile = join(outdir, "index.mjs");
const entry = join(root, "reconciled/src/index.ts");
const leadCore = join(root, "reconciled/lead-core/src/index.ts");

if (existsSync(outdir)) {
  rmSync(outdir, { recursive: true, force: true });
}
mkdirSync(outdir, { recursive: true });

// Same ESM↔CJS shim as the Jul 28 production artifact (createRequire banner).
const banner = `import { createRequire as __bannerCrReq } from 'node:module';
import __bannerPath from 'node:path';
import __bannerUrl from 'node:url';

globalThis.require = __bannerCrReq(import.meta.url);
globalThis.__filename = __bannerUrl.fileURLToPath(import.meta.url);
globalThis.__dirname = __bannerPath.dirname(globalThis.__filename);
`;

await esbuild.build({
  entryPoints: [entry],
  outfile,
  bundle: true,
  platform: "node",
  target: "node20",
  format: "esm",
  sourcemap: true,
  banner: { js: banner },
  // Bundle deps like the Jul 28 prod artifact (no node_modules on the VPS).
  packages: "bundle",
  alias: {
    "@workspace/lead-core": leadCore,
  },
  logLevel: "info",
});

console.log(`built ${outfile}`);
