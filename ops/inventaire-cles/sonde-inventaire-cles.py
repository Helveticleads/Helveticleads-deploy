#!/usr/bin/env python3
"""Inventaire DEPLOY_SSH_KEY — trois sources, noms seulement (jamais de valeur)."""
from __future__ import annotations

import base64
import json
import os
import re
import subprocess
import sys
from pathlib import Path

DIR = Path(__file__).resolve().parent
OWNER = os.environ.get("OWNER", "Helveticleads")
DECLARES_FILE = Path(os.environ.get("DECLARES_FILE", DIR / "depots-declares.txt"))
SECRETS_DECLARES_FILE = Path(
    os.environ.get("SECRETS_DECLARES_FILE", DIR / "secrets-declares.txt")
)


def gh_json(args: list[str]) -> object | None:
    try:
        out = subprocess.check_output(["gh", "api", *args], text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return None
    if not out.strip():
        return None
    return json.loads(out)


def gh_text(args: list[str]) -> str:
    try:
        return subprocess.check_output(["gh", "api", *args], text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return ""


def load_secret_name() -> str:
    env = os.environ.get("SECRET_NAME", "").strip()
    if env:
        return env
    for line in SECRETS_DECLARES_FILE.read_text().splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        return s
    raise SystemExit("SECRET_NAME vide")


def load_declared() -> list[str]:
    out: list[str] = []
    for line in DECLARES_FILE.read_text().splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        name = s.split("/")[-1]
        out.append(name)
    return out


def list_repos() -> list[str]:
    # Compte personnel : `gh repo list` couvre public+privé ; users/OWNER/repos
    # ne rend souvent qu'un sous-ensemble et fausse l'inventaire.
    try:
        out = subprocess.check_output(
            [
                "gh",
                "repo",
                "list",
                OWNER,
                "--limit",
                "300",
                "--json",
                "name",
                "--jq",
                ".[].name",
            ],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        names = [n for n in out.splitlines() if n.strip()]
        if names:
            return names
    except subprocess.CalledProcessError:
        pass
    raw = gh_text(["--paginate", f"users/{OWNER}/repos", "--jq", ".[].name"])
    return [n for n in raw.splitlines() if n.strip()]


def uses_secret(name: str, secret_name: str) -> bool:
    lit = re.compile(
        rf"secrets\.{re.escape(secret_name)}|secrets\[['\"]{re.escape(secret_name)}['\"]\]"
    )
    shared = re.compile(
        r"Helveticleads-deploy/\.github/workflows/(deploy-infomaniak|deploy-vite-standalone)\.yml@"
    )
    # Helveticleads-deploy DÉFINIT les workflows réutilisables : la référence
    # secrets.DEPLOY_SSH_KEY y figure, mais le secret est lu chez l'appelant.
    # On ne le compte comme « utilise » que s'il s'appelle lui-même en caller.
    listing = gh_json([f"repos/{OWNER}/{name}/contents/.github/workflows"])
    if not isinstance(listing, list):
        return False
    for ent in listing:
        fn = ent.get("name") or ""
        if not (fn.endswith(".yml") or fn.endswith(".yaml")):
            continue
        if name == "Helveticleads-deploy" and fn in (
            "deploy-infomaniak.yml",
            "deploy-vite-standalone.yml",
        ):
            continue
        raw = gh_text(
            [f"repos/{OWNER}/{name}/contents/.github/workflows/{fn}", "--jq", ".content"]
        )
        if not raw.strip():
            continue
        try:
            text = base64.b64decode(raw.strip()).decode()
        except Exception:
            continue
        if lit.search(text):
            return True
        if secret_name == "DEPLOY_SSH_KEY" and shared.search(text):
            return True
    return False


def carries_secret(name: str, secret_name: str) -> str | None:
    """Retourne updated_at si le dépôt porte le secret, sinon None. Jamais la valeur."""
    data = gh_json([f"repos/{OWNER}/{name}/actions/secrets"])
    if not isinstance(data, dict):
        return None
    for s in data.get("secrets") or []:
        if s.get("name") == secret_name:
            return s.get("updated_at") or "?"
    return None


def main() -> int:
    secret_name = load_secret_name()
    declared = load_declared()
    declared_set = set(declared)
    all_repos = list_repos()

    uses: set[str] = set()
    carries: dict[str, str] = {}

    for name in all_repos:
        if uses_secret(name, secret_name):
            uses.add(name)
        updated = carries_secret(name, secret_name)
        if updated is not None:
            carries[name] = updated

    utilise_pas_porte = sorted(uses - set(carries))
    porte_pas_utilise = sorted(set(carries) - uses)
    declare_ni = sorted(
        n for n in declared if n not in uses and n not in carries
    )

    print(f"Sonde inventaire — secret **nommé** `{secret_name}` (aucune valeur).")
    print(f"Dépôts scannés : {len(all_repos)} · déclarés : {len(declared)}")
    print()

    print(f"## utilise mais ne porte pas ({len(utilise_pas_porte)})")
    if not utilise_pas_porte:
        print("(vide)")
    else:
        for n in utilise_pas_porte:
            print(f"- {OWNER}/{n}")
    print()

    print(f"## porte mais n'utilise pas ({len(porte_pas_utilise)})")
    if not porte_pas_utilise:
        print("(vide)")
    else:
        for n in porte_pas_utilise:
            print(f"- {OWNER}/{n} (maj {carries[n]})")
    print()

    print(f"## déclaré mais ni l'un ni l'autre ({len(declare_ni)})")
    if not declare_ni:
        print("(vide)")
    else:
        for n in declare_ni:
            print(f"- {OWNER}/{n}")
    print()

    print(f"## porte — dates de mise à jour ({len(carries)})")
    for n in sorted(carries):
        print(f"- {OWNER}/{n} · updated_at={carries[n]}")
    print()

    # Quatre nouveaux sites nuisibles (repère pour le compte rendu)
    quatre = [
        "FR-helvetique-guepes-et-frelons.ch",
        "FR-helvetique-pro-nuisibles.ch",
        "FR-helvetique-punaise-de-lit.ch",
        "FR-helvetique-rongeurs.ch",
    ]
    print("## focus quatre sites nuisibles")
    for n in quatre:
        u = n in uses
        c = n in carries
        print(
            f"- {OWNER}/{n} · utilise={'oui' if u else 'non'} · porte={'oui' if c else 'non'}"
            + (f" · updated_at={carries[n]}" if c else "")
        )
    print()

    print("```")
    print(f"secret_name={secret_name}")
    print(f"n_scannes={len(all_repos)}")
    print(f"n_declares={len(declared)}")
    print(f"n_utilise={len(uses)}")
    print(f"n_porte={len(carries)}")
    print(f"n_utilise_mais_ne_porte_pas={len(utilise_pas_porte)}")
    print(f"n_porte_mais_nutilise_pas={len(porte_pas_utilise)}")
    print(f"n_declare_mais_ni_lun_ni_lautre={len(declare_ni)}")
    print(f"n_declares_hors_scan={len(declared_set - set(all_repos))}")
    print("```")
    return 0


if __name__ == "__main__":
    sys.exit(main())
