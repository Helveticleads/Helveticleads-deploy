#!/usr/bin/env node
/**
 * Refuse un fichier qui contient un conflit Git complet :
 * les trois marqueurs <<<<<<< / ======= / >>>>>>> en début de ligne.
 *
 * Un titre setext Markdown (======= seul) passe.
 * Échappatoire documentation : une ligne contenant uniquement
 *   garde-marqueurs-ignore
 * (éventuellement dans un commentaire) saute le fichier entier.
 * Chaque saut est annoncé (GATE_SKIP) — ce n’est pas GATE_OK.
 *
 * Usage: node guard-marqueurs-conflit.mjs [racine]
 */
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = process.argv[2] || ".";
const IGNORE_LINE = /^\s*(?:\/\/|#|\/\*|\*|<!--)?\s*garde-marqueurs-ignore\s*(?:\*\/|-->)?\s*$/m;
const HAS_LT = /^<<<<<<</m;
const HAS_EQ = /^=======/m;
const HAS_GT = /^>>>>>>>/m;
const SKIP_DIR = new Set([
  "node_modules",
  ".git",
  "dist",
  "attached_assets",
  "_verrou_hote",
  "_garde_marqueurs",
  ".next",
  "coverage",
]);

function walk(dir, acc = []) {
  if (!existsSync(dir)) return acc;
  for (const name of readdirSync(dir)) {
    if (SKIP_DIR.has(name)) continue;
    const p = join(dir, name);
    let st;
    try {
      st = statSync(p);
    } catch {
      continue;
    }
    if (st.isDirectory()) walk(p, acc);
    else if (/\.(json|mjs|js|cjs|ts|tsx|astro|html|css|md|mdx|yml|yaml|toml|svg|txt)$/i.test(name))
      acc.push(p);
  }
  return acc;
}

function relOf(file) {
  const r = relative(ROOT === "." ? process.cwd() : ROOT, file);
  return r || file;
}

const hits = [];
const skipped = [];
for (const file of walk(ROOT)) {
  const text = readFileSync(file, "utf8");
  if (IGNORE_LINE.test(text)) {
    skipped.push(relOf(file));
    continue;
  }
  if (HAS_LT.test(text) && HAS_EQ.test(text) && HAS_GT.test(text)) {
    hits.push(relOf(file));
  }
}

for (const f of skipped) {
  console.log(`GATE_SKIP marqueurs-conflit:${f}`);
}
if (skipped.length) {
  console.log(`GATE_SKIP marqueurs-conflit:count=${skipped.length}`);
}

if (hits.length) {
  console.error(`[marqueurs-conflit] ${hits.length} fichier(s)`);
  for (const f of hits) console.error(`  ${f}`);
  process.exit(1);
}
if (skipped.length) {
  console.log(`[marqueurs-conflit] 0 conflit dans ${ROOT} (ignorés=${skipped.length} — voir GATE_SKIP)`);
} else {
  console.log(`[marqueurs-conflit] 0 dans ${ROOT}`);
}
