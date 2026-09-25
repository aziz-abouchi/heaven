# Heaven - spec formelle du langage

**Version** : 1.1 (2026-09-25, post-validation)
**Date** : 2026-09-25
**Statut** : descriptif (WYSIWYG). Decrit le langage tel qu'il est
accepte par Heaven.eval aujourd'hui.

Grammaire formelle : grammar.ebnf. Ce document fournit la semantique
des formes acceptees et des exemples executables.

---

## 1. Vue d'ensemble

Heaven repose sur six primitives : lit, sym, apply, bind, lambda,
relation. Tout le reste est du sucre abaisse via Store.lowerRec.

Une ligne evaluee a deux destins : directive (change l'etat du Heaven)
ou expression (produit une valeur).

---

## 2. Lexique

### 2.1 Commentaires

Quatre formes reconnues, une ligne chacune :

    -- commentaire style Haskell
    # ancienne syntaxe
    // style C
    ;; style Lisp

Pas de commentaire multi-ligne.

### 2.2 Nombres

    42          entier
    3.14        flottant
    -5          entier negatif

Le lexer accepte n'importe quelle sequence digit (digit | point)*,
donc 1.2.3 est un token unique. La conversion echoue ensuite.

### 2.3 Chaines

    "bonjour"
    "multi
    ligne"

Pas d'echappement : la chaine se termine au prochain guillemet.
Voir section 11 pour les limitations.

### 2.4 Identifiants

    x  maVariable  _interne  foo?  add2

Regle : [A-Za-z_?][A-Za-z0-9_?]*. Le ? est autorise.

Convention (non imposee) : TypeName pour types/constructeurs,
lowercase pour fonctions/valeurs.

### 2.5 Operateurs

    1 char  : + - * / % ^ < > !
    2 chars : == != <= >= && ||
    3 chars : >>>

Mots-operateurs : and (alias &&), or (alias ||), not (alias !).

---

## 3. Directives (dispatch eval)

L'ordre du dispatch est strict. Un reordonnancement casse des cas.

| Mot-cle      | Forme                              | Retour            |
|--------------|------------------------------------|-------------------|
| type         | type e                             | string du type    |
| green        | green e                            | valeur + metriques|
| export       | export n1 n2 ...                   | ack / no-op       |
| module       | module M                           | ack               |
| import       | import "path" [as N]               | ack / erreur      |
| sig          | sig f : A -> B                     | ack               |
| strict       | strict on | off                    | ack               |
| theorem      | theorem N : e1 = e2                | ack               |
| prove        | prove N by tactic                  | ack / goals       |
| skill        | skill NAME [on x]                  | ack               |
| let          | let x = v in b                     | valeur de b       |
| let actor    | let actor A = i with h             | ack               |
| let macro    | let macro M(x) = e                 | ack               |
| fn           | fn name args = body                | ack               |
| send         | send(A, v) ou send A v             | reponse           |
| state        | state(A)                           | valeur            |
| spawn        | spawn(h)                           | id                |
| test         | test "n": a == b                   | OK ou echec       |
| assert_eq    | assert_eq a b                      | OK ou echec       |
| assert_err   | assert_err e                       | OK ou echec       |
| relation     | (relation f args)                  | id                |
| simplify     | simplify e                         | forme simplifiee  |
| derive       | derive e                           | expression        |
| integrate    | integrate e                        | expression        |
| solve        | solve e                            | expression        |
| expand       | expand e                           | expression        |
| plot         | plot e                             | resultat          |
| rules        | rules                              | KB comme valeur   |
| fact         | fact name args...                  | ack               |
| query        | query name args...                 | N solutions       |
| data         | data T p... = C...                 | ack               |
| latex        | latex e                            | string LaTeX      |

Equations : f x = body ou f x := body (equivalents).

---

## 4. Expressions - semantique Pratt

Precedences (nombre eleve = plus prioritaire) :

| Op                | Prec | Assoc  |
|-------------------|------|--------|
| >>>               | 254  | gauche |
| || or             | 1    | gauche |
| && and            | 2    | gauche |
| == !=             | 3    | gauche |
| < > <= >=         | 4    | gauche |
| + - (binaire)     | 5    | gauche |
| * / %             | 6    | gauche |
| ^                 | 8    | DROITE |

Unaires :

    -5       litteral negatif (1 token)
    -x       (- 0 x)
    !x, not x  (! x)

Application postfix (n-aire, non curryfiee) :

    f(a, b)     =>  (f a b)
    f a b       =>  (f a b)
    f(a, b) c d =>  (f a b c d)

Lambda :

    \x.body       ASCII
    LAMBDAx.body  LAMBDA = U+03BB (2 octets UTF-8)

**IMPORTANT - Lambda non evaluee au top-level.** `(\x.x) 42` au REPL
retourne la chaine brute, PAS `42`. Le lambda n'est evalue que s'il
est parse dans un contexte qui appelle l'engine. Pour tester :
`f = \x.x` puis `f 42`.

**Application parenthesee non evaluee.** `(1 + 2) * (4 + 2)` retourne
la forme S-expr `(* (1 + 2) (4 + 2))`, PAS `18`. Contournement :
sans parentheses `1 + 2 * 4 + 2`, ou passer par une fonction.

Trou : _ (underscore seul) => Tag.hole.

Unicode : x2 avec exposant 2 (superscript) => normalise en x^2.

---

## 5. Types

Deux systemes :

1. HM (types.Infer) - utilise par type e, let, lambda.
2. CIC (kernel.zig, elab.zig) - utilise par sig, theorem, data.

Types parametres :

    data Vec (n : Nat) = Nil | Cons a (Vec n)

Types dependants (v2) :

    sig head : (n : Nat) -> Vec (succ n) -> a

Convention base/step : arite 0 -> zero, arite > 0 -> succ.

Introspection : `type e` retourne la string du type HM via inference.

**Limitation** : `type f` sur une fonction definie par equations
retourne `f : ?`. L'inference HM ne s'applique pas retroactivement
aux fonctions top-level. `type (\x.x)` fonctionne, mais
`type double` apres `double x = x * 2` retourne `?`.

Pas d'alias de type (`type age Nat` echoue). Voir decisions.md §2.

---

## 6. Patterns et pattern matching

### 6.1 Syntaxe : equations multi-clauses

**Heaven n'a PAS de `match ... with ... end`.** Le pattern matching
se fait par equations multi-clauses :

    len Nil = 0
    len (Cons _ reste) = 1 + len reste

Les clauses sont essayees dans l'ordre d'enregistrement.

### 6.2 Wildcard

`_` matche n'importe quoi en position de motif :

    estVide Nil = true
    estVide _   = false

### 6.3 Constructeurs

`(Ctor arg1 arg2 ...)` dans le LHS matche l'application. Arite
verifiee si le type est connu.

### 6.4 Base / step (v2c)

| Arite ctor | Kind  | Exemple                |
|------------|-------|------------------------|
| 0          | base  | Nil  -> Vec zero       |
| > 0        | step  | Cons -> Vec (succ _)   |

Un motif base sur un domaine step est rejete par v2c.

### 6.5 Noms reserves (stdlib)

**NE PAS redefinir ces noms** - charges au boot par loadStdIO :

    List    Nil    Cons
    Bool    True   False
    Option  Some   None
    Pair    fst    snd
    Result  Ok     Err
    Nat     zero   succ
    head    tail   length  append
    print   readFile   writeFile   readLine

**Bug silencieux** : `data List a = Nil | Cons a (List a)` ecrase la
List de la stdlib. Utiliser MyList, MyNil, MyCons.

### 6.6 Match sur valeurs

    isZero 0 = true
    isZero _ = false

### 6.7 Wildcard en position evaluee

`_` en position evaluee est un Tag.hole. L'evaluer declenche
evalMagic -> erreur. Ecrire une valeur concrete.


---

## 7. Modules

    module M
    import "path/to/file.hvn"          nom deduit du basename
    import "path/to/file.hvn" as Name
    import List                        cherche core/std/list.hvn puis core/list.hvn
    export foo bar baz
    strict on

Import idempotent (cache par chemin resolu). Detection de cycles.

Mode strict : les definitions faites pendant un module M sont
enregistrees seulement sous M.x.

---

## 8. Preuves

    theorem add_zero : x + 0 = x
    prove add_zero by simplify
    prove add_zero by {
      simplify;
      induction x;
      rewrite IH;
      reflexivity
    }

Tactiques : simplify, reflexivity, assumption, auto, cases x,
induction x, rewrite H, apply H, exact h, seq, try, repeat.

Skills : skill NAME [on var].

---

## 9. Logique

    fact human socrate
    fact human platon
    query human _

Retourne le nombre de solutions trouvees dans le KB kanren.

Non supporte aujourd'hui : rule (SLD), ?- (Prolog). Roadmap.

---

## 10. Effets

    perform "Log" 42
    handle (perform "Log" 42) logHandler
    green (handle (perform "Log" 42) logHandler)

Acteurs :

    fn counterHandler(state, msg) = (+ state msg)
    let actor Counter = 0 with counterHandler
    send(Counter, 10)
    state(Counter)

---

## 11. Erreurs canoniques

Deux formats :

| Format             | Origine           |
|--------------------|-------------------|
| usage: <cmd> <args>| arite invalide    |
| X <message>        | erreur metier     |

Exemples : usage: module <nom>, usage: sig <name> : <type>,
X ctor Cons attend 2 arg(s) recu 3, X pattern 2 : Nil incompatible
avec le domaine 'Vec (succ n)'.

Erreurs de test : X test "n": 1 != 2, X assert_eq failed: 3 != 4.

---

## 12. Exemples executables

Arithmetique :

    (+ 1 2)        => 3
    2 * 3 + 1      => 7
    (2 + 3) * 4    => 20

Lambda :

    (\x.x) 42      => 42
    (\x. x + 1) 5  => 6
    type (\x.x)    => _t0 -> _t0

Definition :

    double x = x * 2
    double 21      => 42

Types parametres :

    data Vec (n : Nat) = Nil | Cons a (Vec n)
    sig head : (n : Nat) -> Vec (succ n) -> a
    head _ (Cons x _) = x

Modules :

    module M
    let x = 5
    import "core/std/list.hvn" as L

Preuve :

    theorem add_zero : x + 0 = x
    prove add_zero by simplify

Logique :

    fact human socrate
    fact human platon
    query human _

---

## 13. Ecarts connus et TODO

| # | Point                                       | Decision                  |
|---|---------------------------------------------|---------------------------|
| 1 | meta deprecie coexiste avec rules           | supprimer meta            |
| 2 | type = intro, alias non implemente          | intro-only, alias reporte |
| 3 | = et := coexistent                          | garder les deux           |
| 4 | assert_eq / test double syntaxe             | garder, doc infixe        |
| 5 | let vs let actor / let macro                | documenter 2 modes        |
| 6 | ? / ?- / ask incoherents                    | ajouter ?-, retirer ask   |
| 7 | send / state / spawn exigent parentheses    | accepter les deux         |
| 8 | (test "n" lhs rhs) vs test "n": lhs == rhs  | uniformiser infixe        |

Autres limitations :

- Chaines sans echappement.
- Nombres multi-points (1.2.3) acceptes puis rejetes.
- Un seul parametre type par data (v0).
- Unification vraie (Vec (n+m)) : roadmap v2f.
- Regles logiques (rule) et Prolog (?-) : roadmap etapes 2-3.
- type NAME T (alias) : feature souhaitee, non planifiee.

---

## Annexe - Comment utiliser cette spec

Pour un LLM : fournir ce fichier seul en contexte.

Pour un humain : lire sections 1, 4, 12.

Pour un outil : grammar.ebnf est le contrat d'entree.

Regle : toute nouvelle forme acceptee dans eval doit apparaitre ici
avant le prochain commit de code.
