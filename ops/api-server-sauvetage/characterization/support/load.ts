import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import type { HostId } from "./hosts";
import { charTarget } from "./hosts";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

function bust(url: string, host: HostId) {
  return `${url}?h=${host}&t=${Date.now()}`;
}

export async function loadNormalize(host: HostId) {
  if (charTarget() === "extract") {
    const href = pathToFileURL(
      path.join(root, "from-hosts", host, "lead-core/src/normalize.ts"),
    ).href;
    const mod = await import(bust(href, host));
    return mod as { normalizeLegacyLeadBody: Function };
  }
  const { setActiveHostProfile } = await import(
    pathToFileURL(path.join(root, "reconciled/src/config/runtime.ts")).href
  );
  setActiveHostProfile(host);
  const href = pathToFileURL(
    path.join(root, "reconciled/lead-core/src/normalize.ts"),
  ).href;
  const mod = await import(bust(href, host));
  return mod as { normalizeLegacyLeadBody: Function };
}

export async function loadDeliverLead(host: HostId) {
  if (host === "infomaniak-de" && charTarget() === "extract") {
    return null;
  }
  if (charTarget() === "extract") {
    const href = pathToFileURL(
      path.join(root, "from-hosts", host, "src/services/deliver-lead.ts"),
    ).href;
    const mod = await import(bust(href, host));
    return mod as { deliverLead: Function };
  }
  const { setActiveHostProfile } = await import(
    pathToFileURL(path.join(root, "reconciled/src/config/runtime.ts")).href
  );
  setActiveHostProfile(host);
  const href = pathToFileURL(
    path.join(root, "reconciled/src/services/deliver-lead.ts"),
  ).href;
  const mod = await import(bust(href, host));
  return mod as { deliverLead: Function };
}

export async function loadIkDeWebhook() {
  if (charTarget() === "extract") {
    const href = pathToFileURL(
      path.join(root, "from-hosts/infomaniak-de/src/lib/webhook.ts"),
    ).href;
    return import(bust(href, "infomaniak-de"));
  }
  const { setActiveHostProfile } = await import(
    pathToFileURL(path.join(root, "reconciled/src/config/runtime.ts")).href
  );
  setActiveHostProfile("infomaniak-de");
  const href = pathToFileURL(
    path.join(root, "reconciled/src/lib/webhook.ts"),
  ).href;
  return import(bust(href, "infomaniak-de"));
}

export async function loadLeadsRouter(host: HostId) {
  if (charTarget() === "extract") {
    const href = pathToFileURL(
      path.join(root, "from-hosts", host, "src/routes/leads.ts"),
    ).href;
    const mod = await import(bust(href, host));
    return mod.default;
  }
  const { setActiveHostProfile } = await import(
    pathToFileURL(path.join(root, "reconciled/src/config/runtime.ts")).href
  );
  setActiveHostProfile(host);
  const href = pathToFileURL(
    path.join(root, "reconciled/src/routes/leads.ts"),
  ).href;
  const mod = await import(bust(href, host));
  return mod.default;
}
