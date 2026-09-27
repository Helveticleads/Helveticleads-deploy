import { Router, type IRouter } from "express";
import { normalizeLegacyLeadBody } from "@workspace/lead-core";
import { deliverLead } from "../services/deliver-lead";
import { logger } from "../lib/logger";

const router: IRouter = Router();

function honeypotTriggered(body: unknown): boolean {
  if (!body || typeof body !== "object") return false;
  const website = (body as Record<string, unknown>).website;
  return typeof website === "string" && website.trim().length > 0;
}

router.post(["/leads", "/contact"], async (req, res) => {
  if (honeypotTriggered(req.body)) {
    logger.info({ host: req.get("host") }, "Honeypot triggered — silent accept");
    return res.status(201).json({ ok: true, channels: [] });
  }

  const parsed = normalizeLegacyLeadBody(req.body, {
    host: req.get("host"),
    referer: typeof req.get("referer") === "string" ? req.get("referer") : undefined,
    ip_address:
      (req.headers["x-forwarded-for"] as string | undefined)?.split(",")[0]?.trim() ??
      req.socket.remoteAddress,
    user_agent: req.headers["user-agent"],
    default_site: process.env.SITE_DOMAIN ?? "helvetique-jardin.ch",
  });

  if (!parsed.ok) {
    return res.status(400).json({
      error: "Données invalides",
      details: parsed.fieldErrors,
    });
  }

  try {
    const result = await deliverLead(parsed.data, { host: req.get("host") });

    if (!result.delivered) {
      return res.status(503).json({
        error: result.error ?? "Service indisponible",
      });
    }

    return res.status(201).json({
      ok: true,
      channels: result.channels,
      lead_id: result.lead_id,
    });
  } catch (err) {
    logger.error({ err }, "Lead delivery failed");
    return res.status(500).json({
      error: "Erreur serveur lors de l'enregistrement de la demande",
    });
  }
});

export default router;
