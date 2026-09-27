import { Router, type IRouter, type Request, type Response } from "express";
import { normalizeLegacyLeadBody, sendLeadEmail } from "@workspace/lead-core";
import { deliverLead } from "../services/deliver-lead";
import { sendLeadWebhook } from "../lib/webhook";
import { logger } from "../lib/logger";
import { getActiveHostProfile } from "../config/runtime";

const router: IRouter = Router();

function honeypotTriggered(body: unknown, fields: readonly string[]): boolean {
  if (!body || typeof body !== "object") return false;
  const raw = body as Record<string, unknown>;
  return fields.some((key) => {
    const value = raw[key];
    return typeof value === "string" && value.trim().length > 0;
  });
}

function contactEmail(site: string, lang: "fr" | "de"): string {
  if (process.env["CONTACT_EMAIL"]) return process.env["CONTACT_EMAIL"];
  const domain = site.replace(/^https?:\/\//, "").replace(/\/$/, "");
  return lang === "fr" ? `contact@${domain}` : `kontakt@${domain}`;
}

function errorMessage(
  lang: "fr" | "de",
  code: "resend_missing" | "generic",
  site: string,
): string {
  const email = contactEmail(site, lang);
  if (code === "resend_missing") {
    return lang === "fr"
      ? `Service email non configuré. Veuillez nous écrire à ${email}.`
      : `E-Mail-Dienst nicht konfiguriert. Bitte schreiben Sie uns an ${email}.`;
  }
  return lang === "fr"
    ? `Une erreur est survenue lors de l'envoi. Veuillez écrire à ${email} ou réessayer plus tard.`
    : `Beim Senden ist ein Fehler aufgetreten. Bitte schreiben Sie an ${email} oder versuchen Sie es später erneut.`;
}

const leadLogger = {
  info: (obj: Record<string, unknown>, msg: string) => logger.info(obj, msg),
  warn: (obj: Record<string, unknown>, msg: string) => logger.warn(obj, msg),
  error: (obj: Record<string, unknown>, msg: string) => logger.error(obj, msg),
};

router.post(["/leads", "/contact"], async (req: Request, res: Response) => {
  const profile = getActiveHostProfile();

  if (honeypotTriggered(req.body, profile.honeypotFields)) {
    logger.info({ host: req.get("host") }, "Honeypot triggered — silent accept");
    if (profile.responseStyle === "ikde") {
      res.json({ success: true });
      return;
    }
    return res.status(201).json({ ok: true, channels: [] });
  }

  const parsed = normalizeLegacyLeadBody(req.body, {
    host: req.get("host"),
    referer: typeof req.get("referer") === "string" ? req.get("referer") : undefined,
    ip_address:
      (req.headers["x-forwarded-for"] as string | undefined)?.split(",")[0]?.trim() ??
      req.socket.remoteAddress,
    user_agent: req.headers["user-agent"],
    default_site: process.env.SITE_DOMAIN ?? profile.defaultSite,
    default_language: profile.defaultLanguage,
  });

  if (!parsed.ok) {
    if (profile.responseStyle === "ikde") {
      res.status(400).json({
        success: false,
        message: parsed.error ?? "Ungültige Daten",
      });
      return;
    }
    return res.status(400).json({
      error: "Données invalides",
      details: parsed.fieldErrors,
    });
  }

  // IK-DE production path: fire-and-forget webhook, await email only
  if (!profile.delivery.usesDeliverLead) {
    const lead = parsed.data;
    void sendLeadWebhook(lead).catch((err) => {
      logger.error({ err, lead_id: lead.lead_id }, "Unhandled webhook error");
    });

    const result = await sendLeadEmail(lead, leadLogger, {
      requestHost: req.get("host"),
    });

    if (!result.success) {
      if (result.error === "RESEND_API_KEY_MISSING") {
        res.status(503).json({
          success: false,
          message: errorMessage(lead.site_language, "resend_missing", lead.source_site),
        });
        return;
      }
      res.status(500).json({
        success: false,
        message: errorMessage(lead.site_language, "generic", lead.source_site),
      });
      return;
    }

    res.json({ success: true, lead_id: lead.lead_id });
    return;
  }

  try {
    const result = await deliverLead(parsed.data, { host: req.get("host") });

    if (!result.delivered) {
      return res.status(503).json({
        error: result.error ?? "Service indisponible",
      });
    }

    const body: Record<string, unknown> = {
      ok: true,
      channels: result.channels,
      lead_id: result.lead_id,
    };
    if (profile.includeCrmLeadIdInResponse) {
      body.crm_lead_id = result.crm_lead_id;
    }
    return res.status(201).json(body);
  } catch (err) {
    logger.error({ err }, "Lead delivery failed");
    return res.status(500).json({
      error: "Erreur serveur lors de l'enregistrement de la demande",
    });
  }
});

export default router;
