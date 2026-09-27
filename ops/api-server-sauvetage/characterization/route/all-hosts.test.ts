import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import express from "express";
import request from "supertest";
import { activeHosts, type HostId } from "../support/hosts";
import { loadLeadsRouter } from "../support/load";

function appWith(router: express.Router) {
  const app = express();
  app.use(express.json());
  app.use("/api", router);
  return app;
}

describe.each(activeHosts())("route /leads · %s", (host: HostId) => {
  let app: express.Express;

  beforeEach(async () => {
    delete process.env.RESEND_API_KEY;
    delete process.env.FROM_EMAIL;
    delete process.env.LEAD_CENTRAL_EMAIL;
    delete process.env.LEADS_WEBHOOK_URL;
    delete process.env.CRM_WEBHOOK_URL;
    delete process.env.CRM_PUSH_ENABLED;

    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        if (url.includes("api.resend.com")) {
          return new Response(JSON.stringify({ id: "re_test" }), { status: 200 });
        }
        return new Response(JSON.stringify({ ok: true }), { status: 200 });
      }),
    );

    const router = await loadLeadsRouter(host);
    app = appWith(router);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("honeypot website → silent accept (shape host-specific)", async () => {
    const res = await request(app)
      .post("/api/leads")
      .send({ name: "Ada Lovelace", phone: "0791234567", website: "http://spam" });

    if (host === "infomaniak-de") {
      expect(res.status).toBe(200);
      expect(res.body).toEqual({ success: true });
    } else {
      expect(res.status).toBe(201);
      expect(res.body).toEqual({ ok: true, channels: [] });
    }
  });

  it("ik-de extra honeypot fields", async () => {
    if (host !== "infomaniak-de") return;
    const res = await request(app)
      .post("/api/leads")
      .send({ name: "Ada Lovelace", phone: "0791234567", _hp: "x" });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  it("invalid body → 400, message language/shape host-specific", async () => {
    const res = await request(app).post("/api/leads").send({ name: "A", phone: "1" });
    expect(res.status).toBe(400);
    if (host === "infomaniak-de") {
      expect(res.body.success).toBe(false);
      expect(String(res.body.message)).toMatch(/Ungültige|Données|invalid/i);
    } else {
      expect(res.body.error).toBe("Données invalides");
      expect(res.body.details).toBeTruthy();
    }
  });

  it("valid lead with Resend → success shape", async () => {
    process.env.RESEND_API_KEY = "re_test_key_xxxxxxxxxxxxxxxxxxxx";
    process.env.FROM_EMAIL = "Leads <noreply@example.com>";
    process.env.LEAD_CENTRAL_EMAIL = "central@example.com";
    // IK-DE empty webhook as in production
    process.env.LEADS_WEBHOOK_URL = "";

    const res = await request(app)
      .post("/api/leads")
      .set("Host", host === "infomaniak-de" ? "helvetic-garten.ch" : "helvetique-jardin.ch")
      .send({ name: "Ada Lovelace", phone: "0791234567" });

    if (host === "infomaniak-de") {
      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.lead_id).toBeTruthy();
      expect(res.body.channels).toBeUndefined();
    } else {
      expect(res.status).toBe(201);
      expect(res.body.ok).toBe(true);
      expect(res.body.channels).toContain("email");
      expect(res.body.lead_id).toBeTruthy();
      if (host === "ionos") {
        // express/json omits undefined — crm_lead_id n'apparaît que si CRM a répondu
        expect(res.body.crm_lead_id === undefined || typeof res.body.crm_lead_id === "number").toBe(
          true,
        );
      } else {
        expect("crm_lead_id" in res.body).toBe(false);
      }
    }
  });

  it("missing Resend → 503 (legacy) or ik-de localized 503", async () => {
    const res = await request(app)
      .post("/api/leads")
      .set("Host", "helvetic-garten.ch")
      .send({ name: "Ada Lovelace", phone: "0791234567" });

    if (host === "infomaniak-de") {
      expect(res.status).toBe(503);
      expect(res.body.success).toBe(false);
      expect(String(res.body.message)).toMatch(/E-Mail-Dienst|Service email/);
    } else {
      expect(res.status).toBe(503);
      expect(res.body.error).toBeTruthy();
    }
  });
});
