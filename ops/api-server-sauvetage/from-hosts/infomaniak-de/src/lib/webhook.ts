import { createHmac } from "node:crypto";
import { logger } from "./logger";
import type { LeadData } from "@workspace/lead-core";

const MAX_RETRIES = 2;

function buildWebhookPayload(lead: LeadData) {
  return {
    lead_id: lead.lead_id,
    site: lead.source_site,
    langue: lead.site_language,
    page_origine: lead.source_page,
    type_formulaire: lead.form_type,
    prenom: lead.name,
    email: lead.email ?? null,
    telephone: lead.phone,
    ville: lead.city ?? null,
    service: lead.service ?? null,
    urgence: lead.urgency ?? null,
    rappel_souhaite: lead.callback_requested ?? false,
    rappel_creneau: lead.callback_slot ?? null,
    message: lead.message ?? null,
    reponses_formulaire: lead.step_answers ?? null,
    date_soumission: lead.created_at,
  };
}

function signPayload(body: string, secret: string): string {
  return createHmac("sha256", secret).update(body).digest("hex");
}

async function postOnce(url: string, body: string, signature: string | null): Promise<boolean> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (signature) {
    headers["X-Lead-Signature"] = signature;
  }

  const res = await fetch(url, { method: "POST", headers, body });
  return res.ok;
}

export async function sendLeadWebhook(lead: LeadData): Promise<{ sent: boolean; error?: string }> {
  const url = process.env["LEADS_WEBHOOK_URL"];
  if (!url) {
    return { sent: false, error: "WEBHOOK_URL_MISSING" };
  }

  const secret = process.env["LEADS_WEBHOOK_SECRET"];
  const body = JSON.stringify(buildWebhookPayload(lead));
  const signature = secret ? signPayload(body, secret) : null;

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    try {
      const ok = await postOnce(url, body, signature);
      if (ok) {
        logger.info({ lead_id: lead.lead_id, site: lead.source_site }, "Lead webhook sent");
        return { sent: true };
      }
      logger.warn({ attempt, lead_id: lead.lead_id }, "Lead webhook HTTP error");
    } catch (err) {
      logger.error({ err, attempt, lead_id: lead.lead_id }, "Lead webhook network error");
    }
    if (attempt < MAX_RETRIES) {
      await new Promise((r) => setTimeout(r, 500 * (attempt + 1)));
    }
  }

  return { sent: false, error: "WEBHOOK_FAILED" };
}
