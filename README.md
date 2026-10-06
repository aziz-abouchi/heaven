# Heaven

<!--
  ⚠️  NE PAS ÉDITER LES CHIFFRES ENTRE MARKERS <!-- DOCGEN:xxx --> ... <!-- /DOCGEN -->
  Régénérer via : zig build docgen  (ou python3 scripts/docgen.py)
  Vérifier      : zig build docgen-check  (le CI échoue si périmé)
  Voir PROMPT_CONTINUITE.md section "Convention doc".
-->


Un langage de programmation où tout ce que vous affirmez peut être prouvé,
où le code se compile en natif et en WASM, et dont la direction
architecturale vise une gestion mémoire pilotée par le type system
(QTT) plutôt que par un garbage collector.

Heaven n'est pas un langage de plus. C'est une tentative de faire tenir
ensemble trois choses que les langages modernes séparent : la rigueur d'un
assistant de preuve (Coq, Lean), la légèreté d'un REPL (Lisp, Python), et
une base pour un système d'acteurs (Erlang) — aujourd'hui séquentiel,
distribué à terme.

---

## Pourquoi Heaven ?

1. Un noyau minimal, tout le reste dérivé. Six primitives (lit, sym,
apply, bind, lambda, relation) et rien d'autre. Types dépendants,
tactiques de preuve, effets algébriques, modules, acteurs — tout est
sucre syntaxique abaissé vers ces six primitives avant évaluation. Si
une extension non-abaissée atteint l'évaluateur, il la rejette.

2. Preuves et programmes dans le même fichier. Pas de DSL externe pour
prouver, pas de commentaire magique. Vous écrivez theorem add_zero : x + 0 = x
puis prove add_zero by { simplify }, et le noyau CIC vérifie. Les tactiques
sont composables (induction, rewrite, apply, auto, cases, reflexivity,
assumption, seq, try, repeat).

3. Compilation native et WASM réelles. Pas de bytecode. Le MIR (un IR
intermédiaire à blocs basiques) alimente deux backends :
- QBE → code natif x86-64, ARM, RISC-V
- WASM → WebAssembly text, exécutable par wasmtime

Performance mesurée : fib(25) compile en 1.15 ms contre 29 824 ms en
interprété (environ 26 000x). isEven 100000000 (100M récursions mutuelles)
tourne sans stack overflow — TCO self-tail et mutuelle (fusion SCC) sur les
deux backends.

4. [TARGET] Vers zéro GC. QTT (Quantitative Type Theory) est implémenté :
chaque variable porte une multiplicité (0 effacée, 1 linéaire, ω libre),
les violations sont détectées à l'élaboration. La stratégie de gestion
mémoire déterministe qui en découle (libération à la consommation, arène
d'acteur, pas de scanning) est l'architecture cible — en cours
d'implémentation.

5. Multi-syntaxes métier. La notation par défaut ressemble à un mélange
d'Idris (types dépendants, sig head : (n : Nat) -> Vec (succ n) -> a) et
d'Erlang (spawn / tell / recv pour les acteurs). Les notations spécialisées
(physique, musique, mathématiques) sont prévues à terme ; la syntaxe de
base est déjà stable.

---

## Ce qui marche aujourd'hui

Source de vérité : docs/STATUS.md (marqueurs stable / partiel / roadmap).

Noyau : 6 primitives hash-consées, Tag.evar (métavariables internes
distinctes de Tag.hole), structuralEql, lowering idempotent.

Types dépendants (surface) : data Vec (n : Nat) = Nil | Cons a (Vec n),
sig head : (n : Nat) -> Vec (succ n) -> a. Vérification structurelle des
patterns (arité, kind, base/step). Unification modulo arithmétique (v2f) :
Vec (n + m) fonctionne, la commande :norm est disponible au REPL.

Tactiques : prove t by { simplify; induction x; rewrite IH }. REPL
interactif avec affichage de but et contexte.

Effets algébriques : perform "Op" v / handle e h. Handler IO par défaut
pour print, readFile, writeFile, readLine. Étendu avec bracket, local,
catch.

Compilation :
- QBE : compile-qbe <src.hvn> -o <bin>  → binaire natif
- Cross : compile-qbe <src.hvn> -o <out.s> --target <name> → assembleur
  pour amd64_sysv, amd64_apple, arm64, arm64_apple, rv64
- WASM : compile-wasm <src.hvn> -o <out.wat>  → wasmtime run
- Bench : bench-interp, bench-qbe, bench-wasm (wall, cpu, énergie RAPL,
température, RSS)

Modules : module M, import "path.hvn" as Name, transitif, cycles détectés,
HEAVEN_PATH, export, idempotence, mode strict on/off. Les définitions
sont aliasées sous M.x ; le mode strict (opt-in) bloque le nom nu.

QTT : let linear / erased / many x = … in …, violations détectées à
l'élaboration.

Stdlib : Bool, List, Option, Pair, Result, Stream — chargés au boot
(signatures + quelques clauses ; voir docs/STATUS.md pour l'état exact).

Acteurs : deux mécanismes distincts, séquentiels pour l'instant.
- `spawn` / `tell` / `recv` : prototype de concurrence, mailbox FIFO
- `send(X, msg)` : envoi au handler d'un acteur (`let actor A = ... with h`)
- Un seul thread, pas de scheduler préemptif (voir STATUS.md)

Pipeline logique : miniKanren (kanren_expr), fact/query au REPL, synthèse
→ E-Graph → extraction.

Ontologie : ontology.zig — concepts, trust levels, provenance. Squelette
testé, non encore branché sur le Core (Phase 3 : SMT-LIB).

---

## Quickstart

Compiler (natif, Linux / macOS) :

    zig build

Lancer le REPL :

    ./zig-out/bin/heaven repl

Arithmétique et récursion :

    heaven> fac n = if (== n 0) 1 (* n (fac (- n 1)))
    ✓ clause enregistrée pour 'fac'

    heaven> fac 5
    120

Types dépendants :

    heaven> data Vec (n : Nat) = Nil | Cons a (Vec n)
    ✓ data Vec registered (1 param(s), 2 constructor(s))

    heaven> sig head : (n : Nat) -> Vec (succ n) -> a
    ✓ sig head : 2 arg(s)

    heaven> head _ Nil = 42
    ✗ pattern 2 : Nil incompatible avec le domaine 'Vec (succ n)'

    heaven> head _ (Cons x _) = x
    ✓ clause enregistrée pour 'head'

Preuves :

    heaven> theorem add_zero : x + 0 = x
    ✓ theorem add_zero stated

    heaven> prove add_zero by { simplify }
    ✓ [add_zero] proved (tactics)

Compilation native :

    $ cat fib.hvn
    fn fib(n) = (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2))))
    (fib 25)

    $ ./zig-out/bin/heaven compile-qbe fib.hvn -o fib && ./fib
    75025

---

## Les 6 primitives

| # | Primitive | Rôle | Encodage |
|---|-----------|------|----------|
| 1 | lit | Valeurs immédiates (int, float, str, bool, unit) | aux → index dans lits |
| 2 | sym | Variables, symboles, noms de constructeurs | payload → index interner |
| 3 | apply | Application n-aire | payload → fonction, span_a → arguments |
| 4 | bind | Définition globale | payload → nom (Sym), aux → valeur |
| 5 | lambda | Abstraction | payload → paramètre (Sym), span_a → corps |
| 6 | relation | Règles de réécriture / théorèmes | payload → tête, span_a → LHS, span_b → RHS |

Extensions (sucre abaissé avant évaluation) :

- let x = v in b → apply(lambda(x, b), v)
- f x = body (équation) → clause dans engine.fns
- module M / import "path" as Name → alias M.x dans engine.fns
- data Vec (n : Nat) = ... → TypeRegistry + ctor_arity + ctor_parents
- sig f : A -> B -> C → arité + domaines dans Heaven
- theorem t : a = b + prove t by { ... } → ProofState + Tactic
- perform(op, args) → apply(perform, op, args...)
- handle(body, h) → apply(handle, body, h)
- _ (hole) → Tag.hole
- Type / Prop → sym("Type") / sym("Prop")

L'évaluateur (src/core/engine_expr.zig) ne dispatch que sur ces 6 primitives.
Toute extension non-abaissée déclenche error.ExtensionNotLowered.

---

## Architecture

    ┌──────────────────────────────────────────────────────────┐
    │ Surface : REPL / shell / vessel WASM / CLI               │
    ├──────────────────────────────────────────────────────────┤
    │ Façade : src/core/heaven_expr.zig                        │
    │   parse · eval · import · tactics · holes · effects      │
    ├──────────────────────────────────────────────────────────┤
    │                    CORE IR (6 primitives)                │
    │                        expr.zig                          │
    ├──────────┬─────────────┬──────────────┬──────────────────┤
    │ Frontend │   Moteurs   │   Preuve     │    Backends      │
    │ lowering │ kanren      │ tactics      │ MIR              │
    │ elab     │ egraph      │ proof_core   │  ├─ QBE (natif)  │
    │ parse    │ transform   │ kernel CIC   │  └─ WASM (port.) │
    │ syntax   │ math        │ type_registry│                  │
    ├──────────┴─────────────┴──────────────┴──────────────────┤
    │ Runtime : acteurs · scheduler · RAPL profiler · réseau   │
    └──────────────────────────────────────────────────────────┘

Le noyau (expr.zig) est hash-consé. Le MIR est un contrat : un seul
pipeline de lowering, N consommateurs. Chaque backend (environ 200 lignes)
lit le MIR et émet son langage cible sans connaître Heaven.

---

## Documentation

- docs/book/ — livre complet (12 chapitres + annexes) : démarrage, types,
pattern matching, récursion, ordre supérieur, effets, streams, preuves,
monde réel, sous le capot, modules, knowledge.
- docs/VISION.md — vision long terme (pourquoi, direction, invariants).
- docs/STATUS.md — source de vérité (ce qui marche).
- docs/DECISIONS.md — décisions structurantes (D1-D9).
- docs/ROADMAP.md — specs actionnables.
- docs/spec/ — specs détaillées par sous-système (_tco_mutual.md,
_concurrency.md, _continuations.md, _ontology.md, _bench.md, _serialize.md).
- HEAVEN_ARCHITECTURE_2026.md — vue architecturale (document de vision).

---

## Tests

    zig build test              # tests unitaires Zig (<!-- DOCGEN:tests_zig -->381<!-- /DOCGEN -->)
    zig build test-regression   # tests Heaven core (<!-- DOCGEN:test_regression -->98/98<!-- /DOCGEN -->)
    zig build test-files        # tests/*.hvn, <!-- DOCGEN:test_files_count -->10<!-- /DOCGEN --> fichiers (<!-- DOCGEN:test_files -->37/37<!-- /DOCGEN -->)

<!-- DOCGEN:tests_zig -->381<!-- /DOCGEN --> tests Zig passent, ainsi que
<!-- DOCGEN:tests_heaven -->135<!-- /DOCGEN --> tests Heaven
(<!-- DOCGEN:test_regression -->98/98<!-- /DOCGEN --> via `test-regression`
+ <!-- DOCGEN:test_files -->37/37<!-- /DOCGEN --> via `test-files`).
Mesure <!-- DOCGEN:date -->2026-10-06<!-- /DOCGEN -->.

---

## Statut

Expérimental avancé.

Ce qui est stable :
- Noyau (6 primitives, hash-consing, structuralEql)
- Parsing infixe et S-expression
- Types dépendants (surface + unification arithmétique v2f)
- Tactiques composables (v1.5) — couverture hétérogène (voir STATUS.md)
- Modules et imports (v0 — alias M.x ; fn/let en cours)
- Effets algébriques, IO
- Compilation QBE et WASM
- TCO self-tail et mutuelle (SCC 2+)

Ce qui est en cours :
- wasm32-wasi (session parallèle, stub en place)
- Continuations délimitées (D8, continuation.zig prêt, branchement à faire)
- Découplage Vessel ↔ Astra (D9)
- Cross-compilation multi-arch

Ce qui est planifié :
- Parser Turtle / SPARQL pour la couche knowledge
- Types quotients dans le noyau CIC
- Scheduler préemptif (attend D8)
- Auto-hébergement (BigInt, I/O, structures de données, puis self-parse)

---

## Licence

Apache 2.0
