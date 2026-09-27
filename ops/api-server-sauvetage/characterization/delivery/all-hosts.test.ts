import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { activeHosts, charTarget, type HostId } from "../support/hosts";
import { loadDeliverLead, loadIkDeWebhook } from "../support/load";

type Lead = {
  lead_id: string;
  site_language: "fr" | "de";
  source_site: string;
  source_page: string;
  form_type: string;
  name: string;
  phone: string;
  created_at: string;
};

function sampleLead(): Lead {
  return {
    lead_id: "11111111-1111-1111-1111-111111111111",
    site_language: "fr",
    source_site: "https://helvetique-jardin.ch",
    source_page: "/",
    form_type: "lead",
    name: "Ada Lovelace",
    phone: "0791234567",
    created_at: new Date().toISOString(),
  };
}

const DELIVER_HOSTS = activeHosts().filter((h) => h !== "infomaniak-de");

describe.each(DELIVER_HOSTS)("delivery deliverLead · %s", (host: HostId) => {
  let deliverLead: (lead: Lead, ctx?: { host?: string }) => Promise<any>;
  let fetches: { url: string; method: string; body?: string }[];
  let tmp: string;

  beforeEach(async () => {
    fetches = [];
    tmp = mkdtempSync(join(tmpdir(), "crm-sent-"));
    process.env.CRM_SENT_DIR = tmp;
    process.env.CRM_SITE_TOKENS_FILE = join(tmp, "tokens.json");
    delete process.env.RESEND_API_KEY;
    delete process.env.CRM_WEBHOOK_URL;
    delete process.env.CRM_PUSH_ENABLED;
    delete process.env.CRM_PUSH_KEY;
    delete process.env.CRM_TRACK_URL;
    delete process.env.FROM_EMAIL;

    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
        const url = String(input);
        fetches.push({
          url,
          method: (init?.method ?? "GET").toUpperCase(),
          body: typeof init?.body === "string" ? init.body : undefined,
        });
        if (url.includes("api.resend.com")) {
          return new Response(JSON.stringify({ id: "re_test" }), { status: 200 });
        }
        if (url.includes("/api/leads/track-tokens")) {
          return new Response(
            JSON.stringify({ tokens: { "helvetique-terrassement.ch": "hl_testtoken" } }),
            { status: 200 },
          );
        }
        if (url.includes("/api/leads/track")) {
          return new Response(JSON.stringify({ success: true, lead_id: 42 }), {
            status: 200,
          });
        }
        return new Response(JSON.stringify({ ok: true }), { status: 200 });
      }),
    );

    const mod = await loadDeliverLead(host);
    if (!mod) throw new Error("expected deliverLead");
    deliverLead = mod.deliverLead as typeof deliverLead;
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
    rmSync(tmp, { recursive: true, force: true });
  });

  it("fails when no channel configured", async () => {
    const r = await deliverLead(sampleLead());
    expect(r.delivered).toBe(false);
    expect(r.channels).toEqual([]);
  });

  it("sends email via Resend when RESEND_API_KEY set — first channel", async () => {
    process.env.RESEND_API_KEY = "re_test_key_xxxxxxxxxxxxxxxxxxxx";
    process.env.FROM_EMAIL = "Leads <noreply@example.com>";
    process.env.LEAD_CENTRAL_EMAIL = "central@example.com";
    const r = await deliverLead(sampleLead(), { host: "helvetique-jardin.ch" });
    expect(r.delivered).toBe(true);
    expect(r.channels[0]).toBe("email");
    expect(fetches.some((f) => f.url.includes("api.resend.com"))).toBe(true);
  });

  it("legacy CRM_WEBHOOK_URL (non-track) — channel webhook after email", async () => {
    process.env.RESEND_API_KEY = "re_test_key_xxxxxxxxxxxxxxxxxxxx";
    process.env.FROM_EMAIL = "Leads <noreply@example.com>";
    process.env.CRM_WEBHOOK_URL = "https://hooks.example.com/legacy";
    const r = await deliverLead(sampleLead());
    expect(r.delivered).toBe(true);
    expect(r.channels).toContain("email");
    expect(r.channels).toContain("webhook");
    const order = fetches.map((f) => f.url);
    const emailIdx = order.findIndex((u) => u.includes("resend"));
    const whIdx = order.findIndex((u) => u.includes("hooks.example.com"));
    expect(emailIdx).toBeGreaterThanOrEqual(0);
    expect(whIdx).toBeGreaterThan(emailIdx);
  });

  it("CRM push track — only ionos activates with CRM_PUSH_ENABLED", async () => {
    process.env.RESEND_API_KEY = "re_test_key_xxxxxxxxxxxxxxxxxxxx";
    process.env.FROM_EMAIL = "Leads <noreply@example.com>";
    process.env.CRM_PUSH_ENABLED = "true";
    process.env.CRM_PUSH_KEY = "x".repeat(64);
    process.env.CRM_WEBHOOK_URL = "https://crm.example.com/api/leads/track";
    const r = await deliverLead(sampleLead(), {
      host: "helvetique-terrassement.ch",
    });
    expect(r.delivered).toBe(true);
    const trackCalls = fetches.filter((f) => f.url.endsWith("/api/leads/track"));
    if (host === "ionos") {
      expect(r.channels).toContain("crm");
      expect(trackCalls.length).toBeGreaterThan(0);
      expect(r.crm_lead_id).toBe(42);
    } else {
      expect(r.channels).not.toContain("crm");
      if (charTarget() === "reconciled") {
        // profile: CRM push off; track URL excluded from legacy webhook
        expect(trackCalls.length).toBe(0);
      } else {
        // extract: CRM_WEBHOOK_URL (même track) part en webhook générique
        expect(r.channels).toContain("webhook");
      }
    }
  });

  it("email failure with only Resend → not delivered", async () => {
    process.env.RESEND_API_KEY = "re_test_key_xxxxxxxxxxxxxxxxxxxx";
    process.env.FROM_EMAIL = "Leads <noreply@example.com>";
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("nope", { status: 500 })),
    );
    const r = await deliverLead(sampleLead());
    expect(r.delivered).toBe(false);
    expect(r.channels).toEqual([]);
  });
});

describe("delivery webhook · infomaniak-de", () => {
  it("sendLeadWebhook no-ops when LEADS_WEBHOOK_URL empty (production)", async () => {
    if (!activeHosts().includes("infomaniak-de")) return;
    delete process.env.LEADS_WEBHOOK_URL;
    process.env.LEADS_WEBHOOK_URL = "";
    const mod = await loadIkDeWebhook();
    const r = await mod.sendLeadWebhook(sampleLead());
    expect(r.sent).toBe(false);
    expect(r.error).toBe("WEBHOOK_URL_MISSING");
  });

  it("sendLeadWebhook POSTs when URL set", async () => {
    if (!activeHosts().includes("infomaniak-de")) return;
    process.env.LEADS_WEBHOOK_URL = "https://hooks.example.com/leads";
    process.env.LEADS_WEBHOOK_SECRET = "secret";
    const calls: string[] = [];
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        calls.push(String(input));
        return new Response("ok", { status: 200 });
      }),
    );
    const mod = await loadIkDeWebhook();
    const r = await mod.sendLeadWebhook(sampleLead());
    expect(r.sent).toBe(true);
    expect(calls[0]).toContain("hooks.example.com/leads");
    vi.unstubAllGlobals();
  });
});
