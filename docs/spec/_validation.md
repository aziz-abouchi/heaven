# Validation spec v1.0 - resultats

**Date** : 2026-09-25
**Protocole** : heaven.md seul donne a un LLM, prompt
"genere 5 programmes Heaven couvrant arithmetique, lambda, data,
pattern matching, query logique".
**Test** : chaque ligne du LLM passee dans les 2 REPL (natif + WASM).

## Verdict global

**1/5 programmes serait correct.** Les 4 autres contiennent des
formes inventees ou des hypotheses fausses sur le comportement.

## Analyse par ligne

| Ligne | Natif | WASM | Note |
|---|---|---|---|
| `1 + 2 * 3` | 7 OK | 7 OK | OK |
| `(1 + 2) * (4 + 2)` | S-expr | S-expr | Non evaluee : retourne `(* (1 + 2) (4 + 2))` |
| `-2 ^ 3` | erreur | erreur | UnknownSymbol : `-` separe |
| `(\x.x) 42` | string brute | string brute | Lambda non evaluee au top-level |
| `(\x. x + 1) 5` | string brute | string brute | idem |
| `compose f g = \x. f (g x)` | clause | clause | Enregistrement OK |
| `succ x = x + 1` | clause | clause | Ecrase le stdlib |
| `(composition double succ) 3` | error | error | Typo LLM : `composition` |
| `ajouter a b = a + b` puis `ajouter 5 7` | 12 OK | 12 OK | OK |
| `type ajouter` | `?` | `?` | HM non retroactif |
| `data List a = Nil | Cons a (List a)` | OK | OK | Ecrase la stdlib |
| `data Vec (n : Nat) = ...` | OK | OK | OK |
| `sig vhead : ...` | OK | OK | OK |
| `vhead _ (VCons t _) = t` | OK (subst: 1) | OK | v2e actif |
| `vhead 2 v1` | erreur `v1` | curry | Typo : `v1` pas defini |
| `type l1`, `type v1` | `?` | `?` | HM non retroactif |
| `len Nil = 0` + `len (Cons _ r) = 1 + len r` | OK | OK | Equations multi-clauses |
| `fact human socrate` | silencieux | UnknownSymbol | Divergence natif/WASM |
| `query human _` | silencieux | UnknownSymbol | Divergence |
| `test "...": query human _ == 3` | ✗ | ✗ | Semantique : query retourne string |

## Trous de la spec identifies

1. **Pattern matching** - Le LLM a invente `match ... with ... end`.
   Heaven utilise des equations multi-clauses. Section 6 a reecrire.
2. **Noms reserves stdlib** - List, Cons, Nil, succ, etc. charges au
   boot. Redefinir casse silencieusement.
3. **type e non retroactif** - Retourne `?` pour les fonctions
   definies par equations.
4. **Lambda top-level non evaluee** - `(\x.x) 42` retourne la chaine.
5. **Application parenthesee non evaluee** - `(1 + 2) * (4 + 2)` ->
   S-expr.
6. **query retourne une string** - Pas un entier.

## Bugs runtime decouverts (a corriger, pas dans la spec)

| Bug | Impact | Priorite |
|---|---|---|
| Lambda non evaluee top-level | Fonctionnel | Haute |
| `type e` sur fn utilisateur | Retourne `?` | Moyenne |
| Application parenthesee | S-expr | Moyenne |
| `fact`/`query` silencieux natif | Divergence WASM | Moyenne |
| `-2 ^ 3` | Parse error | Basse |

## Protocole v2 (apres correctifs)

1. Patch heaven.md avec les 6 trous.
2. Meme prompt au LLM.
3. Tester ligne a ligne dans le REPL natif.
4. Critere : >= 4/5 programmes dont toutes les lignes passent.
