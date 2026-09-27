import { randomUUID } from "node:crypto";
import type { LeadData, NormalizeRequestContext, NormalizeResult, SiteLanguage } from "./types";

function asString(value: unknown): string | undefined {
  return typeof value === "string" ? value.trim() : undefined;
}

function isEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function siteFromHost(host?: string, fallback?: string): string {
  const h = host?.split(":")[0]?.trim();
  if (h) return `https://${h}`;
  if (fallback) return fallback.startsWith("http") ? fallback : `https://${fallback}`;
  return "https://helvetique-jardin.ch";
}

function languageFromHost(host?: string, override?: SiteLanguage): SiteLanguage {
  if (override) return override;
  const h = host?.toLowerCase() ?? "";
  if (h.includes("helvetic-") || h.endsWith(".de")) return "de";
  return "fr";
}

function resolveFormType(raw: Record<string, unknown>): string {
  const explicit =
    asString(raw.form_type) ??
    asString(raw.type_formulaire) ??
    asString(raw.formType);
  if (explicit) return explicit;

  const source = asString(raw.source);
  if (source === "hero" || source === "contact") return source;

  return "lead";
}

function resolveName(raw: Record<string, unknown>): string | undefined {
  const prenom = asString(raw.prenom) ?? asString(raw.firstName);
  const nomPart = asString(raw.nom) ?? asString(raw.lastName);

  if (prenom) {
    if (nomPart) return `${prenom} ${nomPart}`.trim();
    if (prenom.length >= 2) return prenom;
  }

  const direct = asString(raw.name) ?? asString(raw.nom);
  if (direct && direct.length >= 2) return direct;

  return undefined;
}

function resolvePhone(raw: Record<string, unknown>): string | undefined {
  return (
    asString(raw.phone) ??
    asString(raw.telephone) ??
    asString(raw.telefon) ??
    asString(raw.tel)
  );
}

function resolveService(raw: Record<string, unknown>): string | undefined {
  return (
    asString(raw.service) ??
    asString(raw.serviceSlug) ??
    asString(raw.service_type) ??
    asString(raw.type_travaux) ??
    asString(raw.besoin) ??
    asString(raw.probleme) ??
    asString(raw.type_nuisible) ??
    asString(raw.problemType) ??
    asString(raw.need) ??
    asString(raw.niveau)
  );
}

function resolveCity(raw: Record<string, unknown>): string | undefined {
  return (
    asString(raw.city) ??
    asString(raw.zone) ??
    asString(raw.ville) ??
    asString(raw.ort) ??
    asString(raw.locality) ??
    asString(raw.commune) ??
    asString(raw.region)
  );
}

function resolveUrgency(raw: Record<string, unknown>): string | undefined {
  return (
    asString(raw.urgency) ??
    asString(raw.urgence) ??
    asString(raw.dringlichkeit) ??
    asString(raw.horizon) ??
    asString(raw.horizont)
  );
}

/** consent / consentement — pas de rejet 400 tant que les 16 fronts ne sont pas migrés (Phase 3). */
function resolveConsent(raw: Record<string, unknown>): boolean {
  return raw.consent === true || raw.consentement === true;
}

function resolvePage(raw: Record<string, unknown>, referer?: string): string {
  return (
    asString(raw.source_page) ??
    asString(raw.page_origine) ??
    asString(raw.page) ??
    (referer ? referer.replace(/^https?:\/\/[^/]+/i, "") || "/" : "/")
  );
}

function buildStepAnswers(raw: Record<string, unknown>): Record<string, string> | undefined {
  const fromObject =
    raw.step_answers && typeof raw.step_answers === "object"
      ? Object.fromEntries(
          Object.entries(raw.step_answers as Record<string, unknown>)
            .filter(([, v]) => typeof v === "string" && (v as string).trim())
            .map(([k, v]) => [k, (v as string).trim()]),
        )
      : {};

  const extras: Record<string, string> = {};
  const typeClient = asString(raw.typeClient) ?? asString(raw.type_client) ?? asString(raw.type_bien);
  const frequence = asString(raw.frequence) ?? asString(raw.frequency);
  const profil = asString(raw.profil) ?? asString(raw.typeClient);
  const canton = asString(raw.canton) ?? asString(raw.region);
  const npa = asString(raw.npa) ?? asString(raw.postal_code) ?? asString(raw.plz);

  if (typeClient) extras.typeClient = typeClient;
  if (frequence) extras.frequence = frequence;
  if (profil && profil !== typeClient) extras.profil = profil;
  if (canton) extras.canton = canton;
  if (npa) extras.npa = npa;
  const horizon = asString(raw.horizon) ?? asString(raw.horizont);
  if (horizon) extras.horizon = horizon;
  const niveau = asString(raw.niveau);
  if (niveau) extras.niveau = niveau;

  const merged = { ...extras, ...fromObject };
  return Object.keys(merged).length > 0 ? merged : undefined;
}

/**
 * Defensive parser for legacy FR (and shared VPS) form payloads → LeadData.
 * TODO Phase 3 (fin migration 16 fronts) : rejeter si lead.consent !== true.
 */
export function normalizeLegacyLeadBody(
  body: unknown,
  ctx: NormalizeRequestContext = {},
): NormalizeResult {
  if (!body || typeof body !== "object") {
    return { ok: false, error: "Corps JSON invalide", fieldErrors: { _form: ["Corps JSON invalide"] } };
  }

  const raw = body as Record<string, unknown>;

  const phone = resolvePhone(raw);
  const name = resolveName(raw);
  const fieldErrors: Record<string, string[]> = {};

  if (!phone || phone.length < 6) {
    fieldErrors.telephone = ["Téléphone requis (6 caractères minimum)"];
  }
  if (!name || name.length < 2) {
    fieldErrors.nom = ["Nom requis"];
  }

  const emailRaw = asString(raw.email);
  if (emailRaw && !isEmail(emailRaw)) {
    fieldErrors.email = ["Email invalide"];
  }

  if (Object.keys(fieldErrors).length > 0) {
    return { ok: false, error: "Données invalides", fieldErrors };
  }

  const sourceSite =
    asString(raw.source_site) ??
    asString(raw.site) ??
    siteFromHost(ctx.host, ctx.default_site);

  const lead: LeadData = {
    lead_id: randomUUID(),
    site_language: languageFromHost(ctx.host, ctx.default_language),
    source_site: sourceSite,
    source_page: resolvePage(raw, ctx.referer),
    form_type: resolveFormType(raw),
    name: name!,
    phone: phone!,
    email: emailRaw || undefined,
    city: resolveCity(raw),
    service: resolveService(raw),
    message: asString(raw.message) ?? asString(raw.sujet) ?? asString(raw.nachricht),
    urgency: resolveUrgency(raw),
    step_answers: buildStepAnswers(raw),
    callback_requested:
      raw.callback_requested === true ||
      raw.demande_rappel === true ||
      raw.rappel_souhaite === true,
    callback_slot:
      asString(raw.callback_slot) ??
      asString(raw.creneau_rappel) ??
      asString(raw.rappel_creneau) ??
      asString(raw.rueckruf_zeit) ??
      asString(raw.preferred_callback_time),
    consent: resolveConsent(raw),
    user_agent: ctx.user_agent,
    ip_address: ctx.ip_address,
    created_at: new Date().toISOString(),
  };

  return { ok: true, data: lead };
}
