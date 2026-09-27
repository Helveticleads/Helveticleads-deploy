export const HOSTS = [
  "hetzner",
  "lws",
  "infomaniak-fr",
  "infomaniak-de",
  "ionos",
] as const;

export type HostId = (typeof HOSTS)[number];

export function activeHosts(): HostId[] {
  const filter = process.env.CHAR_HOST as HostId | undefined;
  if (filter) {
    if (!HOSTS.includes(filter)) throw new Error(`Unknown CHAR_HOST=${filter}`);
    return [filter];
  }
  return [...HOSTS];
}

export function charTarget(): "extract" | "reconciled" {
  const t = process.env.CHAR_TARGET ?? "extract";
  if (t !== "extract" && t !== "reconciled") {
    throw new Error(`CHAR_TARGET must be extract|reconciled, got ${t}`);
  }
  return t;
}
