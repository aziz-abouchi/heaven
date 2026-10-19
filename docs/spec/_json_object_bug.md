<!-- HEAVEN:json-object-bug -->
# JSON V1 objects : bug sur clé/valeur (2026-10-19)

## Ce qui marche

- Arrays : 6/6 (`json_as_arr_s`, `jv_len`, `jv_get`).
- Object vide `{}` : parse, `json_obj_get ... "z"` retourne `JNull`.
- Pattern matching imbriqué : 6/6 (pat.hvn).
- Égalité constructeurs : 12/12 (test_data_eq.hvn, commit 788062f).

## Ce qui casse

- Object avec clé : `json_obj_get (json_as_obj_s "{\"a\":42}") "a"` retourne 0 (attendu JNum 42).
- Test discriminant : `json_obj_get (JPCons (JPair "a" (JNum 42)) JPNil) "a"` échoue même en construction manuelle (pas de parser impliqué).

## Deux hypothèses

### H1 : `json_obj_get` ne matche pas `(JPCons (JPair k v) rest)`

Pourtant pat.hvn (6/6) matche `(LCons (PInt x) rest)`. Différence : `JPair k v` a **2 args** dont un `Str` (k), `PInt x` a 1 arg `Int`. Peut-être le pattern à 2 args avec le premier `Str` échoue ? Test discriminant à faire :

    data P2 = P2 Str Int
    data L2 = L2Cons P2 L2 | L2Nil
    get2 (L2Cons (P2 k v) rest) k2 = (if (= k k2) v 0)
    get2 L2Nil k2 = (- 0 1)
    test "g2": (get2 (L2Cons (P2 "a" 42) L2Nil) "a") == 42

### H2 : `==` (assert test) ne gère pas les constructeurs

Le test `(json_obj_get (json_as_obj_s "{}") "z") == JP.JNull` échoue avec `JNull != JP.JNull` (même constructeur !). `=` (valeur) le gère (test_data_eq), mais `==` (assert de test) peut être un opérateur distinct qui ne délègue pas à `evalCmp`.

Vérifier : `(= JNull JNull)` vs `JNull == JNull` dans un test.

## Contournement actuel

Ne pas utiliser `==` directement sur un JVal. Passer par `jv_as_int`/`jv_as_str` (extrait un `Int`/`Str` littéral avant `==`). C'est ce que fait test_json_v1 pour arrays.

## Impact

- JSON V1 object **partiel** : parse `{}` (vide) mais pas `{"k":v}`.
- HTTP body JSON : bloqué tant que H1/H2 n'est pas tranché.
- Métacircularité : non impactée (n'utilise pas json_obj_get).

## Effort

1 session pour H1+H2.

## H3 (nouveau) : `jv_get` ne matche pas `(JVCons x rest) 0`

Test discriminant : `jv_get (JVCons (JNum 10) JVNil) 0` echoue,
alors que `jv_len (JVCons (JNum 10) JVNil)` passe (3/4 sur
jget2.hvn : inline_len OK, inline_get KO).

**Cause probable** : pattern `jv_get (JVCons x rest) 0` avec un
litteral `0` en 2e position du pattern. Peut-etre le pattern
litteral ne matche pas les args calcules, ou l'ordre de matching
est en cause (2e clause jv_get (JVCons _ rest) n ne matche pas
non plus, retourne JNull par defaut).

**Impact** : `arr_get0`, `arr_get2` retires de test_json_v1.hvn.
Acces par index cassé (mais jv_len fonctionne).

**Fix probable** : meme famille que selfrecursion (parsePostfix)
ou 0-pattern def. 1 session avec test discriminant.


## Mise à jour 2026-10-19 apres discriminant H1

- Pattern `(LLCons (PP k v) rest) k2` avec `PP Str Int` : 5/5
  en isolation (h1disc.hvn). Donc le pattern lui-meme marche.
- `json_obj_get (JPCons (JPair "a" (JNum 42)) JPNil) "a"` : KO
  meme en construction manuelle (faux positif precedent : c'etait
  `jv_get` qui manquait, pas `json_obj_get`).
- Import + pattern : 3/3 (imp.hvn). Pas le fossile #4.

**Hypothese residuelle** : difference entre `PP Str Int` (Str type)
et `JPair Str JVal` (Str + constructeur JVal imbrique en 2e arg).
Un test direct `JPCons (JPair "a" (JNum 42)) JPNil` avec le pattern
`(JPCons (JPair k v) rest)` trancherait. Non fait (cutoff).

**Contournement** : utiliser `jv_get` sur arrays, pas `json_obj_get`
sur objects avec cles. JSON object reste partiel (parse {} vide
mais pas de lookup sur cle non-vide).

H3 (jv_get) : RESOLU, `jv_get` ajoute, 2/2.
