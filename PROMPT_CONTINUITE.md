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
