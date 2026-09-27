import { describe, it, expect, beforeAll } from "vitest";
import { activeHosts, type HostId } from "../support/hosts";
import { loadNormalize } from "../support/load";

const BASE = { name: "Ada Lovelace", phone: "0791234567" };

describe.each(activeHosts())("normalize · %s", (host: HostId) => {
  let normalizeLegacyLeadBody: (body: unknown, ctx?: object) => any;

  beforeAll(async () => {
    const mod = await loadNormalize(host);
    normalizeLegacyLeadBody = mod.normalizeLegacyLeadBody as typeof normalizeLegacyLeadBody;
  });

  it("rejects non-object body", () => {
    const r = normalizeLegacyLeadBody(null);
    expect(r.ok).toBe(false);
    expect(r.fieldErrors?._form?.length).toBeGreaterThan(0);
  });

  it("requires phone (≥6) and name (≥2)", () => {
    const r = normalizeLegacyLeadBody({ name: "A", phone: "123" });
    expect(r.ok).toBe(false);
    expect(r.fieldErrors.telephone).toBeTruthy();
    expect(r.fieldErrors.nom).toBeTruthy();
  });

  it("accepts minimal valid payload", () => {
    const r = normalizeLegacyLeadBody({ ...BASE });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.name).toBe("Ada Lovelace");
    expect(r.data.phone).toBe("0791234567");
    expect(r.data.lead_id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
    );
  });

  it("reads phone aliases phone|telephone|tel", () => {
    for (const key of ["phone", "telephone", "tel"] as const) {
      const r = normalizeLegacyLeadBody({ name: "Ada Lovelace", [key]: "0799999999" });
      expect(r.ok, key).toBe(true);
      if (r.ok) expect(r.data.phone).toBe("0799999999");
    }
  });

  it("telefon alias — host-specific", () => {
    const r = normalizeLegacyLeadBody({ name: "Ada Lovelace", telefon: "0798888777" });
    if (host === "hetzner" || host === "lws") {
      expect(r.ok).toBe(false); // telefon not read → phone missing
    } else {
      expect(r.ok).toBe(true);
      if (r.ok) expect(r.data.phone).toBe("0798888777");
    }
  });

  it("city alias chain — host-specific order / fields", () => {
    if (host === "hetzner") {
      // ville before zone
      const r = normalizeLegacyLeadBody({
        ...BASE,
        ville: "Genève",
        zone: "Zürich",
      });
      expect(r.ok).toBe(true);
      if (r.ok) expect(r.data.city).toBe("Genève");
    } else if (host === "lws") {
      // zone before ville
      const r = normalizeLegacyLeadBody({
        ...BASE,
        ville: "Genève",
        zone: "Zürich",
      });
      expect(r.ok).toBe(true);
      if (r.ok) expect(r.data.city).toBe("Zürich");
    } else if (host === "infomaniak-de") {
      const r = normalizeLegacyLeadBody({ ...BASE, gemeinde: "Bern" });
      expect(r.ok).toBe(true);
      if (r.ok) expect(r.data.city).toBe("Bern");
    } else {
      // fr / ionos — commune
      const r = normalizeLegacyLeadBody({ ...BASE, commune: "Lausanne" });
      expect(r.ok).toBe(true);
      if (r.ok) expect(r.data.city).toBe("Lausanne");
    }
  });

  it("address field — only hetzner", () => {
    const r = normalizeLegacyLeadBody({ ...BASE, adresse: "1 rue Test" });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    if (host === "hetzner") expect(r.data.address).toBe("1 rue Test");
    else expect(r.data.address).toBeUndefined();
  });

  it("service aliases — schaedling only on infomaniak-de", () => {
    const r = normalizeLegacyLeadBody({ ...BASE, schaedling: "wespen" });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    if (host === "infomaniak-de") expect(r.data.service).toBe("wespen");
    else expect(r.data.service).toBeUndefined();
  });

  it("consent — present on fr/de/ionos strata", () => {
    const r = normalizeLegacyLeadBody({ ...BASE, consent: true });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    if (host === "hetzner" || host === "lws") {
      expect(r.data.consent).toBeUndefined();
    } else {
      expect(r.data.consent).toBe(true);
    }
  });

  it("schaedlinge hero step_answers adapter — only infomaniak-de", () => {
    const r = normalizeLegacyLeadBody({
      ...BASE,
      step_answers: { step_1: "wespen", step_3: "Zürich", step_4: "dringend" },
    });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    if (host === "infomaniak-de") {
      expect(r.data.service).toBe("wespen");
      expect(r.data.city).toBe("Zürich");
      expect(r.data.urgency).toBe("dringend");
    } else {
      expect(r.data.service).toBeUndefined();
      expect(r.data.city).toBeUndefined();
    }
  });

  it("validation language — DE messages only when bilingual (infomaniak-de)", () => {
    const r = normalizeLegacyLeadBody(
      { name: "A", phone: "1" },
      { host: "helvetic-garten.ch", default_language: "de" },
    );
    expect(r.ok).toBe(false);
    if (host === "infomaniak-de") {
      expect(r.error).toMatch(/Ungültige/);
      expect(r.fieldErrors.telephone[0]).toMatch(/Telefon/);
    } else {
      expect(r.error).toBe("Données invalides");
      expect(r.fieldErrors.telephone[0]).toMatch(/Téléphone/);
    }
  });

  it("default_language override from ctx", () => {
    const r = normalizeLegacyLeadBody(
      { ...BASE },
      { host: "example.ch", default_language: "de" },
    );
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    // body site_language only wins on IK-DE
    expect(r.data.site_language).toBe("de");
  });

  it("explicit site_language in body — only infomaniak-de", () => {
    const r = normalizeLegacyLeadBody(
      { ...BASE, site_language: "fr" },
      { host: "helvetic-garten.ch", default_language: "de" },
    );
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    if (host === "infomaniak-de") expect(r.data.site_language).toBe("fr");
    else expect(r.data.site_language).toBe("de"); // override from ctx wins without body read
  });
});
