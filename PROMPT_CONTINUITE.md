# Prompt de continuité — Heaven session suivante

## HEAD
f29775d (main) — refactor(kernel): derive cong_succ, cong_add_l/r via eq_rect_nat
Tout poussé sur origin/main.

## Tests
175/176 Zig (1 skipped), 100/100 HVN, 0 fuite.
peano.zig : 27/27 tests.
[KERNEL] structural=true type_check=true pool_size=1505.

## Session écoulée — jalon kernel : declassement des congruences
- eq_rect_nat ajoute (J-eliminator restreint a Nat) : primitive unique
  pour l'egalite.
- 3 axiomes de congruence RETIRES, maintenant derives :
  cong_succ (mkCongSuccProof), cong_add_l (mkCongAddLProof),
  cong_add_r (mkCongAddRProof).
- Tous les proof terms internes branches sur les helpers derives
  (peano.zig + proof_core.zig).
- Bug latent corrige : shift/subst ne propageaient pas dans .refl.
- Bug latent corrige : mkCongAddRProof P devait etre Eq(add a c, add x c)
  (invisible sur tests clos, cassait distrib sur (2,3,4)).

## Base de confiance kernel — etat final (190daaa, 2026-09-30)
PRIMITIFS : Nat, zero, succ, add, mul, nat_ind, eq_rect_nat.
AXIOMES   : AUCUN axiome de congruence.
DERIVES   : sym, trans, cong_succ, cong_add_l, cong_add_r
            + add_comm, add_assoc, add_succ_right, mul_zero_right,
              mul_succ_right, mul_comm, distrib.
            Tous construits sur eq_rect_nat + nat_ind.
pool_size : 1782 (preuves derivees plus volumineuses qu'axiomes).

## Prochaines actions kernel
A. Deriver sym via eq_rect_nat :
   sym = La b h. eq_rect_nat(Ly. Eq(y, a), a, b, h, refl(a))
B. Deriver trans via eq_rect_nat (plus delicat, c doit apparaitre).
C. Ensuite : plus AUCUN axiome de congruence, kernel CIC minimal.

## Patterns de bugs (3 occurrences, documentes)
1. ih_type doit etre ecrit sous le contexte PRECEDENT (var(0) pour
   [k] seul), pas var(2).
2. Ordre des arguments de retour doit matcher l'ordre des Pi dans P.
3. cong_add_l vs cong_add_r : l=2e arg, r=1er arg.
4. eq_rect_nat : P doit cibler le BON cote (Eq(add a c, add x c)
   vs Eq(add x c, add b c)) sinon P(b) est faux.
Invisibles sur (zero,zero,...). Test e2e sur (2,3,4) INDISPENSABLE.

## WIP externe non commit
core/std/*.hvn, parse.zig, core/test_suite.hvn,
src/vessel/public/test_suite.hvn, patch_parser_infix.py.

## Architecture a terme (kernel)
delta-regles minimales (2 par operateur, 1er argument) :
  add(zero,n)->n ; add(succ k,n)->succ(add k n)
  mul(zero,n)->zero ; mul(succ k,n)->add(n,mul k n)
Equality : eq_rect_nat primitif, tout le reste derive.
Apres sym/trans derives : 0 axiome de congruence.

## Session 2026-09-30 (suite) — commits b01de06..0462157
- 735c3f7 feat(engine_expr): safepoint 3a-3-lite (evalWithBudget
  / EvalOutcome). Engine.reductions, error.SuspendRequested,
  abort cooperatif. 4 tests.
- ccb8711 docs(_continuations.md): note "abort cooperatif !=
  scheduling". Constat : evalWithBudget suspend a l'entree, ne
  reprend pas. Le scheduler exige 3a-3-complet.
- dbeca0c feat(platform/abi): ProfileTree (hierarchie de profils,
  children/ancestors/rootOf/depth, dedup content-addressed).
  8 tests.
- 0462157 feat(platform/abi): ProfileAnnotations (ClassId <->
  ProfileId, bestForMetric). Premiere brique de la boucle
  Metrics -> EGraph -> Proof. 8 tests.

## ABI platform — etat final (8 fichiers, ~84 tests)
precision.zig (7), error.zig (4), capability.zig (15),
metric.zig (6), profile.zig (28), profile_ser.zig (8),
profile_tree.zig (8), profile_annotations.zig (8).

Tous branches dans build.zig (test_abi_*). `zig build test` : 375/377
(1 skip WIP MIR, 1 fail test_mir_qbe externe).

## Regle P3 tenue par le type
Deux verrous concrets :
- requireMeasuredEnergy (profile.zig) : refuse les estimations.
- bestForMetric (profile_annotations.zig) : ne considere que
  `measured`, jamais `estimated`.
Un optimiseur qui veut choisir une classe DOIT passer par
bestForMetric -- il ne peut pas prendre une decision sur une
valeur non fiable.

## Prochains chantiers (independants)
A. 3a-3-complet : brancher captureCont dans engine_expr.evaluate.
   Session dense, touche le tree-walker (56 sites recursifs,
   propage via try). Debloque scheduler + handle-rec.
B. egraph.add_profile : relier ProfileAnnotations a egraph.zig.
   La couche donnees existe, il reste le pont.
C. MIR/QBE (autre session) -- NE PAS TOUCHER.

## ABI platform etendue (2026-09-30, commits f912737..11419cf)
src/platform/abi/ contient maintenant 6 fichiers :
- precision.zig   (7 tests) : Precision, Monotonic, Value, Metric
- error.zig       (4 tests) : PlatformError, FailureReason
- capability.zig (15 tests) : FileCap, NetCap, EnergyCap
- metric.zig      (6 tests) : Metric(K, P), 7 Kinds
- profile.zig    (28 tests) : Profile + ProfileDiff + politiques
- profile_ser.zig (8 tests) : format HVP1

Branche dans build.zig : `zig build test` execute tout.

## Continuations 3a-2 livree (11419cf)
src/core/continuation.zig (9 tests) :
- 3a-1 : Prompt, PromptStack (push/pop/top/depth)
- 3a-2 : Frame, CaptureStack, Continuation, captureCont,
  throwCont. Pile simulee, non branchee sur engine_expr.

## Specs etendues
- docs/spec/_serialize.md : section Profils (HVP1) — format v1,
  id non serialise, dedup content-addressed, index v2 reporte.
- docs/spec/_metrics.md : 4 notes "Implementation (2026-09-30)"
  pointant vers src/platform/abi/*.zig.

## Prochain increment
- 3a-3 : brancher captureCont/throwCont dans engine_expr.evaluate
  (handle-rec + scheduler C3). Dense, touche le tree-walker.
- Ou : Profile dans EGraph (boucle Metrics -> Proof, spec _metrics.md).

## WIP externe (NE PAS TOUCHER)
src/backend/mir_qbe.zig, test_mir_qbe.zig, qbe-1.3.tar.xz (M3).
Note : `zig build test` est rouge a cause de test_mir_qbe
(M3 : oracle mir.execute vs natif). Ce n'est PAS notre travail.

## ABI platform implementee (2026-09-30)
src/platform/abi/ livre (commit aafd7f3) :
- precision.zig : Precision, Monotonic, Value(T,P), Metric(T)
- error.zig     : PlatformError, FailureReason, Result(T)
- capability.zig : FileCap, NetCap, EnergyCap + restrict()
26 tests (7+4+15), tous verts. Aucun branchement build.zig.
Testables en isolation : zig test src/platform/abi/<f>.zig

## Prochain increment (concret, testable)
- Metric<T,P> en Zig : instancier pour les metriques de _metrics.md
  (wall_time, rss, energy, ...) sans dependre de platform.
- Ou : etendre _serialize.md avec section Profile (doc, pre-requis
  metrics).

## Cascade specs livree (2026-09-30)
Trois specs forment la colonne vertébrale du runtime :
- docs/spec/_platform.md (331 l., commit 3459881) :
  capabilities, precision typee, erreurs unifiees, non-goals.
- docs/spec/_runtime.md (262 l., commit 340d0c4) :
  carte d'articulation _concurrency/_effects/_continuations/
  _platform. Invariant fondateur : les 5 primitives runtime
  (spawn/send/recv/yield/self) sont des effets algebriques, pas
  des primitives CIC.
- docs/spec/_metrics.md (336 l., commit b473aa7) :
  Profile comme terme (hashable/comparable/stockable/injectible),
  Metric<T, P: Precision>, boucle Metrics -> EGraph -> Proof.

Cascade : _platform -> _runtime -> _metrics. Pre-requis :
_serialize.md (section Profile HVN1), spec securite
(RemoteProfileCap), Prototype 4 (add_profile dans EGraph).

## Spec platform (nouveau)
docs/spec/_platform.md livree (2026-09-30, commit 3459881).
- 5 principes : capabilities (P1), pas d'authority ambiante (P2),
  precision dans le type (P3), pas de null (P4), erreur unique (P5).
- 13 familles ABI, 7 capabilities, table dispo par cible.
- Prochaines specs : _runtime.md puis _metrics.md (ordre impose :
  _metrics depend du modele de Profile typé par precision de P3).

## Autres chantiers ouverts
- Prototype 3a-2 (captureCont/throwCont) : continuations.
- Migration span_a.slice (181 sites).
- Serialisation v2 (reachable subset).
- MIR (docs/mir en cours, externe).

## NE PAS TOUCHER
wasm.zig, kernel.zig, mir.zig, x86_64_windows.zig, aarch64_macos.zig,
commands.zig (racine), transform.zig, kernel_bridge.zig,
branche feat/physical-telemetry + WIP externe ci-dessus.

## Methode
Petits pas verifies > gros refactor. Un commit = un theme.
Heredoc > 50 l. = tronque par navigateur -> scripts /tmp en 2-3 blocs.
zig test src/kernel/peano.zig (rapide) pour iterer kernel.
NE JAMAIS utiliser git checkout sur un fichier modifie sans verifier
que le diff est bien du WIP et pas du travail en cours.

## Addendum backends (même session, fin)
- cda121d M1 : docs/MIR_CONTRACT.md (contrat MIR — attention : a
  écrasé 290f301 sans fusion, réconcilié en 11f128c ; convention
  #13 : git log -- <file> avant tout cat > sur docs/)
- ff0ecb0 M2a : src/backend/mir_wat.zig — émetteur MIR→WAT,
  4 golden tests (179/180, zéro leak). Dispatch trampoline v0,
  phis abattus, call_user restreint à fn_defs.
- Fuite mir.zig (gelé, côté kernel) : deinit ne libère pas
  .phi.incoming (l.316) ni .call_user.args — workaround dans
  test_mir_wat.zig, fix réel à coordonner.
- M2b : wasmtime (cargo install wasmtime-cli) — oracle
  mir.execute vs exécution WAT réelle.
