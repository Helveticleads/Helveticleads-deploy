import type { CorsOptions } from "cors";
import { getActiveHostProfile } from "../config/runtime";
import { DEV_ORIGINS, originsForDomains } from "../config/profiles";

/**
 * CORS allowlist is per host profile (servedDomains), not a shared IK-DE list.
 * ALLOWED_ORIGINS env can add extras (comma-separated) without removing profile domains.
 */
export function allowedOriginsForActiveHost(): string[] {
  const profile = getActiveHostProfile();
  const fromProfile = originsForDomains(profile.servedDomains);
  const fromEnv = (process.env.ALLOWED_ORIGINS ?? "")
    .split(",")
    .map((v) => v.trim())
    .filter(Boolean);
  return [...new Set([...fromProfile, ...DEV_ORIGINS, ...fromEnv])];
}

export function getCorsOptions(): CorsOptions {
  const allowed = allowedOriginsForActiveHost();

  return {
    origin(origin, callback) {
      if (!origin || allowed.includes(origin)) {
        callback(null, true);
        return;
      }
      callback(new Error(`CORS blocked for origin: ${origin}`));
    },
    methods: ["GET", "POST", "OPTIONS"],
    allowedHeaders: ["Content-Type", "X-Lead-Signature"],
  };
}
