import { describe, it, expect, beforeEach } from "vitest";
import { activeHosts, charTarget, type HostId } from "../support/hosts";
import { setActiveHostProfile } from "../../reconciled/src/config/runtime";
import {
  PROFILES,
  originsForDomains,
} from "../../reconciled/src/config/profiles";
import { allowedOriginsForActiveHost } from "../../reconciled/src/lib/cors";

/**
 * CORS must be per-host. Only meaningful against the reconciled trunk
 * (extracts: four hosts used cors() open; IK-DE had a partial hardcoded list).
 */
describe("cors · per-host allowlist (reconciled)", () => {
  beforeEach(() => {
    delete process.env.ALLOWED_ORIGINS;
  });

  it.skipIf(charTarget() !== "reconciled")(
    "each host allows its own origin and rejects another host's",
    () => {
      const hosts = activeHosts();
      for (const host of hosts) {
        setActiveHostProfile(host);
        const allowed = allowedOriginsForActiveHost();
        const own = `https://${PROFILES[host].servedDomains[0]}`;
        expect(allowed, host).toContain(own);
        expect(allowed, host).toContain(`https://www.${PROFILES[host].servedDomains[0]}`);

        const other = hosts.find((h) => h !== host)!;
        const foreign = `https://${PROFILES[other].servedDomains[0]}`;
        // foreign apex must not be on this host's list (unless domain coincidence — none today)
        expect(allowed, `${host} must reject ${foreign}`).not.toContain(foreign);
      }
    },
  );

  it.skipIf(charTarget() !== "reconciled")(
    "hetzner does not inherit ik-de garten-only defaults",
    () => {
      setActiveHostProfile("hetzner");
      const allowed = allowedOriginsForActiveHost();
      expect(allowed).toContain("https://helvetic-kaminfeger.ch");
      expect(allowed).not.toContain("https://helvetic-garten.ch");
    },
  );

  it.skipIf(charTarget() !== "reconciled")(
    "infomaniak-de allowlist covers all eight served domains, not only garten",
    () => {
      setActiveHostProfile("infomaniak-de");
      const allowed = allowedOriginsForActiveHost();
      for (const d of PROFILES["infomaniak-de"].servedDomains) {
        expect(allowed).toContain(`https://${d}`);
      }
      expect(originsForDomains(PROFILES["infomaniak-de"].servedDomains).length).toBe(16);
    },
  );
});

describe.each(activeHosts())("cors · profile domains present · %s", (host: HostId) => {
  it.skipIf(charTarget() !== "reconciled")("servedDomains non-empty", () => {
    expect(PROFILES[host].servedDomains.length).toBeGreaterThan(0);
  });
});
