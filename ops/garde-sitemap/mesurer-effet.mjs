#!/usr/bin/env node
/**
 * Mesure l'effet d'un build : un sitemap existe, non vide, et ses URL
 * correspondent aux pages HTML prérendues indexables.
 * Aucun nom de script n'est consulté.
 *
 * Usage: node mesurer-effet.mjs <dir-dist-public>
 * Exit 0 = OK, 1 = FAIL (effet manquant ou divergent).
 */
import { readFileSync, existsSync, statSync, readdirSync } from "node:fs";
import { join, relative, sep } from "node:path";

const root = process.argv[2];
if (!root) {
  console.error("usage: node mesurer-effet.mjs <dir-dist-public>");
  process.exit(2);
}

function npath(p) {
  if (!p) return "/";
  let s = String(p);
  if (!s.startsWith("/")) s = `/${s}`;
  if (s !== "/" && s.endsWith("/")) s = s.replace(/\/+$/, "");
  return s || "/";
}

function locToPath(loc) {
  const s = String(loc || "").trim();
  let path;
  try {
    path = new URL(s).pathname;
  } catch {
    const withScheme = s.match(/^https?:\/\/[^/]+(\/.*)$/i);
    if (withScheme) path = withScheme[1] || "/";
    else {
      const hostPath = s.match(/^[^/\s]+(\/.*)$/);
      path = hostPath ? hostPath[1] || "/" : s.startsWith("/") ? s : `/${s}`;
    }
  }
  try {
    path = decodeURIComponent(path);
  } catch {
    /* keep */
  }
  return npath(path.normalize("NFC"));
}

function hasNoindex(html) {
  const m = html.match(/<meta[^>]+name=["']robots["'][^>]*>/i);
  if (!m) return false;
  const c = m[0].match(/content=["']([^"']+)["']/i);
  const r = (c ? c[1] : "").toLowerCase();
  return r.includes("noindex") || r.includes("none");
}

function walkHtml(dir, base = dir, out = []) {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const ent of entries) {
    const full = join(dir, ent.name);
    if (ent.isDirectory()) {
      if (ent.name === "assets" || ent.name === "node_modules") continue;
      walkHtml(full, base, out);
      continue;
    }
    if (!ent.isFile() || !ent.name.endsWith(".html")) continue;
    if (ent.name === "404.html") continue;
    out.push(full);
  }
  return out;
}

function fileToRoute(file, base) {
  const rel = relative(base, file).split(sep).join("/");
  if (rel === "index.html") return "/";
  if (rel.endsWith("/index.html")) return npath(`/${rel.slice(0, -"/index.html".length)}`);
  if (rel.endsWith(".html")) return npath(`/${rel.slice(0, -".html".length)}`);
  return null;
}

const smFile = join(root, "sitemap.xml");
if (!existsSync(smFile) || !statSync(smFile).isFile()) {
  console.error(`GATE_FAIL sitemap:absent path=${smFile}`);
  process.exit(1);
}

const xml = readFileSync(smFile, "utf8");
const locs = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => locToPath(m[1]));
const sm = new Set(locs);

if (sm.size === 0) {
  console.error(`GATE_FAIL sitemap:vide path=${smFile}`);
  process.exit(1);
}

const prerendered = new Set();
const noindexed = new Set();
for (const file of walkHtml(root)) {
  if (!statSync(file).isFile() || statSync(file).size === 0) continue;
  const route = fileToRoute(file, root);
  if (!route) continue;
  const html = readFileSync(file, "utf8");
  prerendered.add(route);
  if (hasNoindex(html)) noindexed.add(route);
}
const expected = new Set([...prerendered].filter((r) => !noindexed.has(r)));

if (expected.size === 0) {
  console.error(`GATE_FAIL sitemap:prerendu_vide pages_html=0`);
  process.exit(1);
}

const onlySm = [...sm].filter((r) => !expected.has(r)).sort();
const onlyExp = [...expected].filter((r) => !sm.has(r)).sort();

console.log(
  `[sitemap-effet] sitemap=${sm.size} prerendered=${prerendered.size} noindex=${noindexed.size} expected=${expected.size}`,
);
console.log(
  `[sitemap-effet] seulement_sitemap=${onlySm.length}${onlySm.length ? " " + onlySm.slice(0, 12).join(" ") : ""}`,
);
console.log(
  `[sitemap-effet] manquant_sitemap=${onlyExp.length}${onlyExp.length ? " " + onlyExp.slice(0, 12).join(" ") : ""}`,
);

if (onlySm.length || onlyExp.length) {
  console.error("GATE_FAIL sitemap:ecart_prerendu");
  process.exit(1);
}

console.log("GATE_OK sitemap_effet");
process.exit(0);
