export type SiteLanguage = "fr" | "de";

export type LeadData = {
  lead_id: string;
  site_language: SiteLanguage;
  source_site: string;
  source_page: string;
  form_type: string;
  name: string;
  phone: string;
  email?: string;
  city?: string;
  address?: string;
  service?: string;
  message?: string;
  urgency?: string;
  step_answers?: Record<string, string>;
  callback_requested?: boolean;
  callback_slot?: string;
  consent?: boolean;
  user_agent?: string;
  ip_address?: string;
  created_at: string;
};

export type NormalizeRequestContext = {
  host?: string;
  referer?: string;
  ip_address?: string;
  user_agent?: string;
  default_site?: string;
  default_language?: SiteLanguage;
};

export type NormalizeResult =
  | { ok: true; data: LeadData }
  | { ok: false; error: string; fieldErrors?: Record<string, string[]> };

export type LeadCoreLogger = {
  info: (obj: Record<string, unknown>, msg: string) => void;
  warn: (obj: Record<string, unknown>, msg: string) => void;
  error: (obj: Record<string, unknown>, msg: string) => void;
};

export type SendLeadEmailOptions = { requestHost?: string };

export type SendLeadEmailResult = { success: boolean; error?: string };
