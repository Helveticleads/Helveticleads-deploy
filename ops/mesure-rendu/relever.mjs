#!/usr/bin/env node
/**
 * Relève texte visible + nb d'éléments du corps — HTML servi (sans JS).
 * Usage: node relever.mjs <url|fichier.html> [label]
 */
import { readFileSync, existsSync } from "node:fs";
import { JSDOM } from "jsdom";

const target = process.argv[2];
const label = process.argv[3] || target;
if (!target) {
  console.error("usage: node relever.mjs <url|fichier.html> [label]");
  process.exit(2);
}

async function loadHtml(t) {
  if (existsSync(t) || t.startsWith("/") || t.endsWith(".html")) {
    return readFileSync(t, "utf8");
  }
  const res = await fetch(t, {
    headers: { "Cache-Control": "no-store", "User-Agent": "hl-mesure-rendu/1" },
    redirect: "follow",
  });
  const html = await res.text();
  return { html, status: res.status, finalUrl: res.url };
}

function measure(html) {
  const dom = new JSDOM(html);
  const doc = dom.window.document;
  for (const sel of ["script", "style", "noscript", "svg title"]) {
    doc.querySelectorAll(sel).forEach((n) => n.remove());
  }
  const body = doc.body;
  if (!body) {
    return { hasBody: false, textLen: 0, textSample: "", elements: 0, hasRoot: false, title: "" };
  }
  const text = (body.textContent || "").replace(/\s+/g, " ").trim();
  const elements = body.querySelectorAll("*").length;
  return {
    hasBody: true,
    textLen: text.length,
    textSample: text.slice(0, 80),
    elements,
    hasRoot: !!doc.querySelector("#root"),
    title: (doc.title || "").slice(0, 60),
  };
}

const loaded = await loadHtml(target);
const html = typeof loaded === "string" ? loaded : loaded.html;
const meta = typeof loaded === "string" ? { status: "file", finalUrl: target } : loaded;
const m = measure(html);
console.log(
  [
    label,
    `status=${meta.status}`,
    `textLen=${m.textLen}`,
    `elements=${m.elements}`,
    `hasRoot=${m.hasRoot}`,
    `title=${JSON.stringify(m.title)}`,
    `sample=${JSON.stringify(m.textSample)}`,
  ].join("\t")
);
