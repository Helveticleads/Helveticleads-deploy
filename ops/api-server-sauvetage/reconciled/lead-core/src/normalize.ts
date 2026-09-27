import { randomUUID } from "node:crypto";
import type {
  LeadData,
  NormalizeRequestContext,
  NormalizeResult,
  SiteLanguage,
} from "./types";
import { getActiveHostProfile } from "../../src/config/runtime";

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
  fromBody: boolean,
): SiteLanguage {
  if (fromBody) {
    const explicit = raw.site_language;
    if (explicit === "fr" || explicit === "de") return explicit;
  }
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

function resolvePhone(raw: Record<string, unknown>, hasTelefon: boolean): string | undefined {
  if (hasTelefon) {
    return (
      asString(raw.phone) ??
      asString(raw.telephone) ??
      asString(raw.telefon) ??
      asString(raw.tel)
    );
  }
  return asString(raw.phone) ?? asString(raw.telephone) ?? asString(raw.tel);
}

function resolvePage(raw: Record<string, unknown>, referer?: string): string {
  return (
    asString(raw.source_page) ??
    asString(raw.page_origine) ??
    asString(raw.page) ??
    (referer ? referer.replace(/^https?:\/\/[^/]+/i, "") || "/" : "/")
  );
}

function resolveCity(
  raw: Record<string, unknown>,
  chain: "hetzner" | "lws" | "fr" | "de",
): string | undefined {
  switch (chain) {
    case "hetzner":
      return (
        asString(raw.city) ??
        asString(raw.ville) ??
        asString(raw.ort) ??
        asString(raw.locality) ??
        asString(raw.zone)
      );
    case "lws":
      return (
        asString(raw.city) ??
        asString(raw.zone) ??
        asString(raw.ville) ??
        asString(raw.ort) ??
        asString(raw.locality)
      );
    case "fr":
      return (
        asString(raw.city) ??
        asString(raw.ville) ??
        asString(raw.ort) ??
        asString(raw.locality) ??
        asString(raw.commune) ??
        asString(raw.zone) ??
        asString(raw.region)
      );
    case "de":
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
}

function resolveService(
  raw: Record<string, unknown>,
  chain: "hetzner" | "fr" | "de",
): string | undefined {
  if (chain === "hetzner") {
    return (
      asString(raw.service) ??
      asString(raw.serviceSlug) ??
      asString(raw.type_travaux) ??
      asString(raw.besoin) ??
      asString(raw.probleme) ??
      asString(raw.type_nuisible) ??
      asString(raw.problemType) ??
      asString(raw.need)
    );
  }
  if (chain === "fr") {
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

function resolveUrgency(
  raw: Record<string, unknown>,
  rich: boolean,
): string | undefined {
  if (!rich) {
    return asString(raw.urgency) ?? asString(raw.urgence);
  }
  return (
    asString(raw.urgency) ??
    asString(raw.urgence) ??
    asString(raw.dringlichkeit) ??
    asString(raw.horizon) ??
    asString(raw.horizont)
  );
}

function resolveConsent(raw: Record<string, unknown>): boolean {
  return raw.consent === true || raw.consentement === true;
}

function buildStepAnswers(
  raw: Record<string, unknown>,
  richDe: boolean,
): Record<string, string> | undefined {
  const fromObject =
    raw.step_answers && typeof raw.step_answers === "object"
      ? Object.fromEntries(
          Object.entries(raw.step_answers as Record<string, unknown>)
            .filter(([, v]) => typeof v === "string" && (v as string).trim())
            .map(([k, v]) => [k, (v as string).trim()]),
        )
      : {};

  const extras: Record<string, string> = {};

  if (richDe) {
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
  } else {
    const typeClient =
      asString(raw.typeClient) ?? asString(raw.type_client) ?? asString(raw.type_bien);
    const frequence = asString(raw.frequence) ?? asString(raw.frequency);
    const profil = asString(raw.profil) ?? asString(raw.typeClient);
    const canton = asString(raw.canton) ?? asString(raw.region);
    const npa = asString(raw.npa) ?? asString(raw.postal_code) ?? asString(raw.plz);
    if (typeClient) extras.typeClient = typeClient;
    if (frequence) extras.frequence = frequence;
    if (profil && profil !== typeClient) extras.profil = profil;
    if (canton) extras.canton = canton;
    if (npa) extras.npa = npa;
    // FR/IONOS also stash horizon/niveau when present
    const profile = getActiveHostProfile();
    if (profile.serviceChain === "fr" || profile.cityChain === "fr") {
      const horizon = asString(raw.horizon) ?? asString(raw.horizont);
      if (horizon) extras.horizon = horizon;
      const niveau = asString(raw.niveau);
      if (niveau) extras.niveau = niveau;
    }
  }

  const merged = { ...extras, ...fromObject };
  return Object.keys(merged).length > 0 ? merged : undefined;
}

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
 * Profile-aware normalize — behaviour selected by active host profile
 * (characterization fidelity). Pipeline richness from infomaniak-de.
 */
export function normalizeLegacyLeadBody(
  body: unknown,
  ctx: NormalizeRequestContext = {},
): NormalizeResult {
  const profile = getActiveHostProfile();
  const defaultLang =
    ctx.default_language ?? profile.defaultLanguage ?? languageFromHost(ctx.host);
  const langHint = profile.bilingualValidation
    ? defaultLang
    : ("fr" as SiteLanguage);
  const msgs = validationMessages(
    profile.bilingualValidation ? langHint : "fr",
  );

  if (!body || typeof body !== "object") {
    return {
      ok: false,
      error: msgs.invalidJson,
      fieldErrors: { _form: [msgs.invalidJson] },
    };
  }

  const raw = body as Record<string, unknown>;
  const siteLanguage = resolveSiteLanguage(
    raw,
    ctx.host,
    ctx.default_language ?? profile.defaultLanguage,
    profile.resolveSiteLanguageFromBody,
  );

  const phone = resolvePhone(raw, profile.phoneHasTelefon);
  const name = resolveName(raw);
  const fieldErrors: Record<string, string[]> = {};

  if (!phone || phone.length < 6) fieldErrors.telephone = [msgs.phone];
  if (!name || name.length < 2) fieldErrors.nom = [msgs.name];

  const emailRaw = asString(raw.email);
  if (emailRaw && !isEmail(emailRaw)) fieldErrors.email = [msgs.email];

  if (Object.keys(fieldErrors).length > 0) {
    return { ok: false, error: msgs.invalidData, fieldErrors };
  }

  const sourceSite =
    asString(raw.source_site) ??
    asString(raw.site) ??
    siteFromHost(ctx.host, ctx.default_site ?? profile.defaultSite);

  const message =
    asString(raw.message) ??
    asString(raw.sujet) ??
    (profile.messageHasNachricht ? asString(raw.nachricht) : undefined);

  let callbackRequested =
    raw.callback_requested === true ||
    raw.demande_rappel === true ||
    raw.rappel_souhaite === true;
  if (profile.stepAnswersRichDe) {
    callbackRequested =
      callbackRequested || raw.rueckruf_gewuenscht === true;
  }

  let callbackSlot =
    asString(raw.callback_slot) ??
    asString(raw.creneau_rappel) ??
    asString(raw.rappel_creneau);
  if (profile.phoneHasTelefon) {
    callbackSlot =
      callbackSlot ??
      asString(raw.rueckruf_zeit) ??
      asString(raw.preferred_callback_time);
  }

  const lead: LeadData = {
    lead_id: randomUUID(),
    site_language: siteLanguage,
    source_site: sourceSite,
    source_page: resolvePage(raw, ctx.referer),
    form_type: resolveFormType(raw),
    name: name!,
    phone: phone!,
    email: emailRaw || undefined,
    city: resolveCity(raw, profile.cityChain),
    ...(profile.includeAddress
      ? {
          address: asString(raw.adresse) ?? asString(raw.address),
        }
      : {}),
    service: resolveService(raw, profile.serviceChain),
    message,
    urgency: resolveUrgency(raw, profile.urgencyHasDringlichkeit),
    step_answers: buildStepAnswers(raw, profile.stepAnswersRichDe),
    callback_requested: callbackRequested,
    callback_slot: callbackSlot,
    ...(profile.includeConsent ? { consent: resolveConsent(raw) } : {}),
    user_agent: ctx.user_agent,
    ip_address: ctx.ip_address,
    created_at: new Date().toISOString(),
  };

  if (profile.schaedlingeHeroAdapter) {
    applySchaedlingeHeroFromStepAnswers(lead);
  }

  return { ok: true, data: lead };
}
