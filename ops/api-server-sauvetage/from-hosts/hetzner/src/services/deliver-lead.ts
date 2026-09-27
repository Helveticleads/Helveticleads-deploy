import { sendLeadEmail, type LeadData } from "@workspace/lead-core";
import { logger } from "../lib/logger";

export type DeliveryResult = {
  delivered: boolean;
  channels: string[];
  error?: string;
  lead_id?: string;
};

function getEnv(name: string, fallback?: string): string | undefined {
  const value = process.env[name]?.trim();
  if (value) return value;
  return fallback;
}

async function sendViaWebhook(lead: LeadData): Promise<boolean> {
  const url = getEnv("CRM_WEBHOOK_URL");
  if (!url) return false;

  const secret = getEnv("CRM_WEBHOOK_SECRET");
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (secret) {
    headers["X-Webhook-Secret"] = secret;
  }

  const response = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify({
      site: lead.source_site,
      receivedAt: lead.created_at,
      lead,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    logger.error({ status: response.status, body: body.slice(0, 500) }, "CRM webhook error");
    return false;
  }

  return true;
}

const leadLogger = {
  info: (obj: Record<string, unknown>, msg: string) => logger.info(obj, msg),
  warn: (obj: Record<string, unknown>, msg: string) => logger.warn(obj, msg),
  error: (obj: Record<string, unknown>, msg: string) => logger.error(obj, msg),
};

export async function deliverLead(
  lead: LeadData,
  ctx?: { host?: string },
): Promise<DeliveryResult> {
  const hasResend = Boolean(getEnv("RESEND_API_KEY"));
  const hasWebhook = Boolean(getEnv("CRM_WEBHOOK_URL"));

  if (!hasResend && !hasWebhook) {
    logger.warn("Lead received but no delivery channel configured (RESEND_API_KEY / CRM_WEBHOOK_URL)");
    return {
      delivered: false,
      channels: [],
      error:
        "Réception des demandes non configurée. Définir RESEND_API_KEY ou CRM_WEBHOOK_URL sur le serveur.",
    };
  }

  const channels: string[] = [];

  if (hasResend) {
    const result = await sendLeadEmail(lead, leadLogger, { requestHost: ctx?.host });
    if (result.success) channels.push("email");
  }

  if (hasWebhook) {
    const ok = await sendViaWebhook(lead);
    if (ok) channels.push("webhook");
  }

  if (channels.length === 0) {
    return {
      delivered: false,
      channels: [],
      error: "Échec de l'envoi. Vérifiez la configuration serveur (Resend / webhook CRM).",
      lead_id: lead.lead_id,
    };
  }

  logger.info({ channels, form_type: lead.form_type, lead_id: lead.lead_id }, "Lead delivered");
  return { delivered: true, channels, lead_id: lead.lead_id };
}
