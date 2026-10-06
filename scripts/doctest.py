#!/usr/bin/env python3
"""
doctest.py — verifie que les blocs `heaven>` du book s'executent sans
erreur d'evaluation.

Pour chaque .md du book :
  1. Extrait les lignes `    heaven> CMD` (indent 4 espaces).
  2. Les rejoue dans une session `heaven repl` fraiche (une par
     fichier : les definitions persistent au sein d'un fichier,
     pas entre fichiers).
  3. Cherche `[eval error]`, `[EVAL ERROR]`, `error.` dans la
     sortie (marqueurs de vraies erreurs).
  4. Ne signale PAS `✗` seul : le book l'utilise parfois pour des
     erreurs pedagogiques attendues (ex: pattern incompatible).

Usage :
    python3 scripts/doctest.py                    # tous les .md
    python3 scripts/doctest.py docs/book/src/04-recursion.md
    python3 scripts/doctest.py --check            # CI : exit 1 si erreur
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

BOOK_DIR = Path("docs/book/src")
HEAVEN_BIN = "./zig-out/bin/heaven"

# Ligne `    heaven> commande` (indent >= 4 espaces)
CMD_RE = re.compile(r'^    heaven>\s?(.*)$')

# Marqueurs de vraie erreur d'evaluation.
ERROR_PATTERNS = ("[eval error]", "[EVAL ERROR]", "error.")


def extract_commands(md_path):
    """Extrait les commandes `heaven> X`. Une commande est skip si
    elle est precede (directement ou a quelques lignes) du marqueur
    HTML `<!-- doctest: skip -->`. Si le fichier contient
    `<!-- doctest: skip-file -->`, aucune commande n'est extraite."""
    content = md_path.read_text()
    if '<!-- doctest: skip-file -->' in content:
        return []
    cmds = []
    lines = content.splitlines()
    skip_next = False
    for i, line in enumerate(lines):
        # Cherche une directive skip qui precede une commande
        if '<!-- doctest: skip' in line:
            skip_next = True
        m = CMD_RE.match(line)
        if m:
            if not skip_next:
                cmds.append(m.group(1))
            else:
                # Note : on ne reinitialise PAS skip_next ici -- un
                # skip peut couvrir plusieurs lignes consecutives.
                # Il faut un marqueur `<!-- /doctest -->` pour reprendre.
                pass
        elif '<!-- /doctest -->' in line:
            skip_next = False
    return cmds


def run_session(commands, timeout=30):
    """Un seul subprocess pour tout le fichier (les definitions
    persistent). Chaque erreur est associee a la commande a laquelle
    elle correspond en comptant les prompts `heaven>` avant elle."""
    if not commands:
        return None
    inp = "\n".join(commands) + "\n"
    try:
        r = subprocess.run(
            [HEAVEN_BIN, "repl"],
            input=inp,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return ("TIMEOUT", [(0, commands[0], "TIMEOUT")])
    except FileNotFoundError:
        print(f"Erreur : {HEAVEN_BIN} introuvable. Lance `zig build` d'abord.")
        sys.exit(2)
    out = r.stdout + r.stderr
    lines = out.splitlines()
    errors = []
    # Compte les `heaven>` : chaque prompt marque le debut d'une commande.
    # On associe chaque erreur a l'index du prompt le plus proche avant.
    cmd_idx = 0
    seen_prompts = 0
    for line in lines:
        if "heaven>" in line:
            seen_prompts += 1
            cmd_idx = seen_prompts - 1
        elif any(p in line for p in ERROR_PATTERNS):
            if cmd_idx < len(commands):
                errors.append((cmd_idx, commands[cmd_idx], line))
    return (out, errors)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*", help="Fichiers .md (defaut: tous)")
    ap.add_argument("--check", action="store_true",
                    help="Exit 1 si au moins une erreur detectee")
    ap.add_argument("--verbose", action="store_true",
                    help="Affiche l'output complet en cas d'erreur")
    args = ap.parse_args()

    targets = ([Path(f) for f in args.files] if args.files
               else sorted(BOOK_DIR.glob("*.md")))

    total_cmds = 0
    total_errors = 0
    failed_files = []

    for md in targets:
        if not md.exists():
            print(f"SKIP {md} (absent)")
            continue
        cmds = extract_commands(md)
        if not cmds:
            continue
        total_cmds += len(cmds)
        res = run_session(cmds)
        if res is None:
            continue
        out, errors = res
        if out == "TIMEOUT":
            print(f"✗ {md.name} : TIMEOUT ({len(cmds)} cmd)")
            failed_files.append(md.name)
            total_errors += 1
            continue
        if errors:
            print(f"✗ {md.name} : {len(errors)} erreur(s) sur {len(cmds)} cmd")
            out_lines = out.splitlines()
            for err in errors[:10]:
                # err peut etre tuple ou ligne selon la version
                if isinstance(err, tuple):
                    msg = err[2]
                else:
                    msg = err
                # Trouve la ligne dans out_lines et affiche 4 lignes de contexte
                for i, line in enumerate(out_lines):
                    if msg in line:
                        ctx = out_lines[max(0, i-4):i+1]
                        print(f"     ---")
                        for l in ctx:
                            marker = ">>>" if msg in l else "   "
                            print(f"     {marker} {l}")
                        break
            if args.verbose:
                print("  Output complet :")
                print("  " + "\n  ".join(out.splitlines()))
            failed_files.append(md.name)
            total_errors += len(errors)
        else:
            print(f"✓ {md.name} : {len(cmds)} cmd OK")

    print()
    print(f"Total : {total_cmds} commandes, {total_errors} erreur(s)")
    if failed_files:
        print(f"Fichiers en echec : {', '.join(failed_files)}")
        if args.check:
            sys.exit(1)
    else:
        print("Tous les doctests passent.")


if __name__ == "__main__":
    main()
