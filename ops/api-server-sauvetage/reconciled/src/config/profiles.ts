import type { SiteLanguage } from "../../reconciled/lead-core/src/types";

/**
 * Host behaviour profile — photographs production quirks as configuration.
 * recipients.ts stays convention-based (prefix@domain); not configurable here.
 */
export type ResponseStyle = "legacy" | "ikde";

export type HostProfile = {
  id: string;
  /** Normalize / validation language behaviour */
  bilingualValidation: boolean;
  resolveSiteLanguageFromBody: boolean;
  defaultLanguage?: SiteLanguage;
  defaultSite: string;
  includeAddress: boolean;
  includeConsent: boolean;
  schaedlingeHeroAdapter: boolean;
  /** City alias chain identity */
  cityChain: "hetzner" | "lws" | "fr" | "de";
  /** Service alias chain */
  serviceChain: "hetzner" | "fr" | "de";
  phoneHasTelefon: boolean;
  messageHasNachricht: boolean;
  urgencyHasDringlichkeit: boolean;
  stepAnswersRichDe: boolean;
  /** Route */
  honeypotFields: readonly string[];
  responseStyle: ResponseStyle;
  includeCrmLeadIdInResponse: boolean;
  /** Delivery channels (what the host code *can* activate; env still required) */
  delivery: {
    usesDeliverLead: boolean;
    supportsCrmPush: boolean;
    supportsLegacyCrmWebhook: boolean;
    supportsLeadsWebhook: boolean;
  };
};

export const PROFILES: Record<string, HostProfile> = {
  hetzner: {
    id: "hetzner",
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
