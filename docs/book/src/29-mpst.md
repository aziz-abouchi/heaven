# MPST — Session types runtime

> Vérification comportementale des protocoles d'acteurs.

## Deux couches coexistent

- stdlib/mpst.hvn : algèbre binaire (STSend, STRecv, dual, check).
  9 tests verts. Prédécesseur (Honda 1993).
- core/std/otp/protocol.hvn : helpers OTP-spécifiques sur
  mpst_trace(pid) — check_no_trace, check_has_trace,
  check_protocol, check_dual.

## Mécanisme

Chaque tell/recv accumule les labels (chaînes) dans proc.trace.
mpst_trace(pid) retourne "Req,Resp". Comparaison à une spec.

    check_protocol pid expected = (mpst_trace pid) == expected
    check_no_trace pid          = (mpst_trace pid) == ""
    check_has_trace pid         = (string_length (mpst_trace pid)) > 0
    check_dual c s c_exp s_exp  = (and ((mpst_trace c) == c_exp)
                                       ((mpst_trace s) == s_exp))

## Exemple

    test "proto_req":
      (let many p = (spawn step 0) in
       (let many _ = (tell p "Req") in
        (check_has_trace p))) == true

## Dualité

Pas d'inversion automatique (la trace est syntaxique, la dualité est
sémantique). On déclare les deux specs :

    check_dual client server "!Req,?Resp" "?Req,!Resp"

## Pourquoi runtime ?

Un typechecker MPST statique (Scribble, FuSe) est un projet à part.
Heaven choisit le runtime — cohérent avec QTT, effects, préemption
runtime. Moins fort qu'Agda, plus direct.

Voir docs/spec/_mpst_plan.md et _mpst_v2_plan.md.
