#!/usr/bin/env node
/**
 * Effet « la page a rendu » — pas un nom d'implémentation (#root, SITE_CONFIG).
 *
 * Critère (releve 2026-10-19, ET pas OU) :
 *   textLen ≥ 200  et  elements ≥ 20
 * sur le corps, scripts/styles exclus.
 *
 * Usage:
 *   node mesurer-rendu.mjs <fichier.html>
 *   node mesurer-rendu.mjs --html-file <fichier.html>
 * Exit 0 = OK, 1 = FAIL, 2 = usage.
 */
import { readFileSync, existsSync } from "node:fs";

const MIN_TEXT = 200;
const MIN_ELEMENTS = 20;

function usage() {
  console.error("usage: node mesurer-rendu.mjs <fichier.html>");
  process.exit(2);
}

const file = process.argv[2] === "--html-file" ? process.argv[3] : process.argv[2];
if (!file || !existsSync(file)) usage();

const html = readFileSync(file, "utf8");

/** Parse minimal sans dépendance : retire script/style, compte balises corps, texte. */
function measure(raw) {
  let s = String(raw);
  s = s.replace(/<script\b[\s\S]*?<\/script>/gi, "");
  s = s.replace(/<style\b[\s\S]*?<\/style>/gi, "");
  s = s.replace(/<noscript\b[\s\S]*?<\/noscript>/gi, "");
  const bodyMatch = s.match(/<body\b[^>]*>([\s\S]*)<\/body>/i);
  const body = bodyMatch ? bodyMatch[1] : s;
  const elements = (body.match(/<[a-zA-Z][^>]*>/g) || []).length;
  const text = body
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/\s+/g, " ")
    .trim();
  return { textLen: text.length, elements, sample: text.slice(0, 80) };
}

const m = measure(html);
const ok = m.textLen >= MIN_TEXT && m.elements >= MIN_ELEMENTS;
console.log(
  `MESURE_RENDU textLen=${m.textLen} elements=${m.elements} seuil=${MIN_TEXT}/${MIN_ELEMENTS} verdict=${ok ? "OK" : "FAIL"} sample=${JSON.stringify(m.sample)}`
);
process.exit(ok ? 0 : 1);
