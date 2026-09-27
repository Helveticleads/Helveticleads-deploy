import type { SiteLanguage } from "./types";

export type ResolvedRecipients = { to: string; bcc: string[] };

function normalizeHost(host: string): string {
  return host.toLowerCase().replace(/^www\./, "").replace(/:\d+$/, "").trim();
}

function isValidHost(host: string): boolean {
  return host.includes(".");
}

/**
 * Resolve per-site inbox + optional central BCC (deduped when site is the central box).
 */
export function resolveRecipients(
  host: string,
  lang: SiteLanguage,
  centralEmail?: string,
): ResolvedRecipients {
  const central = (centralEmail ?? "").trim();
  const prefix = lang === "de" ? "kontakt" : "contact";
  const h = normalizeHost(host);

  if (!h || !isValidHost(h)) {
    return { to: central, bcc: [] };
  }

  const to = `${prefix}@${h}`;
  const bcc =
    central && central.toLowerCase() !== to.toLowerCase() ? [central] : [];

  return { to, bcc };
}
