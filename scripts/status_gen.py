#!/usr/bin/env python3
"""Genere docs/STATUS.md depuis docs/status.json."""
import argparse
import json
import sys
from pathlib import Path

STATUS_MD = Path("docs/STATUS.md")
STATUS_JSON = Path("docs/status.json")
TIER_EMOJI = {"stable": "✅", "partiel": "⚠️", "roadmap": "🚧", "absent": "❌"}


def esc(s: str) -> str:
    return s.replace("|", "\\|")


def gen(data):
    out = []
    out.append("# Heaven — Statut des fonctionnalités\n")
    out.append(f"Dernière mise à jour : {data['updated']}\n")
    out.append("Ce document est **genere** depuis `docs/status.json` par")
    out.append("`scripts/status_gen.py`. Ne pas editer a la main.\n")
    out.append("Légende :")
    out.append("- ✅ **stable** — implémenté, testé, comportement fiable")
    out.append("- ⚠️ **partiel** — implémenté, limitations connues")
    out.append("- 🚧 **roadmap** — non implémenté, spec existe (voir `ROADMAP.md`)")
    out.append("- ❌ **absent** — non implémenté, aucune spec\n")

    # En-tete termine : un seul ---
    out.append("---\n")
    for s in data["sections"]:
        prefix = "##" if s["level"] == 2 else "###"
        out.append(f"{prefix} {s['title']}\n")
        if s["kind"] == "raw":
            out.append(s["content"])
            out.append("")
            continue
        if not s["features"]:
            out.append("(pas de tableau)\n")
            continue
        if s.get("leading_text"):
            out.append(s["leading_text"])
            out.append("")
        n_cols = s.get("n_cols", 4)
        if n_cols == 3:
            out.append("| Élément | Statut | Note |")
            out.append("|---|---|---|")
            for f in s["features"]:
                emoji = TIER_EMOJI.get(f["tier"], f["tier"])
                out.append(f"| {esc(f['name'])} | {emoji} | {esc(f['proof'])} |")
        else:
            out.append("| Élément | Statut | Preuve | Limitation |")
            out.append("|---|---|---|---|")
            for f in s["features"]:
                emoji = TIER_EMOJI.get(f["tier"], f["tier"])
                out.append(f"| {esc(f['name'])} | {emoji} | {esc(f['proof'])} | {esc(f['limit'])} |")
        out.append("")
        if s.get("trailing_text"):
            out.append(s["trailing_text"])
            out.append("")

    return "\n".join(out).rstrip() + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    data = json.loads(STATUS_JSON.read_text())
    generated = gen(data)
    current = STATUS_MD.read_text() if STATUS_MD.exists() else ""
    if current == generated:
        print("OK : STATUS.md a jour")
        return
    if args.check:
        print("✗ STATUS.md divergent de status.json", file=sys.stderr)
        sys.exit(1)
    STATUS_MD.write_text(generated)
    print("OK : STATUS.md regenere")


if __name__ == "__main__":
    main()
