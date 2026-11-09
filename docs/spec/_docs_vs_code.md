# Docs vs code — claims vérifiés 2026-11-09

> Niveaux de preuve : S0 doc seule / S1 code présent / S2 chemin d'exécution
> identifié / S3 test automatisé / S4 test exécuté et réussi.
> **Sessions 33-36** : claims testés sur binaire `./zig-out/bin/heaven`.

## Claims VÉRIFIÉS (S3/S4)

| Claim (STATUS.md) | Réalité | Niveau | Preuve |
|---|---|---|---|
| 1446 tests Heaven | **176 fichiers `.hvn`, 1467 assertions** | S4 | `test_all_hvn.py` → 176 passed |
| Thunks top-level cassés | ✅ **RÉSOLU** (`9a301c7`) | S4 | `xyz = 3; xyz == 3` → 2/2 |
| `heaven check` = stub | ✅ **S2** : exit 1 sur invalide, 0 sur valide | S4 | `check valid.hvn` rc=0, `check @@@.hvn` rc=1 |

## Claims PARTIELLEMENT vérifiés (S2)

| Claim | Réalité | Niveau |
|---|---|---|
| `data C = C [Int]` casse | Peano OK, array literal KO | S4 |
| WASM produit du binaire | Émet `unreachable`, stdout vide | S4 |
| MIR bool = 0 | ✅ **Fixé** `8511c02` : `true → 1` | S4 |
| QTT enforced | Multiplicités vérifiées au parse (7/7) | S4 |

## Claims NON vérifiés (S0/S1, à auditer session 37)

| Claim | Source | Statut |
|---|---|---|
| `kernel.zig` ~780 lignes | STATUS.md:160 | À vérifier (`src/kernel/` fait 2855 l.) |
| `canonEqStr` = stub | STATUS.md | À vérifier (`canon.zig:234` appellerait `structuralEql`) |
| Quotients = ❌ | STATUS.md:161-162 | À vérifier (`test_quotient.zig` existerait) |
| TLS « à faire » | STATUS.md:200 | À vérifier (`tls.zig`, `https.hvn` existent) |
| `COMMANDS.md` : 13 commandes manquantes | audit | À vérifier |
| `ai "prompt"` doc mais absent | audit | À vérifier |

## Limitations documentées (S4)

| Prog | interp | QBE | Cause |
|---|---|---|---|
| `08-pair` | `(pair 1 2)` | pointeur brut | limitation QBE (ASLR) |
| `09-string` | `"helloworld"` | `QBE_NO_BIN` | strings non supportées MIR |
| `10-closure` | lambda | `QBE_NO_BIN` | closures non supportées MIR |

## Leak identifié

| Constat | Impact |
|---|---|
| `fn` déclaration = 8 bytes/fn | Négligeable (1000 fn = 8 KB), non localisé |

## Référence audit externe

Voir `_docs_vs_code_audit.md` (28 lignes, preuves `fichier:ligne` + actions).
Résumé : 11 stale, 8 contradictoires, 6 non appliqués, 2 à confirmer, 1 exact.

**Sessions 33-36 ont tranché 6 de ces claims** (kernel 41 l., canonEqStr
→ structuralEql, quotients OK, TLS OK, 13 commandes listées, `ai` absent).
