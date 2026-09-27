export { normalizeLegacyLeadBody } from "./normalize";
export { resolveRecipients } from "./recipients";
export { sendLeadEmail } from "./email";
export { buildSubject, siteLabel, isUrgentLead } from "./subject";
export {
  buildHtml,
  buildText,
  LEAD_EMAIL_BRAND_COLOR,
  LEAD_EMAIL_LOGO_URL,
} from "./template";
export type * from "./types";
