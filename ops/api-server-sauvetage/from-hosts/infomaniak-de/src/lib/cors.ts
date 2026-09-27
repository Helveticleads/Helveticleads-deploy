import type { CorsOptions } from "cors";

const DEFAULT_ORIGINS = [
  "https://helvetic-garten.ch",
  "https://www.helvetic-garten.ch",
  "http://localhost:18547",
  "http://127.0.0.1:18547",
  "http://localhost:5173",
  "http://127.0.0.1:5173",
];

function parseAllowedOrigins(): string[] {
  const fromEnv = process.env.ALLOWED_ORIGINS?.split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return fromEnv?.length ? [...new Set([...DEFAULT_ORIGINS, ...fromEnv])] : DEFAULT_ORIGINS;
}

export function getCorsOptions(): CorsOptions {
  const allowed = parseAllowedOrigins();

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
