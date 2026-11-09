# Docs vs code — état vérifié au 2026-11-09

> Niveaux de preuve : S0 doc seule / S1 code présent / S2 chemin
> d'exécution identifié / S3 test automatisé / S4 test exécuté et réussi.
> Sessions 33-37 : claims testés sur binaire `./zig-out/bin/heaven`.

## Faits figés (2026-11-09)

- **176 fichiers `.hvn`** scannés par `test_all_hvn.py` (147 assertions).
- **1467 assertions** au total (somme `Total: n/n` par fichier).
- **4 fichiers skipped** (`test_selfparse.hvn.skip`, `test_parser.hvn.skip`, + 2 skip de `tests/diff/`).

## Claims VÉRIFIÉS (S3/S4)

| Claim (STATUS.md ou doc) | Réalité | Niveau | Preuve |
|---|---|---|---|
| 1446 tests Heaven | **176 fichiers / 1467 assertions** | S4 | `test_all_hvn.py` |
| Thunks top-level cassés | ✅ **RÉSOLU** (`9a301c7`) | S4 | `xyz = 3; xyz == 3` → 2/2 |
| `heaven check` = stub | ✅ **S2** : exit 1 sur invalide, 0 sur valide | S4 | `check valid.hvn` rc=0, `check @@@.hvn` rc=1 |
| MIR bool = 0 | ✅ **Fixé** `8511c02` : `true → 1`, `false → 0` | S4 | `tests/diff/06-mutual` OK |
| QTT érasure absente | ⚠️ **Partiel** `6534b58` + audit : `(let erased …)` skip bind | S3 | `tests/qtt/erased_runtime.hvn` 4/4 |
| QTT multiplicités au parse | ✅ `expr_parser.zig:774` (`countSymUses`) | S3 | `tests/qtt/let_quantities_{ok,viol}.hvn` |
| Suite diff interp == QBE | ✅ 7/7 OK (3 skip QBE-limited) | S4 | `tests/diff/run.sh` |

## Claims CORRIGÉS dans STATUS.md (commit `e58c532`)

| Claim (avant) | Réalité (après) |
|---|---|
| `canonEqStr` (stub) | Appelle `structuralEql` (`canon.zig:234`) |
| `kernel.zig` (~780 L) | `src/kernel/` 2855 l. (kernel 41, peano 1973, typechecker 205) |
| `7 tests dans kernel.zig` | 33 tests dans `src/kernel/` (0 dans kernel.zig) |
| Types quotients ❌ | Partiel : `test_quotient.zig` existe |
| Proof irrelevance ❌ | Partiel : `test_proof_irrelevance.zig` existe |
| TLS/T1 « à faire » | `tls.zig` (122 l.) + `https.hvn` (24 l.) existent |

## Claims encore NON vérifiés (S0/S1)

| Claim | Source | À faire |
|---|---|---|
| Documentation QTT « ❌ absent du book » | STATUS.md:125 | `docs/book/src-v2/26-qtt.md` et `29-memoire.md` existent |
| Acteurs « séquentiel » | STATUS.md:185 | Mailbox multi-msg testée (`test_actor_multi_msg.hvn` 5 msgs = 15) |
| `hkt-v1b` en priorité | STATUS.md:316 | Dans `sections[].content` ligne 1080 de `status.json` |
| Date `updated: 2026-11-05` | STATUS.md:3 | À passer au 2026-11-09 |
| `COMMANDS.md` : 13 commandes manquantes | audit | Voir `src/main.zig` + `commands.zig` |

## Limitations documentées (S4)

| Prog | interp | QBE | Cause |
|---|---|---|---|
| `08-pair` | `(pair 1 2)` | pointeur brut | limitation QBE (ASLR) |
| `09-string` | `"helloworld"` | `QBE_NO_BIN` | strings non supportées MIR |
| `10-closure` | lambda | `QBE_NO_BIN` | closures non supportées MIR |
| `tests/diff/11-color.hvn` | `Green` | `0` | **Bug MIR général ctor 0-arity** (session 38) |

## Leak identifié

| Constat | Impact |
|---|---|
| `fn` déclaration = 8 bytes/fn | Négligeable (1000 fn = 8 KB), non localisé |

## Référence audit externe

Une session externe a produit 28 lignes (11 stale, 8 contradictoires, 6 non
appliqués, 2 à confirmer, 1 exact). **Le tableau complet n'est pas dans ce
repo.** Sessions 33-37 ont tranché 7 de ces claims (voir ci-dessus). Les 21
lignes restantes sont perdues — à re-faire si nécessaire.
