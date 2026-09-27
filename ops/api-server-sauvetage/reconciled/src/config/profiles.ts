import type { SiteLanguage } from "../../lead-core/src/types";

/**
 * Host behaviour profile — photographs production quirks as configuration.
 * recipients.ts stays convention-based (prefix@domain); not configurable here.
 *
 * servedDomains: apex hostnames actually served on that VPS (nginx sites-enabled,
 * 2026-09-27). CORS allows https://{d} and https://www.{d} for each entry.
 */
export type ResponseStyle = "legacy" | "ikde";

export type HostProfile = {
  id: string;
  /** Apex domains this host serves — sole source of CORS allowlist (plus optional ALLOWED_ORIGINS). */
  servedDomains: readonly string[];
  bilingualValidation: boolean;
  resolveSiteLanguageFromBody: boolean;
  defaultLanguage?: SiteLanguage;
  defaultSite: string;
  includeAddress: boolean;
  includeConsent: boolean;
  schaedlingeHeroAdapter: boolean;
  cityChain: "hetzner" | "lws" | "fr" | "de";
  serviceChain: "hetzner" | "fr" | "de";
  phoneHasTelefon: boolean;
  messageHasNachricht: boolean;
  urgencyHasDringlichkeit: boolean;
  stepAnswersRichDe: boolean;
  honeypotFields: readonly string[];
  responseStyle: ResponseStyle;
  includeCrmLeadIdInResponse: boolean;
  delivery: {
    usesDeliverLead: boolean;
    supportsCrmPush: boolean;
    supportsLegacyCrmWebhook: boolean;
    supportsLeadsWebhook: boolean;
  };
};

/** Dev/loopback origins shared; never production site origins. */
export const DEV_ORIGINS = [
  "http://localhost:18547",
  "http://127.0.0.1:18547",
  "http://localhost:5173",
  "http://127.0.0.1:5173",
] as const;

export function originsForDomains(domains: readonly string[]): string[] {
  const out: string[] = [];
  for (const d of domains) {
    const apex = d.replace(/^www\./, "").toLowerCase();
    out.push(`https://${apex}`, `https://www.${apex}`);
  }
  return out;
}

export const PROFILES: Record<string, HostProfile> = {
  hetzner: {
    id: "hetzner",
    servedDomains: [
      "helvetic-dachdecker.ch",
      "helvetic-daemmung.ch",
      "helvetic-elektriker.ch",
      "helvetic-glaserei.ch",
      "helvetic-heizung.ch",
      "helvetic-kaminfeger.ch",
      "helvetic-rohrreinigung.ch",
      "helvetic-sanitaer.ch",
      "helvetic-schluesseldienst.ch",
    ],
    bilingualValidation: false,
    resolveSiteLanguageFromBody: false,
    defaultSite: "helvetique-jardin.ch",
    includeAddress: true,
    includeConsent: false,
    schaedlingeHeroAdapter: false,
    cityChain: "hetzner",
    serviceChain: "hetzner",
    phoneHasTelefon: false,
    messageHasNachricht: false,
    urgencyHasDringlichkeit: false,
    stepAnswersRichDe: false,
    honeypotFields: ["website"],
    responseStyle: "legacy",
    includeCrmLeadIdInResponse: false,
    delivery: {
      usesDeliverLead: true,
      supportsCrmPush: false,
      supportsLegacyCrmWebhook: true,
      supportsLeadsWebhook: false,
    },
  },
  lws: {
    id: "lws",
    servedDomains: [
      "helvetique-assainissement.ch",
      "helvetique-carrelage.ch",
      "helvetique-chauffage.ch",
      "helvetique-dentaire.ch",
      "helvetique-electricite.ch",
      "helvetique-ferronnerie.ch",
      "helvetique-isolation.ch",
      "helvetique-maconnerie.ch",
      "helvetique-menuiserie.ch",
      "helvetique-panneau-solaire.ch",
      "helvetique-plaquiste.ch",
      "helvetique-plomberie.ch",
      "helvetique-ramonage.ch",
      "helvetique-renovation-exterieure.ch",
      "helvetique-renovation-interieure.ch",
      "helvetique-serrurerie.ch",
      "helvetique-toiture.ch",
      "helvetique-vitrerie.ch",
    ],
    bilingualValidation: false,
    resolveSiteLanguageFromBody: false,
    defaultSite: "helvetique-jardin.ch",
    includeAddress: false,
    includeConsent: false,
    schaedlingeHeroAdapter: false,
    cityChain: "lws",
    serviceChain: "hetzner",
    phoneHasTelefon: false,
    messageHasNachricht: false,
    urgencyHasDringlichkeit: false,
    stepAnswersRichDe: false,
    honeypotFields: ["website"],
    responseStyle: "legacy",
    includeCrmLeadIdInResponse: false,
    delivery: {
      usesDeliverLead: true,
      supportsCrmPush: false,
      supportsLegacyCrmWebhook: true,
      supportsLeadsWebhook: false,
    },
  },
  "infomaniak-fr": {
    id: "infomaniak-fr",
    servedDomains: [
      "helvetique-demenagements.ch",
      "helvetique-elagage.ch",
      "helvetique-evenementiel.ch",
      "helvetique-ia.ch",
      "helvetique-jardin.ch",
      "helvetique-mariage.ch",
      "helvetique-nettoyage.ch",
      "helvetique-nuisibles.ch",
      "helvetique-patrimoine.ch",
      "helvetique-peinture.ch",
      "helvetique-piscine.ch",
      "helvetique-spa.ch",
      "helvetique-web.ch",
    ],
    bilingualValidation: false,
    resolveSiteLanguageFromBody: false,
    defaultLanguage: "fr",
    defaultSite: "helvetique-jardin.ch",
    includeAddress: false,
    includeConsent: true,
    schaedlingeHeroAdapter: false,
    cityChain: "fr",
    serviceChain: "fr",
    phoneHasTelefon: true,
    messageHasNachricht: true,
    urgencyHasDringlichkeit: true,
    stepAnswersRichDe: false,
    honeypotFields: ["website"],
    responseStyle: "legacy",
    includeCrmLeadIdInResponse: false,
    delivery: {
      usesDeliverLead: true,
      supportsCrmPush: false,
      supportsLegacyCrmWebhook: true,
      supportsLeadsWebhook: false,
    },
  },
  "infomaniak-de": {
    id: "infomaniak-de",
    servedDomains: [
      "helvetic-garten.ch",
      "helvetic-hochzeit.ch",
      "helvetic-malerei.ch",
      "helvetic-pool.ch",
      "helvetic-reinigung.ch",
      "helvetic-schaedlinge.ch",
      "helvetic-vermoegen.ch",
      "helvetic-whirlpool.ch",
    ],
    bilingualValidation: true,
    resolveSiteLanguageFromBody: true,
    defaultLanguage: "de",
    defaultSite: "helvetic-garten.ch",
    includeAddress: false,
    includeConsent: true,
    schaedlingeHeroAdapter: true,
    cityChain: "de",
    serviceChain: "de",
    phoneHasTelefon: true,
    messageHasNachricht: true,
    urgencyHasDringlichkeit: true,
    stepAnswersRichDe: true,
    honeypotFields: ["website", "website_url", "company_website", "_hp"],
    responseStyle: "ikde",
    includeCrmLeadIdInResponse: false,
    delivery: {
      usesDeliverLead: false,
      supportsCrmPush: false,
      supportsLegacyCrmWebhook: false,
      supportsLeadsWebhook: true,
    },
  },
  ionos: {
    id: "ionos",
    servedDomains: [
      "helvetique-terrassement.ch",
      "debarrass-tout.be",
      "domisane-suisse.ch",
      "monexterminateursuisse.ch",
      "monjardiniersuisse.ch",
      "nuisibles-suisse.ch",
    ],
    bilingualValidation: false,
    resolveSiteLanguageFromBody: false,
    defaultSite: "helvetique-jardin.ch",
    includeAddress: false,
    includeConsent: true,
    schaedlingeHeroAdapter: false,
    cityChain: "fr",
    serviceChain: "fr",
    phoneHasTelefon: true,
    messageHasNachricht: true,
    urgencyHasDringlichkeit: true,
    stepAnswersRichDe: false,
    honeypotFields: ["website"],
    responseStyle: "legacy",
    includeCrmLeadIdInResponse: true,
    delivery: {
      usesDeliverLead: true,
      supportsCrmPush: true,
      supportsLegacyCrmWebhook: true,
      supportsLeadsWebhook: false,
    },
  },
};
