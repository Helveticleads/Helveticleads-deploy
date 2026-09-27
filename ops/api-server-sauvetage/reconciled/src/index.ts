import { setActiveHostProfile } from "./config/runtime";
import app from "./app";
import { logger } from "./lib/logger";

/**
 * Boot: HOST_PROFILE selects the host behaviour photograph (ionos | hetzner | …).
 * Required — no silent default to another host's quirks on a wrong VPS.
 */
const rawProfile = process.env["HOST_PROFILE"];
if (!rawProfile || !rawProfile.trim()) {
  throw new Error(
    "HOST_PROFILE environment variable is required but was not provided.",
  );
}

const profile = setActiveHostProfile(rawProfile.trim());

const rawPort = process.env["PORT"];
if (!rawPort) {
  throw new Error(
    "PORT environment variable is required but was not provided.",
  );
}

const port = Number(rawPort);
if (Number.isNaN(port) || port <= 0) {
  throw new Error(`Invalid PORT value: "${rawPort}"`);
}

app.listen(port, (err) => {
  if (err) {
    logger.error({ err }, "Error listening on port");
    process.exit(1);
  }

  logger.info({ port, hostProfile: profile.id }, "Server listening");
});
