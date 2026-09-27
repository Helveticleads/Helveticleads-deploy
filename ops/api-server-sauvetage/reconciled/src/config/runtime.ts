import { PROFILES, type HostProfile } from "./profiles";

let active: HostProfile = PROFILES.hetzner;

export function setActiveHostProfile(id: string): HostProfile {
  const p = PROFILES[id];
  if (!p) throw new Error(`Unknown host profile: ${id}`);
  active = p;
  return active;
}

export function getActiveHostProfile(): HostProfile {
  return active;
}
