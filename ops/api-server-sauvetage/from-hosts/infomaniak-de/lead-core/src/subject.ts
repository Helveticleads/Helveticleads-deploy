import type { LeadData } from "./types";

export function siteLabel(lead: LeadData): string {
  try {
    return new URL(lead.source_site).hostname.replace(/^www\./, "");
  } catch {
    return lead.source_site.replace(/^https?:\/\//, "").replace(/\/$/, "");
  }
}

/** Faux positif théorique : "nicht-dringend" contient "dringend" — non observé sur les fronts DE audités. */
function isUrgentLead(lead: LeadData): boolean {
  const u = (lead.urgency ?? "").toLowerCase();
  return ["urgent", "dringend", "sofort", "notfall", "heute"].some((k) => u.includes(k));
}

export function buildSubject(lead: LeadData): string {
  const label = siteLabel(lead);
  const urgent = isUrgentLead(lead);
  if (lead.site_language === "fr") {
    return urgent
      ? `[Lead URGENT] ${label} — ${lead.name}`
      : `[Nouveau lead] ${label} — ${lead.name}`;
  }
  return urgent
    ? `[Lead DRINGEND] ${label} — ${lead.name}`
    : `[Neuer Lead] ${label} — ${lead.name}`;
}

export { isUrgentLead };
