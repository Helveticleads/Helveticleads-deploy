#!/usr/bin/env node
/**
 * Refuse un fichier qui contient un conflit Git complet :
 * les trois marqueurs <<<<<<< / ======= / >>>>>>> en début de ligne.
 *
 * Un titre setext Markdown (======= seul) passe.
 * Échappatoire documentation : une ligne contenant uniquement
 *   garde-marqueurs-ignore
 * (éventuellement dans un commentaire) saute le fichier entier.
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

const hits = [];
let ignored = 0;
for (const file of walk(ROOT)) {
  const text = readFileSync(file, "utf8");
  if (IGNORE_LINE.test(text)) {
    ignored += 1;
    continue;
  }
  if (HAS_LT.test(text) && HAS_EQ.test(text) && HAS_GT.test(text)) {
    hits.push(relative(ROOT === "." ? process.cwd() : ROOT, file) || file);
  }
}
if (hits.length) {
  console.error(`[marqueurs-conflit] ${hits.length} fichier(s)`);
  for (const f of hits) console.error(`  ${f}`);
  process.exit(1);
}
console.log(`[marqueurs-conflit] 0 dans ${ROOT}` + (ignored ? ` (ignorés=${ignored})` : ""));
