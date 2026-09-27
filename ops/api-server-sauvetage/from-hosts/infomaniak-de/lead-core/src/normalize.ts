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

function resolveSiteLanguage(
  raw: Record<string, unknown>,
  host?: string,
  override?: SiteLanguage,
): SiteLanguage {
  const explicit = raw.site_language;
  if (explicit === "fr" || explicit === "de") return explicit;
  return languageFromHost(host, override);
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

function resolvePage(raw: Record<string, unknown>, referer?: string): string {
  return (
    asString(raw.source_page) ??
    asString(raw.page_origine) ??
    asString(raw.page) ??
    (referer ? referer.replace(/^https?:\/\/[^/]+/i, "") || "/" : "/")
  );
}

function resolveService(raw: Record<string, unknown>): string | undefined {
  return (
    asString(raw.service) ??
    asString(raw.serviceSlug) ??
    asString(raw.service_type) ??
    asString(raw.leistung) ??
    asString(raw.type_travaux) ??
    asString(raw.besoin) ??
    asString(raw.probleme) ??
    asString(raw.type_nuisible) ??
    asString(raw.problemType) ??
    asString(raw.need) ??
    asString(raw.problem_type) ??
    asString(raw.pest_type) ??
    asString(raw.schaedling) ??
    asString(raw.schaedlingsart) ??
    asString(raw.problem) ??
    asString(raw.bedarf) ??
    asString(raw.arbeitstyp) ??
    asString(raw.niveau)
  );
}

function resolveCity(raw: Record<string, unknown>): string | undefined {
  return (
    asString(raw.city) ??
    asString(raw.ville) ??
    asString(raw.ort) ??
    asString(raw.locality) ??
    asString(raw.gemeinde) ??
    asString(raw.commune) ??
    asString(raw.zone) ??
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

  const setExtra = (key: string, value: string | undefined) => {
    const v = value?.trim();
    if (v && !(key in fromObject)) extras[key] = v;
  };

  const typeClient =
    asString(raw.typeClient) ??
    asString(raw.type_client) ??
    asString(raw.type_bien) ??
    asString(raw.kundentyp);
  const frequence =
    asString(raw.frequence) ?? asString(raw.frequency) ?? asString(raw.haeufigkeit);
  const profil = asString(raw.profil) ?? asString(raw.profile) ?? asString(raw.typeClient);

  setExtra("typeClient", typeClient);
  setExtra("frequence", frequence);
  setExtra("kundentyp", asString(raw.kundentyp));
  setExtra("haeufigkeit", asString(raw.haeufigkeit));
  if (profil && profil !== typeClient) setExtra("profil", profil);

  setExtra("pool_type", asString(raw.pool_type));
  setExtra("client_type", asString(raw.client_type));
  setExtra(
    "wedding_date",
    asString(raw.wedding_date) ?? asString(raw.hochzeitsdatum) ?? asString(raw.datum),
  );
  setExtra("canton", asString(raw.canton) ?? asString(raw.kanton) ?? asString(raw.region));
  setExtra("npa", asString(raw.npa) ?? asString(raw.postal_code) ?? asString(raw.plz));
  setExtra("horizont", asString(raw.horizont));
  setExtra("bedarf", asString(raw.bedarf));
  setExtra("niveau", asString(raw.niveau));
  setExtra("ziel", asString(raw.ziel));
  setExtra("situation", asString(raw.situation));

  const merged = { ...extras, ...fromObject };
  return Object.keys(merged).length > 0 ? merged : undefined;
}

/** Schädlinge hero : prestation / ville / urgence dans step_answers.step_* */
function applySchaedlingeHeroFromStepAnswers(lead: LeadData): void {
  const steps = lead.step_answers;
  if (!steps) return;
  if (!lead.service?.trim() && steps.step_1) lead.service = steps.step_1;
  if (!lead.city?.trim() && steps.step_3) lead.city = steps.step_3;
  if (!lead.urgency?.trim() && steps.step_4) lead.urgency = steps.step_4;
}

function validationMessages(lang: SiteLanguage): {
  invalidJson: string;
  invalidData: string;
  phone: string;
  name: string;
  email: string;
} {
  if (lang === "de") {
    return {
      invalidJson: "Ungültige JSON-Daten",
      invalidData: "Ungültige Daten",
      phone: "Telefon erforderlich (mindestens 6 Zeichen)",
      name: "Name erforderlich",
      email: "Ungültige E-Mail-Adresse",
    };
  }
  return {
    invalidJson: "Corps JSON invalide",
    invalidData: "Données invalides",
    phone: "Téléphone requis (6 caractères minimum)",
    name: "Nom requis",
    email: "Email invalide",
  };
}

/**
 * Defensive parser for legacy FR/DE form payloads → LeadData (mutualized VPS).
 * TODO Phase 3 (fin migration 16 fronts) : rejeter si lead.consent !== true.
 */
export function normalizeLegacyLeadBody(
  body: unknown,
  ctx: NormalizeRequestContext = {},
): NormalizeResult {
  const langHint = ctx.default_language ?? languageFromHost(ctx.host);
  const msgs = validationMessages(langHint);

  if (!body || typeof body !== "object") {
    return { ok: false, error: msgs.invalidJson, fieldErrors: { _form: [msgs.invalidJson] } };
  }

  const raw = body as Record<string, unknown>;
  const siteLanguage = resolveSiteLanguage(raw, ctx.host, ctx.default_language);

  const phone = resolvePhone(raw);
  const name = resolveName(raw);
  const fieldErrors: Record<string, string[]> = {};

  if (!phone || phone.length < 6) {
    fieldErrors.telephone = [msgs.phone];
  }
  if (!name || name.length < 2) {
    fieldErrors.nom = [msgs.name];
  }

  const emailRaw = asString(raw.email);
  if (emailRaw && !isEmail(emailRaw)) {
    fieldErrors.email = [msgs.email];
  }

  if (Object.keys(fieldErrors).length > 0) {
    return { ok: false, error: msgs.invalidData, fieldErrors };
  }

  const sourceSite =
    asString(raw.source_site) ??
    asString(raw.site) ??
    siteFromHost(ctx.host, ctx.default_site);

  const lead: LeadData = {
    lead_id: randomUUID(),
    site_language: siteLanguage,
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
      raw.rappel_souhaite === true ||
      raw.rueckruf_gewuenscht === true,
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

  applySchaedlingeHeroFromStepAnswers(lead);

  return { ok: true, data: lead };
}
