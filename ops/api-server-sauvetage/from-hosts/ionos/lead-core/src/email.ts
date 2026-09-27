import { resolveRecipients } from "./recipients";
import { buildSubject } from "./subject";
import { buildHtml, buildText } from "./template";
import type {
  LeadCoreLogger,
  LeadData,
  SendLeadEmailOptions,
  SendLeadEmailResult,
} from "./types";

export { LEAD_EMAIL_BRAND_COLOR, LEAD_EMAIL_LOGO_URL } from "./template";
export { buildSubject } from "./subject";
export { buildHtml, buildText } from "./template";

function siteLabel(lead: LeadData): string {
  try {
    return new URL(lead.source_site).hostname.replace(/^www\./, "");
  } catch {
    return lead.source_site.replace(/^https?:\/\//, "").replace(/\/$/, "");
  }
}

function hostForRecipients(lead: LeadData, requestHost?: string): string {
  const fromHeader = requestHost?.trim();
  if (fromHeader) return fromHeader;
  return siteLabel(lead);
}

export async function sendLeadEmail(
  lead: LeadData,
  log?: LeadCoreLogger,
  options?: SendLeadEmailOptions,
): Promise<SendLeadEmailResult> {
  log?.info(
    { name: lead.name, phone: lead.phone, site: lead.source_site, form: lead.form_type, lead_id: lead.lead_id },
    "Lead received",
  );

  const apiKey = process.env["RESEND_API_KEY"];
  if (!apiKey) {
    log?.warn(
      { lead_id: lead.lead_id, site: lead.source_site },
      "RESEND_API_KEY not set — email not sent",
    );
    return { success: false, error: "RESEND_API_KEY_MISSING" };
  }

  const centralEmail = (
    process.env["LEAD_CENTRAL_EMAIL"] ?? process.env["CONTACT_EMAIL"]
  )?.trim();
  const { to: toEmail, bcc } = resolveRecipients(
    hostForRecipients(lead, options?.requestHost),
    lead.site_language,
    centralEmail,
  );

  if (!toEmail) {
    log?.warn({ lead_id: lead.lead_id, host: options?.requestHost }, "No recipient resolved — email not sent");
    return { success: false, error: "NO_RECIPIENT" };
  }

  const fromEmail =
    process.env["FROM_EMAIL"];

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: fromEmail,
        to: [toEmail],
        ...(bcc.length > 0 ? { bcc } : {}),
        ...(lead.email ? { reply_to: lead.email } : {}),
        subject: buildSubject(lead),
        html: buildHtml(lead),
        text: buildText(lead),
      }),
    });

    if (!res.ok) {
      const body = await res.text();
      log?.error({ status: res.status, body: body.slice(0, 500) }, "Resend API error");
      return { success: false, error: `resend_${res.status}` };
    }

    log?.info({ to: toEmail, bcc, lead_id: lead.lead_id }, "Lead email sent successfully");
    return { success: true };
  } catch (err) {
    log?.error({ err }, "Network error sending lead email");
    return { success: false, error: "network_error" };
  }
}
