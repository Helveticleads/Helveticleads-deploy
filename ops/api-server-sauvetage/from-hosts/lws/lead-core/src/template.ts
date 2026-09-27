import { isUrgentLead, siteLabel } from "./subject";
import type { LeadData } from "./types";

/** Dominant gold from Premium Helvetic Leads logo PNG (PIL sample on brand asset). */
export const LEAD_EMAIL_BRAND_COLOR = "#8B6E2A";

/**
 * Société — servi par le front CRM (Vite public/ → /brand/*).
 * Apex premiumhelveticleads.ch = page parking LWS (pas de static) ; override via LEAD_EMAIL_LOGO_URL.
 */
export const LEAD_EMAIL_LOGO_URL =
  (typeof process !== "undefined" && process.env["LEAD_EMAIL_LOGO_URL"]?.trim()) ||
  "https://crm.premiumhelveticleads.ch/brand/premium-helvetic-leads-logo.png";

/** Cache-buster pour clients mail / navigateur après remplacement de l'asset CRM. */
function logoEmailSrc(): string {
  const base = LEAD_EMAIL_LOGO_URL;
  return base.includes("?") ? `${base}&v=2` : `${base}?v=2`;
}

const FOOTER_CONTACT = (typeof process !== 'undefined' && process.env['LEAD_EMAIL_FOOTER_CONTACT']?.trim()) || '';

function row(label: string, value: string): string {
  return `<tr>
    <td style="padding:8px 14px;border:1px solid #e5e7eb;background:#f9fafb;font-weight:600;white-space:nowrap;font-size:13px;vertical-align:top;">${label}</td>
    <td style="padding:8px 14px;border:1px solid #e5e7eb;font-size:13px;vertical-align:top;">${value}</td>
  </tr>`;
}

function optionalRow(label: string, value: string | undefined): string {
  const v = value?.trim();
  if (!v) return "";
  return row(label, v);
}

function urgencyDisplay(lead: LeadData): string {
  if (!lead.urgency) return "";
  const urgencyLabels: Record<string, string> =
    lead.site_language === "fr"
      ? {
          dringend: "🔴 Urgent",
          urgent: "🔴 Urgent",
          "diese-woche": "Cette semaine",
          "naechste-wochen": "Prochaines semaines",
          "termin-absprechen": "À convenir",
          "ce-mois": "Ce mois",
          "non-urgent": "Pas urgent",
        }
      : {
          dringend: "🔴 Dringend",
          urgent: "🔴 Dringend",
          "diese-woche": "Diese Woche",
          "naechste-wochen": "In den nächsten Wochen",
          "termin-absprechen": "Termin gemeinsam festlegen",
        };
  return urgencyLabels[lead.urgency] ?? lead.urgency;
}

function callbackDisplay(lead: LeadData): string {
  const callbackSlotLabels: Record<string, string> =
    lead.site_language === "fr"
      ? {
          flexibel: "Flexible",
          vormittag: "Matin",
          nachmittag: "Après-midi",
          abend: "Soir",
          matin: "Matin",
          "apres-midi": "Après-midi",
          "fin-journee": "Fin de journée",
        }
      : {
          flexibel: "Flexibel",
          vormittag: "Vormittags",
          nachmittag: "Nachmittags",
          abend: "Abends",
        };

  if (lead.callback_requested === true) {
    return lead.callback_slot
      ? (callbackSlotLabels[lead.callback_slot] ?? lead.callback_slot)
      : lead.site_language === "fr"
        ? "Oui"
        : "Ja";
  }
  if (lead.callback_requested === false) {
    return lead.site_language === "fr" ? "Non" : "Nein";
  }
  return "";
}

/** Domaine sans TLD, tirets → espaces, casse inchangée (ex. helvetique-jardin.ch → helvetique jardin). */
function siteDisplayTitle(domain: string): string {
  const lastDot = domain.lastIndexOf(".");
  const host = lastDot > 0 ? domain.slice(0, lastDot) : domain;
  return host.replace(/-/g, " ");
}

function buildFooterHtml(lead: LeadData): string {
  const autoLine =
    lead.site_language === "fr"
      ? "Notification automatique — ne pas répondre à cet e-mail."
      : "Automatische Lead-Benachrichtigung — nicht auf diese E-Mail antworten.";

  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;">
    <tr>
      <td align="center" style="padding:16px 24px 8px;border-top:1px solid #e5e7eb;font-size:11px;line-height:1.55;color:#6b7280;text-align:center;">
        <p style="margin:0 0 6px;font-weight:600;color:#4b5563;text-align:center;">Premium Helvetic Leads — service de NABLA AI LTD</p>
        <p style="margin:0 0 4px;text-align:center;">NABLA AI LTD · Private limited company · Company no. 16553032</p>
        <p style="margin:0 0 4px;text-align:center;">71-75 Shelton Street, Covent Garden, London, United Kingdom, WC2H 9JQ</p>
        <p style="margin:0 0 4px;text-align:center;">Tél : ${(typeof process !== 'undefined' && process.env['LEAD_EMAIL_FOOTER_PHONE']?.trim()) || ''}</p>
        <p style="margin:0 0 10px;text-align:center;">Contact : <a href="mailto:${FOOTER_CONTACT}" style="color:#6b7280;text-decoration:underline;">${FOOTER_CONTACT}</a></p>
        <p style="margin:0;font-size:10px;color:#9ca3af;text-align:center;">${autoLine}</p>
      </td>
    </tr>
  </table>`;
}

function buildHeaderHtml(lead: LeadData): string {
  const domain = siteLabel(lead);
  const siteTitle = siteDisplayTitle(domain);
  const urgent = isUrgentLead(lead);
  const eyebrow =
    lead.site_language === "fr"
      ? urgent
        ? "LEAD URGENT REÇU"
        : "NOUVEAU LEAD REÇU"
      : urgent
        ? "DRINGENDER LEAD ERHALTEN"
        : "NEUER LEAD ERHALTEN";

  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;">
    <tr>
      <td align="center" style="background:#ffffff;padding:24px 24px 16px;text-align:center;">
        <img src="${logoEmailSrc()}" width="160" alt="Premium Helvetic Leads" style="display:block;border:0;outline:none;text-decoration:none;max-width:160px;width:160px;height:auto;margin:0 auto;" />
      </td>
    </tr>
    <tr>
      <td align="center" style="background:${LEAD_EMAIL_BRAND_COLOR};padding:20px 24px;text-align:center;">
        <p style="margin:0 0 8px;font-size:13px;font-weight:600;color:#ffffff;letter-spacing:0.04em;text-transform:uppercase;text-align:center;">${eyebrow}</p>
        <h1 style="margin:0 0 6px;font-size:24px;line-height:1.3;font-weight:700;color:#ffffff;text-align:center;">${siteTitle.toUpperCase()}</h1>
        <p style="margin:0;font-size:13px;line-height:1.4;color:#fff9eb;text-align:center;">${domain}</p>
      </td>
    </tr>
  </table>`;
}

export function buildHtml(lead: LeadData): string {
  let stepRows = "";
  if (lead.step_answers && Object.keys(lead.step_answers).length > 0) {
    stepRows = row(
      lead.site_language === "fr" ? "Réponses formulaire" : "Formular-Antworten",
      Object.entries(lead.step_answers)
        .map(([k, v]) => `${k}: ${v}`)
        .join(" | "),
    );
  }

  return `<!DOCTYPE html>
<html lang="${lead.site_language}">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f3f4f6;font-family:Arial,Helvetica,sans-serif;">
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#f3f4f6;border-collapse:collapse;">
  <tr>
    <td align="center" style="padding:24px 12px;">
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="620" style="max-width:620px;width:100%;background:#ffffff;border-collapse:collapse;border-radius:12px;overflow:hidden;">
        <tr><td>${buildHeaderHtml(lead)}</td></tr>
        <tr>
          <td>
            <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;">
              ${row(lead.site_language === "fr" ? "Nom" : "Name", lead.name)}
              ${row(lead.site_language === "fr" ? "Téléphone" : "Telefon", `<strong style="font-size:15px;">${lead.phone}</strong>`)}
              ${optionalRow("Email", lead.email)}
              ${optionalRow(lead.site_language === "fr" ? "Ville" : "Ort", lead.city)}
              ${optionalRow(lead.site_language === "fr" ? "Service" : "Leistung", lead.service)}
              ${optionalRow(lead.site_language === "fr" ? "Urgence" : "Dringlichkeit", urgencyDisplay(lead))}
              ${optionalRow(lead.site_language === "fr" ? "Rappel souhaité" : "Rückruf gewünscht", callbackDisplay(lead))}
              ${optionalRow("Message", lead.message)}
              ${stepRows}
              ${row("Lead-ID", lead.lead_id)}
              ${row(lead.site_language === "fr" ? "Page source" : "Quellseite", lead.source_page)}
              ${row(lead.site_language === "fr" ? "Date" : "Datum", lead.created_at)}
              ${optionalRow("IP", lead.ip_address)}
              ${optionalRow("User-Agent", lead.user_agent ? lead.user_agent.substring(0, 80) : undefined)}
            </table>
          </td>
        </tr>
        <tr><td>${buildFooterHtml(lead)}</td></tr>
      </table>
    </td>
  </tr>
</table>
</body>
</html>`;
}

function buildFooterText(lead: LeadData): string[] {
  const autoLine =
    lead.site_language === "fr"
      ? "Notification automatique — ne pas répondre à cet e-mail."
      : "Automatische Lead-Benachrichtigung — nicht auf diese E-Mail antworten.";

  return [
    "",
    "—",
    "Premium Helvetic Leads — service de NABLA AI LTD",
    "NABLA AI LTD · Private limited company · Company no. 16553032",
    "71-75 Shelton Street, Covent Garden, London, United Kingdom, WC2H 9JQ",
    'Tél : ' + ((typeof process !== 'undefined' && process.env['LEAD_EMAIL_FOOTER_PHONE']?.trim()) || ''),
    `Contact : ${FOOTER_CONTACT}`,
    autoLine,
  ];
}

export function buildText(lead: LeadData): string {
  const domain = siteLabel(lead);
  const urgent = isUrgentLead(lead);
  const headline =
    lead.site_language === "fr"
      ? urgent
        ? "Lead urgent reçu"
        : "Nouveau lead reçu"
      : urgent
        ? "Dringender Lead erhalten"
        : "Neuer Lead erhalten";

  const lines: string[] = [
    headline,
    domain,
    "",
    `${lead.site_language === "fr" ? "Nom" : "Name"} : ${lead.name}`,
    `${lead.site_language === "fr" ? "Téléphone" : "Telefon"} : ${lead.phone}`,
  ];

  if (lead.email) lines.push(`Email : ${lead.email}`);
  if (lead.city) lines.push(`${lead.site_language === "fr" ? "Ville" : "Ort"} : ${lead.city}`);
  if (lead.service) lines.push(`${lead.site_language === "fr" ? "Service" : "Leistung"} : ${lead.service}`);
  if (lead.urgency) lines.push(`${lead.site_language === "fr" ? "Urgence" : "Dringlichkeit"} : ${lead.urgency}`);
  if (lead.message) lines.push("", "Message :", lead.message);
  if (lead.step_answers && Object.keys(lead.step_answers).length > 0) {
    lines.push(
      "",
      lead.site_language === "fr" ? "Réponses formulaire :" : "Formular-Antworten :",
      ...Object.entries(lead.step_answers).map(([k, v]) => `  ${k}: ${v}`),
    );
  }

  lines.push(
    "",
    `Lead-ID : ${lead.lead_id}`,
    `${lead.site_language === "fr" ? "Page source" : "Quellseite"} : ${lead.source_page}`,
    `${lead.site_language === "fr" ? "Date" : "Datum"} : ${lead.created_at}`,
  );
  if (lead.ip_address) lines.push(`IP : ${lead.ip_address}`);
  if (lead.user_agent) lines.push(`User-Agent : ${lead.user_agent.substring(0, 80)}`);

  lines.push(...buildFooterText(lead));

  return lines.join("\n");
}
