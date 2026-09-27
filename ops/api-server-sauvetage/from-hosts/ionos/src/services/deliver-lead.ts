/**
 * deliver-lead.ts — Double canal : Resend (e-mail) + CRM /api/leads/track
 *
 * CRM activé si CRM_PUSH_ENABLED=true (alias : CRM_TRACK_ENABLED / CRM_ENABLED)
 * ou si CRM_WEBHOOK_URL / CRM_TRACK_URL pointe vers …/api/leads/track.
 *
 * Tokens : lus depuis la table CRM `sites` via GET /api/leads/track-tokens
 * (header X-CRM-Push-Key). Cache mémoire + fichier local de secours.
 * Zéro config par site : tout domaine présent dans `sites` feed le CRM.
 * Idempotence : un lead_id n'est poussé qu'une seule fois (marque locale).
 */
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { sendLeadEmail, type LeadData } from "@workspace/lead-core";
import { logger } from "../lib/logger";

export type DeliveryResult = {
  delivered: boolean;
  channels: string[];
  error?: string;
  lead_id?: string;
  crm_lead_id?: number;
};

function getEnv(name: string, fallback?: string): string | undefined {
  const value = process.env[name]?.trim();
  if (value) return value;
  return fallback;
}

function envFlagTrue(name: string): boolean {
  const v = (getEnv(name) || "").toLowerCase();
  return v === "1" || v === "true" || v === "yes" || v === "on";
}

function normalizeDomain(input?: string | null): string {
  if (!input) return "";
  return String(input)
    .trim()
    .toLowerCase()
    .replace(/^https?:\/\//, "")
    .replace(/^www\./, "")
    .split("/")[0]
    .split(":")[0];
}

function domainFromLead(lead: LeadData, host?: string): string {
  const fromHost = normalizeDomain(host);
  if (fromHost) return fromHost;
  return normalizeDomain(lead.source_site);
}

function crmPushEnabled(): boolean {
  if (envFlagTrue("CRM_PUSH_ENABLED")) return true;
  if (envFlagTrue("CRM_TRACK_ENABLED")) return true;
  if (envFlagTrue("CRM_ENABLED")) return true;
  const url = getEnv("CRM_WEBHOOK_URL") || getEnv("CRM_TRACK_URL") || "";
  return /\/api\/leads\/track\/?$/i.test(url);
}

function crmTrackUrl(): string {
  const wh = getEnv("CRM_WEBHOOK_URL");
  if (wh && /\/api\/leads\/track/i.test(wh)) return wh.replace(/\/+$/, "");
  const explicit = getEnv("CRM_TRACK_URL");
  if (explicit) return explicit.replace(/\/+$/, "");
  return ""; // require CRM_TRACK_URL or CRM_WEBHOOK_URL
}

function crmTokensUrl(): string {
  const explicit = getEnv("CRM_TOKENS_URL");
  if (explicit) return explicit.replace(/\/+$/, "");
  // Même host que le webhook track → /api/leads/track-tokens
  return crmTrackUrl().replace(/\/track\/?$/i, "/track-tokens");
}

function tokensFilePath(): string {
  // Défaut writable par le service (deploy) — /etc/helvetic/ souvent root-only
  return getEnv("CRM_SITE_TOKENS_FILE") || "/var/lib/helvetic-api/site-tokens.json";
}

function crmSentDir(): string {
  return getEnv("CRM_SENT_DIR") || "/var/lib/helvetic-api/crm-sent";
}

function loadTokenMapFromFile(): Record<string, string> {
  const path = tokensFilePath();
  try {
    if (!existsSync(path)) return {};
    const raw = JSON.parse(readFileSync(path, "utf8")) as
      | Record<string, string>
      | { tokens?: Record<string, string> };
    const src =
      raw && typeof raw === "object" && "tokens" in raw && raw.tokens
        ? raw.tokens
        : (raw as Record<string, string>);
    const out: Record<string, string> = {};
    for (const [k, v] of Object.entries(src || {})) {
      const d = normalizeDomain(k);
      if (d && typeof v === "string" && v.startsWith("hl_")) out[d] = v;
    }
    return out;
  } catch (e) {
    logger.warn({ err: String(e) }, "CRM site-tokens file unreadable");
    return {};
  }
}

function persistTokenMap(map: Record<string, string>): void {
  try {
    const path = tokensFilePath();
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, JSON.stringify(map, null, 2) + "\n", { mode: 0o600 });
  } catch (e) {
    logger.warn({ err: String(e) }, "CRM site-tokens file write failed");
  }
}

let _tokenCache: { at: number; map: Record<string, string> } | null = null;
const TOKEN_CACHE_MS = 5 * 60_000;
let _fetchInFlight: Promise<Record<string, string>> | null = null;

async function fetchTokensFromCrmSites(): Promise<Record<string, string>> {
  const key = getEnv("CRM_PUSH_KEY");
  if (!key) {
    logger.warn("CRM_PUSH_KEY absent — fallback fichier tokens uniquement");
    return {};
  }
  if (_fetchInFlight) return _fetchInFlight;

  _fetchInFlight = (async () => {
    const url = crmTokensUrl();
    try {
      const response = await fetch(url, {
        method: "GET",
        headers: {
          Accept: "application/json",
          "X-CRM-Push-Key": key,
        },
      });
      const text = await response.text();
      if (!response.ok) {
        logger.error(
          { status: response.status, body: text.slice(0, 300) },
          "CRM track-tokens fetch failed",
        );
        return {};
      }
      const body = JSON.parse(text) as {
        tokens?: Record<string, string>;
      } & Record<string, string>;
      const src = body.tokens && typeof body.tokens === "object" ? body.tokens : body;
      const out: Record<string, string> = {};
      for (const [k, v] of Object.entries(src || {})) {
        if (k === "count" || k === "tokens") continue;
        const d = normalizeDomain(k);
        if (d && typeof v === "string" && v.startsWith("hl_")) out[d] = v;
      }
      if (Object.keys(out).length > 0) {
        persistTokenMap(out);
        logger.info({ count: Object.keys(out).length }, "CRM sites tokens refreshed");
      }
      return out;
    } catch (e) {
      logger.error({ err: String(e) }, "CRM track-tokens network error");
      return {};
    } finally {
      _fetchInFlight = null;
    }
  })();

  return _fetchInFlight;
}

async function resolveToken(domain: string): Promise<string | undefined> {
  const d = normalizeDomain(domain);
  if (!d) return undefined;

  const now = Date.now();
  if (_tokenCache && now - _tokenCache.at < TOKEN_CACHE_MS && _tokenCache.map[d]) {
    return _tokenCache.map[d];
  }

  // Live depuis table sites (CRM), puis cache fichier
  const live = await fetchTokensFromCrmSites();
  const file = loadTokenMapFromFile();
  const map = { ...file, ...live };
  _tokenCache = { at: now, map };

  if (map[d]) return map[d];

  // Cache froid / domaine nouveau : forcer un refresh si cache hit sans ce domaine
  if (Object.keys(live).length === 0) {
    const retry = await fetchTokensFromCrmSites();
    const merged = { ...map, ...retry };
    _tokenCache = { at: Date.now(), map: merged };
    return merged[d];
  }
  return undefined;
}

function splitName(name: string): { prenom: string; nom: string } {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return { prenom: "", nom: "" };
  if (parts.length === 1) return { prenom: parts[0], nom: "" };
  return { prenom: parts[0], nom: parts.slice(1).join(" ") };
}

function alreadyPushedToCrm(leadId: string): boolean {
  try {
    return existsSync(join(crmSentDir(), leadId));
  } catch {
    return false;
  }
}

function markPushedToCrm(leadId: string, crmLeadId?: number): void {
  try {
    mkdirSync(crmSentDir(), { recursive: true });
    writeFileSync(
      join(crmSentDir(), leadId),
      JSON.stringify({ at: new Date().toISOString(), crm_lead_id: crmLeadId ?? null }) + "\n",
      "utf8",
    );
  } catch (e) {
    logger.warn({ err: String(e), leadId }, "CRM idempotence mark failed");
  }
}

/** Mapping champs aligné sur l'endpoint PHP nuisibles → /api/leads/track */
function buildTrackPayload(lead: LeadData, token: string, domain: string) {
  const { prenom, nom } = splitName(lead.name || "");
  const messageParts = [
    lead.message,
    lead.service ? `Prestation : ${lead.service}` : "",
    lead.urgency ? `Urgence : ${lead.urgency}` : "",
    lead.callback_requested
      ? `Rappel demandé${lead.callback_slot ? ` (${lead.callback_slot})` : ""}`
      : "",
  ].filter(Boolean);

  return {
    token,
    site: domain,
    prenom,
    nom,
    telephone: lead.phone || "",
    email: lead.email || "",
    message: messageParts.join("\n") || undefined,
    localisation: lead.city || "",
    nature_demande: lead.service || lead.form_type || "",
    sujet_origine: lead.source_page || domain,
  };
}

type CrmPushResult = { ok: boolean; crm_lead_id?: number; skipped?: boolean };

async function sendViaCrmTrack(
  lead: LeadData,
  ctx?: { host?: string },
): Promise<CrmPushResult> {
  if (!crmPushEnabled()) return { ok: false };

  const domain = domainFromLead(lead, ctx?.host);
  const token = await resolveToken(domain);
  if (!token) {
    logger.warn({ domain, lead_id: lead.lead_id }, "CRM push: no token for domain (absent de sites ?)");
    return { ok: false };
  }

  if (alreadyPushedToCrm(lead.lead_id)) {
    logger.info({ lead_id: lead.lead_id, domain }, "CRM push: already pushed (idempotent skip)");
    return { ok: true, skipped: true };
  }

  const url = crmTrackUrl();
  const payload = buildTrackPayload(lead, token, domain);

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify(payload),
    });
    const bodyText = await response.text();
    let body: { success?: boolean; lead_id?: number; error?: string } = {};
    try {
      body = JSON.parse(bodyText) as typeof body;
    } catch {
      /* non-JSON */
    }

    if (response.status === 401) {
      logger.error({ domain, status: 401, body: bodyText.slice(0, 300) }, "CRM push: invalid token");
      return { ok: false };
    }

    if (!response.ok || body.success === false) {
      logger.error(
        { domain, status: response.status, body: bodyText.slice(0, 500) },
        "CRM push error",
      );
      return { ok: false };
    }

    const crmLeadId = typeof body.lead_id === "number" ? body.lead_id : undefined;
    markPushedToCrm(lead.lead_id, crmLeadId);
    logger.info({ domain, lead_id: lead.lead_id, crm_lead_id: crmLeadId }, "CRM push OK");
    return { ok: true, crm_lead_id: crmLeadId };
  } catch (e) {
    logger.error({ err: String(e), domain, lead_id: lead.lead_id }, "CRM push network error");
    return { ok: false };
  }
}

/** Legacy generic webhook (non-track URL). */
async function sendViaLegacyWebhook(lead: LeadData): Promise<boolean> {
  const url = getEnv("CRM_WEBHOOK_URL");
  if (!url || /\/api\/leads\/track/i.test(url)) return false;

  const secret = getEnv("CRM_WEBHOOK_SECRET");
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (secret) headers["X-Webhook-Secret"] = secret;

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
  const hasCrmPush = crmPushEnabled();
  const hasLegacyWebhook = Boolean(
    getEnv("CRM_WEBHOOK_URL") && !/\/api\/leads\/track/i.test(getEnv("CRM_WEBHOOK_URL") || ""),
  );

  if (!hasResend && !hasCrmPush && !hasLegacyWebhook) {
    logger.warn("Lead received but no delivery channel (RESEND_API_KEY / CRM_PUSH_ENABLED)");
    return {
      delivered: false,
      channels: [],
      error:
        "Réception des demandes non configurée. Définir RESEND_API_KEY ou CRM_PUSH_ENABLED/CRM_WEBHOOK_URL.",
    };
  }

  const channels: string[] = [];
  let crmLeadId: number | undefined;

  if (hasResend) {
    const result = await sendLeadEmail(lead, leadLogger, { requestHost: ctx?.host });
    if (result.success) channels.push("email");
  }

  if (hasCrmPush) {
    const crm = await sendViaCrmTrack(lead, ctx);
    if (crm.ok) {
      channels.push(crm.skipped ? "crm_skip" : "crm");
      if (crm.crm_lead_id) crmLeadId = crm.crm_lead_id;
    }
  } else if (hasLegacyWebhook) {
    const ok = await sendViaLegacyWebhook(lead);
    if (ok) channels.push("webhook");
  }

  if (channels.length === 0) {
    return {
      delivered: false,
      channels: [],
      error: "Échec de l'envoi. Vérifiez la configuration serveur (Resend / CRM push).",
      lead_id: lead.lead_id,
    };
  }

  logger.info(
    { channels, form_type: lead.form_type, lead_id: lead.lead_id, crm_lead_id: crmLeadId },
    "Lead delivered",
  );
  return {
    delivered: true,
    channels,
    lead_id: lead.lead_id,
    crm_lead_id: crmLeadId,
  };
}
