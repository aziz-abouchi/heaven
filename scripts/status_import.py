#!/usr/bin/env python3
"""Importe docs/STATUS.md vers docs/status.json.

Approche simple : chaque section (## ou ###) est "table" si elle
contient au moins une ligne de tableau. Sinon "raw".

Une section table peut avoir des lignes texte avant/apres le
tableau ; elles sont ignorees (trailing_text).
"""
import json
from datetime import date
import re
from pathlib import Path

STATUS_MD = Path("docs/STATUS.md")
STATUS_JSON = Path("docs/status.json")

TIER_MAP = {
    "✅": "stable", "⚠️": "partiel", "🚧": "roadmap", "❌": "absent",
    "stable": "stable", "partiel": "partiel",
    "roadmap": "roadmap", "absent": "absent",
}


def parse_tier(cell):
    for k, v in TIER_MAP.items():
        if k in cell:
            return v
    return cell


def parse_row(line):
    raw = line.strip()
    if not raw.startswith("|") or not raw.endswith("|"):
        return None
    parts = [p.strip() for p in re.split(r"(?<!\\)\|", raw[1:-1])]
    return parts if 2 <= len(parts) <= 4 else None


def is_separator(line):
    return bool(re.match(r"^\|[\s\-:|]+\|$", line))


def is_table_header(line):
    l = line.lower()
    return (l.startswith("| élément ") or l.startswith("| element ")
            or l.startswith("| élément ") or l.startswith("| module "))


def unesc(s):
    return s.replace("\\|", "|")


def make_id(title):
    return re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")


def main():
    md = STATUS_MD.read_text()
    lines = md.splitlines()

    sections = []
    cur = None

    def flush():
        nonlocal cur
        if cur is None:
            return
        has_table = any(l.startswith("|") for l in cur["body"] if not is_separator(l))
        if has_table:
            features = []
            n_cols = 4  # par defaut
            first_table_seen = False
            for l in cur["body"]:
                if is_separator(l):
                    continue
                if is_table_header(l):
                    # Detecter le nombre de colonnes du header
                    hdr = [x.strip() for x in l.strip()[1:-1].split("|")]
                    n_cols = len(hdr)
                    first_table_seen = True
                    continue
                if not l.startswith("|"):
                    continue
                row = parse_row(l)
                if row is None:
                    continue
                # Pad a 4 colonnes
                if len(row) == 3:
                    row = [row[0], row[1], row[2], "—"]
                elif len(row) == 2:
                    row = [row[0], row[1], "—", "—"]
                features.append({
                    "name": unesc(row[0]),
                    "tier": parse_tier(row[1]),
                    "proof": unesc(row[2]),
                    "limit": unesc(row[3]),
                })
            # Stocke n_cols pour le generateur
            cur["_n_cols"] = n_cols
            # leading_text : lignes texte avant le 1er tableau
            leading = []
            seen_any_table = False
            for l in cur["body"]:
                if l.startswith("|") or is_separator(l):
                    seen_any_table = True
                    break
                if l.strip():
                    leading.append(l)
            # trailing_text : lignes texte apres le dernier tableau
            trailing = []
            seen_table = False
            for l in cur["body"]:
                if l.startswith("|") or is_separator(l):
                    seen_table = True
                    trailing = []
                elif seen_table and l.strip():
                    trailing.append(l)
            sec = {
                "level": cur["level"],
                "kind": "table",
                "id": make_id(cur["title"]),
                "title": cur["title"],
                "n_cols": cur.get("_n_cols", 4),
                "features": features,
            }
            if leading:
                sec["leading_text"] = "\n".join(leading).strip()
            if trailing:
                sec["trailing_text"] = "\n".join(trailing).strip()
            sections.append(sec)
        else:
            content = "\n".join(cur["body"]).strip()
            content = re.sub(r"^-{3,}\s*$", "", content, flags=re.MULTILINE).strip()
            if content:
                sections.append({
                    "level": cur["level"],
                    "kind": "raw",
                    "title": cur["title"],
                    "content": content,
                })
        cur = None

    for line in lines:
        m = re.match(r"^(#{2,3}) (.+)$", line)
        if m:
            flush()
            cur = {"level": len(m.group(1)), "title": m.group(2).strip(), "body": []}
            continue
        if cur is None:
            continue
        cur["body"].append(line)

    flush()

    data = {"updated": date.today().isoformat(), "sections": sections}
    STATUS_JSON.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    n_t = sum(1 for s in sections if s["kind"] == "table")
    n_r = sum(1 for s in sections if s["kind"] == "raw")
    n_f = sum(len(s["features"]) for s in sections if s["kind"] == "table")
    print(f"OK : {len(sections)} sections ({n_t} tables, {n_r} raw), {n_f} features")


if __name__ == "__main__":
    main()
