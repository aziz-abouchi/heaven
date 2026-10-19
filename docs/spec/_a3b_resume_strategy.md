<!-- HEAVEN:a3b-resume-strategy -->
# A-3b : stratégie de reprise au milieu d'un `.apply`

**Date** : 2026-10-16
**Statut** : R2 implémenté 2026-10-19. `Frame.args_done_len`, `markArgDone` (11 sites), `Env` ref-compté. R1 trampoline reste à faire (`_capture_eval.md`).

## Constat

`evaluate` est un tree-walker récursif. Aucun point unique n'observe
"arg i vient d'être évalué". Les args sont consommés magic par magic
(`if` évalue args[0], `tuple` itère, `seq` itère), via `evalFunction`
(user fns), dans la boucle TCO, dans le dispatch ctor, dans le
dispatch env.

Conséquence : au moment d'un `SuspendRequested`, remonté par `try`
à travers N frames, on ne sait pas quel arg du `.apply` parent
était en cours.

## Trois stratégies

### R1 — Trampoline explicite
Chaque magic évalue **un seul** arg par appel. Boucle externe pilote.
Machine à états complète.

- ✅ Reprise exacte, robuste.
- ❌ Réécrit ~50 magics. Effort 1-2 sessions. Risque élevé (hot path).
- ❌ Modifie la structure de contrôle ; incompatible avec le hook
  push/pop actuel en une passe.

### R2 — Marqueur par frame (recommandé)
Chaque `Frame` de type `.apply_op` porte `args_done_len: u8`.
Avant `evaluate(arg_i)`, on met à jour `frame.args_done_len = i`
sur le top de la pile (mutable). Au suspend, la pile contient
l'info exacte.

- ✅ Un seul point d'écriture par magic (le `for` d'éval des args).
- ✅ Zéro allocation, POD pur.
- ✅ Compatible avec le hook push/pop actuel.
- ⚠️ Sur resume, args 0..i-1 doivent être **ré-évalués** (on n'a que
  le compte, pas les valeurs). Implique : args doivent être **purs**
  (pas de `yield`, `@prompt`, `delay` non forcé, effets de bord).
- ⚠️ Nécessite `topMut() *Frame` sur `CaptureStack`.
- ⚠️ Instrumentation à faire sur ~5 sites d'éval d'args (ctor, magic,
  evalFunction, TCO, dispatch env). Un oubli = reprise partielle.

### R3 — Replay intégral (voie B)
Au suspend, on jette l'éval du `.apply` en cours. Au resume, on
rejoue l'appel entier depuis le début.

- ✅ Zéro instrumentation. Implémentation triviale.
- ✅ Fonctionne même pour args impurs.
- ❌ Pas de reprise "exacte". Le budget "doublant à chaque retry"
  mentionné dans le contexte initial.
- ❌ Incompatible avec l'objectif A-3b (reprise exacte).

## Décision

**R2 retenu (à valider).** Compromis acceptable : reprise exacte au
niveau du **compteur d'args**, avec la contrainte "args purs" à
documenter dans le langage.

## Points à trancher en 2c-3

1. `Frame.args_done: []const u64` (plan A-3b initial) devient
   `args_done_len: u8` seul. Les valeurs ne sont pas stockées.
2. `CaptureStack.topMut() *Frame` à ajouter.
3. Les 5 sites d'éval d'args à instrumenter :
   - `evalMagic` ctor branch (engine_expr.zig ~1708)
   - `evalMagic` `.apply` args (engine_expr.zig ~890 pour TCO)
   - `evalFunction` (à localiser)
   - dispatch env (engine_expr.zig ~1740)
   - `evalMagic` magic par magic (if/seq/tuple/...)
4. Test : sur suspend, dump `capture_stack` et vérifier que le frame
   `.apply_op` a bien `args_done_len == i` attendu.

## Effort restant

- 2c-3 : `topMut` + `args_done_len` par frame (1 commit, ~1h).
- 2c-4 : instrumentation des 5 sites (1-2 commits, ~2h).
- 2d : `pending_capture → captureCont réel` (session suivante).
- A-3b-3 : `throwCont` dans schedule + test resume.

## Risque résiduel

Args impurs. Il faudra soit interdire `yield`/`@prompt`/`delay` en
position d'arg dans `.apply`, soit accepter la duplication d'effets
sur resume. À documenter dans `DECISIONS.md` (D-A3B-ARGS-PURITY).


## LIMITE STRUCTURELLE (constat 2026-10-16, post-2d)

Le champ `Frame.env: u64` est un pointeur **brut** vers un `*Env`.
Or `evalFunction` (engine_expr.zig:605) cree son Env **stack-local** :

    var new_env = Env.init(self.allocator);
    defer new_env.deinit();

Quand la pile unwind sur `SuspendRequested`, ces Env sont detruits.
La Continuation capture leurs adresses, mais a la reprise elles
pointent vers de la memoire reutilisee ou invalide.

**Consequence** : R2-strict « resume a l'id du frame » ne peut PAS
fonctionner tel quel. Le 2c-5 (« args_done_len survit a captureCont »)
prouve que la donnee survit ; il ne prouve pas que la pile est
reutilisable. C'est une omission du plan initial.

**Decision** : ouvrir le chantier A-3b-2e (ownership des Env) AVANT
A-3b-3. Voir ci-dessous.

## A-3b-2e : ownership des Env (chantier)

Objectif : rendre les Env capturables sans dangling pointer.

### Option B1 — Arena dediee par capture
Chaque captureCont cree une arena, deep-copie les Env, les stocke dans
la Continuation. A la reprise, l'arena est utilisee. Au deinit() de la
Continuation, l'arena est liberee.

- Avantage : pas de changement global.
- Inconvenient : cout memoire O(N) par capture, N = profondeur.

### Option B2 — Ref-counting global
Env devient `*Env` avec compteur de references. Chaque push de frame
incremente. Chaque pop decremente (et libere si 0). La Continuation
possede ses propres refs.

- Avantage : pas de copie.
- Inconvenient : touche tous les sites Env (init/deinit/get/put), risque
  de fuite ou double-free.

### Option B3 — Arena unique pour l'Engine
Tous les Env vivent dans une arena possedee par l'Engine. Les Env ne
sont jamais deinit() individuellement. L'arena est reset entre deux
« mondes » d'evaluation (top-level, avant un schedule, apres un resume).

- Avantage : zero cout par capture.
- Inconvenient : politique de reset a definir (quand peut-on liberer ?).
  Necessite un invariant clair : aucun Env ne survit au-dela d'un cycle.

### Recommandation
B1 d'abord (local, sur, non intrusif). B3 ensuite en optimisation si
le profiling montre que B1 coute trop.


## DESIGN B2 (ref-counting Env) — a valider avant code

### Struct

    // src/core/env.zig (nouveau module, casse le cycle continuation<->engine)
    pub const Env = struct {
        bindings: std.AutoHashMapUnmanaged(Sym, Id) = .{},
        allocator: Allocator,
        refs: u32 = 1,   // B2 : compteur

        pub fn init(a: Allocator) Env { ... }
        pub fn clone(self: *const Env, a: Allocator) !*Env { ... }  // retourne *Env
        pub fn ref(self: *Env) void { self.refs += 1; }
        pub fn unref(self: *Env) void {
            self.refs -= 1;
            if (self.refs == 0) { self.bindings.deinit(...); self.allocator.destroy(self); }
        }
    };

### Regle « qui possede quoi »

1. Un `new_env` local est cree avec refs=1, possede par la stack frame
   courante. A la fin du scope : `defer new_env.unref()`.
2. Chaque push de Frame fait `env.ref()`. Chaque pop fait `env.unref()`.
3. `captureCont` fait `ref()` sur chaque Env unique des frames captures.
   `Continuation.deinit` fait `unref()` sur chacun.
4. `throwCont` refait `ref()` pour chaque frame re-push (l'appelant possede
   maintenant une nouvelle reference).

### B2a vs B2b

- B2a : `Frame.env: *anyopaque`. `continuation.zig` n'importe pas
  `engine_expr.zig` ; l'Engine fournit des callbacks ref/unref.
- B2b : `Env` vit dans `src/core/env.zig`, importable par les deux.

**Choix B2b** : le cycle est reel (continuation importe Env), mais un
module dedie evite le *anyopaque et les callbacks runtime. Cout :
extraire `Env` + `Sym` + `Allocator` dans `env.zig`, mettre a jour les
imports (3-4 fichiers).

### Plan 4 commits

1. **2e-1** : extraire `Env` dans `src/core/env.zig` (copie, re-export
   depuis `engine_expr.zig`). Zero changement de comportement.
2. **2e-2** : `Env` -> `*Env` partout dans engine_expr.zig. `init`
   retourne `*Env` (alloue). `unref()` remplace `deinit()`.
3. **2e-3** : `Frame.env: *Env` (plus u64). Push/pop ajustent ref.
   `captureCont` / `Continuation.deinit` ajustent ref.
4. **2e-4** : tests + A-3b-3 debloque (reprise exacte reelle).

### Risques

- Oubli de ref => fuite (leak detector le verra).
- Oubli de unref => fuite.
- Double unref => crash (leak detector aide).
- Perf : ref++ / ref-- sur hot path. Mesurer avec un bench.

### Alternative si trop lourd

Revenir a B1 (arena par capture) : plus simple mais O(N) memoire par
capture. Pertinent si captures rares (deja le cas : yield ne capture
pas, seuls @throw / perform / resume capturent).


## BLOCAGE R1 (constat 2026-10-16, fin de session)

Apres 2e-3 (Env ref-compte, 0 leak), tentative de A-3b-3 : la reprise
exacte au milieu d'un `.apply` n'est PAS possible avec `evaluate` tel
qu'il est ecrit.

### Pourquoi

`evaluate` est recursif. Sur suspend budget :

    evaluate(A) -> push Frame{A}
      evaluate(B) -> push Frame{B}
        evaluate(C) -> SUSPEND (reductions == 0)

Unwind -> toutes les frames sont pop (defer). Stack vide. La capture
(si active) aurait [A, B].

Sur resume, on restaure [A, B] puis on evaluate(C). Mais le code Zig
qui appelait evaluate(C) depuis evaluate(B) a disparu (c'etait une
activation sur la pile native). Les Frame ne sont que des donnees.

Resultat : evaluate(C) repart de zero, et son retour va a evalWithBudget,
pas a B. Le resultat ne remonte pas la pile A<-B<-C.

### Consequence

Faire la reprise « au frame » necessite R1 : transformer `evaluate`
en machine a etats explicite (boucle externe, chaque magic evalue
1 arg par appel). C'est un refactor du hot path :
- 56 sites d'appel `evaluate`,
- ~50 magics a adapter,
- risque eleve (chaque oubli = bug silencieux).

Effort : 2-3 sessions dediees, pas une fin de session.

### Etat actuel : dormant

`engine.capturing = false` par defaut, jamais active (grep : 0 site
`capturing = true`). Tout le travail 2c/2d/2e est DORMANT :
- Frame enrichi (kind, args_done_len, args_left),
- 11 sites markArgDone,
- PendingCapture.cont (3 sites cables),
- Env ref-compte (0 leak).

Ces briques ne sont PAS perdues : elles sont le prerequis de R1. Le
jour ou on fait R1, on active `capturing = true` et ca marche.

### Modele alternatif deja fonctionnel : checkpoint yield

Pour les taches longues, le modele `yield` actuel marche deja :

    f s = if (= s 50) s (yield (+ s 1))

Chaque tick avance d'un pas et re-yield. Budget arbitrairement petit.
Test scheduler 3/3 vert. Ce n'est pas de la reprise exacte, mais ca
progresse.

### Prochaine etape A-3b

R1 (trampoline `evaluate`) en session dediee. Ne pas activer
`capturing` avant. Sinon : comportement inchange, correct.

Alternative ecartee (reaffirmee) : voie B (budget doublant a chaque
retry), deja mentionnee et rejetee pour absence de reprise exacte.
