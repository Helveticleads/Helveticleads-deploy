import { Router, type IRouter, type Request, type Response } from "express";
import { normalizeLegacyLeadBody, sendLeadEmail } from "@workspace/lead-core";
import { sendLeadWebhook } from "../lib/webhook";
import { logger } from "../lib/logger";

const router: IRouter = Router();

const HONEYPOT_FIELDS = ["website", "website_url", "company_website", "_hp"] as const;

function honeypotTriggered(body: unknown): boolean {
  if (!body || typeof body !== "object") return false;
  const raw = body as Record<string, unknown>;
  return HONEYPOT_FIELDS.some((key) => {
    const value = raw[key];
    return typeof value === "string" && value.trim().length > 0;
  });
}

function contactEmail(site: string, lang: "fr" | "de"): string {
  if (process.env["CONTACT_EMAIL"]) return process.env["CONTACT_EMAIL"];
  const domain = site.replace(/^https?:\/\//, "").replace(/\/$/, "");
  return lang === "fr" ? `contact@${domain}` : `kontakt@${domain}`;
}

function errorMessage(lang: "fr" | "de", code: "resend_missing" | "generic", site: string): string {
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
  if (honeypotTriggered(req.body)) {
    logger.info({ host: req.get("host") }, "Honeypot triggered — silent accept");
    res.json({ success: true });
    return;
  }

  const parsed = normalizeLegacyLeadBody(req.body, {
    host: req.get("host"),
    referer: typeof req.get("referer") === "string" ? req.get("referer") : undefined,
    ip_address:
      (req.headers["x-forwarded-for"] as string | undefined)?.split(",")[0]?.trim() ??
      req.socket.remoteAddress,
    user_agent: req.headers["user-agent"],
    default_site: process.env.SITE_DOMAIN ?? "helvetic-garten.ch",
    default_language: "de",
  });

  if (!parsed.ok) {
    res.status(400).json({
      success: false,
      message: parsed.error ?? "Ungültige Daten",
    });
    return;
  }

  const lead = parsed.data;

  void sendLeadWebhook(lead).catch((err) => {
    logger.error({ err, lead_id: lead.lead_id }, "Unhandled webhook error");
  });

  const result = await sendLeadEmail(lead, leadLogger, { requestHost: req.get("host") });

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
});

export default router;
