# Chapitre 18 — Plusieurs handlers, un abandon

> **Piège d'entrée.** Le chapitre 16 vous a montré *un* `handle_rec`, seul,
> qui intercepte *un* `perform`, et reprend *une* fois via `k`. Ce chapitre
> attaque le cas réel : quand il y en a plusieurs, et quand on décide de
> **ne pas** reprendre. Deux choses que 16 n'a pas dites, et qui sont
> celles qui se cassent en pratique.

## 1. Pourquoi `init` : l'état threadé n'est pas un détail

Rappel de la signature :

```heaven
(handle_rec body handler init)
```

Le troisième argument, `init`, est l'état passé à `body`. Sans lui, `body`
n'aurait aucun moyen de compter ses itérations — `handle_rec` n'a **pas**
de variable mutable interne. C'est le handler qui décide quoi faire de `v`,
mais c'est `body` qui porte l'état.

Exemple minimal : une boucle de 3 itérations qui accumule un compteur dans
`body` lui-même.

```heaven
(handle_rec
  (lambda s ->
    (if (>= s 3) s (perform "loop" (+ s 1))))
  (lambda v k -> (k v))
  0)
# => 3
```

Décomposons :

1. `body 0` → `(perform "loop" 1)`.
2. Handler : `v = 1`. `(k 1)` reprend `body` juste après le `perform`,
   avec `1` en place de l'appel.
3. `body 1` → `(perform "loop" 2)`. Etc.
4. `body 3` → `3` (cas de base, pas de `perform`).

**Point clé** : `k v` n'incrémente rien. C'est `body` qui a calculé `(+ s 1)`
*avant* le `perform`, et qui le reprend via `k`. L'état « circule » dans
`body`, pas dans le handler. **`init` est l'amorce de ce circuit.**

> **Capot pratique.** Si votre `body` ne fait pas varier `s`, `handle_rec`
> boucle. La terminaison est votre responsabilité. `handle_rec` ne détecte
> pas les boucles infinies.

## 2. Piège : deux `handle_rec` imbriqués ne se marchent pas dessus

C'est **le** point que 16 ne dit pas, et que `tests/test_effects_rec_nested.hvn`
prouve (67 l. de tests, 4 scénarios). Voici l'extrait qui compte :

```heaven
inner_body s = (if (= s 0) 100 (perform "inner" s))
inner_handler v k = (k 0)

outer_body s =
  (if (= s 0)
    (handle_rec inner_body inner_handler 1)
    (perform "outer" s))
outer_handler v k = (k 0)

(handle_rec outer_body outer_handler 1)
# => 100
```

Scénario, décomposé :

1. `outer_body 1` → `(perform "outer" 1)`. Pile : `[outer]`. Capturé par
   `outer_handler`, `(k 0)` reprend.
2. `outer_body 0` → `(handle_rec inner_body inner_handler 1)`. Pile :
   `[outer, inner]`. `inner_body 1` → `(perform "inner" 1)`. Capturé par
   `inner_handler` (le **sommet** de la pile).
3. `inner_body 0` → `100`. `inner` rend `100`. `outer` rend `100`.

**Pourquoi ça marche** : chaque `handle_rec` **empile** son handler sur
`prompts`, et chaque `perform` est capturé par le **sommet** de la pile.
Pas de slot ad-hoc, pas de variable partagée. C'est ce que le test
`nested : distinction des valeurs (200 + 100 = 300)` vérifie : sans pile,
`inner` recevrait la capture d'`outer` et le résultat serait faux.

### Corollaire : l'ordre compte

Si les deux `handle_rec` gèrent **le même tag**, le plus **interne** gagne :

```heaven
h_plus10  = (lambda v k -> (k (+ v 10)))
h_plus100 = (lambda v k -> (k (+ v 100)))

(handle_rec (lambda s -> (perform "tick" s)) h_plus10
  (handle_rec (lambda s -> (perform "tick" s)) h_plus100 0))
# => 100

(handle_rec (lambda s -> (perform "tick" s)) h_plus100
  (handle_rec (lambda s -> (perform "tick" s)) h_plus10 0))
# => 10
```

Le résultat **s'inverse** parce que le `perform` est capturé par le handler
le plus proche. **Règle pratique** : en cas de doute, un tag par `handle_rec`.
Le multi-handler sur même tag est un outil, pas un défaut.

## 3. Abandonner `k` : la même mécanique que `@throw`

16 a mentionné qu'on peut ne pas appeler `k`. Ce chapitre en fait la
**deuxième primitive** à côté de `k`.

```heaven
(handle_rec
  (lambda s -> (if (< s 0) (perform "fail" "negatif") s))
  (lambda v k -> (if (== v "negatif") v (k v)))
  -5)
# => "negatif"
```

Regardez le handler :
- `"negatif"` → on rend `v` **sans** appeler `k` → abandon total.
- sinon → `(k v)` → reprise normale.

C'est exactement ce que fait `@throw` dans `test_continuations.hvn`
(15/15) — mais `@throw` est **intégré** au mécanisme des `@prompt`
(continuations délimitées). `handle_rec` + abandon est la version
manuelle de la même chose. Vous verrez `@prompt` plus loin ; ici, retenez
la **forme** :

| Vous voulez… | Vous faites… |
|---|---|
| reprendre | `(k v)` |
| abandonner | rendre `v` sans appeler `k` |
| transformer | rendre n'importe quoi sans appeler `k` |

Trois comportements, une seule primitive (`k` ou pas `k`). Pas besoin de
`try`/`catch` séparés pour les erreurs — le chapitre 18 en fait la
démonstration complète.

## 4. Ce qui existe vs ce qui n'existe pas

16 §10 a le tableau complet. Ici, seulement ce qui concerne **ce chapitre** :

| Mécanisme | État | Ce que ça veut dire |
|---|---|---|
| `handle_rec` imbriqués | testé (`test_effects_rec_nested.hvn`) | Utilisez la pile, ne la contournez pas. |
| Abandon de `k` | testé (`test_effects_rec.hvn`) | `throw` maison = ne pas appeler `k`. |
| `@prompt` / `@throw` | (`test_continuations.hvn`, 15/15) | Manière intégrée ; voir plus loin. |
| Ordre des handlers sur même tag | comportement émergent de la pile | Documenté par exercice, pas par test dédié. |
| Multi-shot (2 appels à `k`) | non testé, non garanti | Ne pariez pas dessus. |
| Deep vs shallow | non décidé | Ne spéculez pas. |

**Conséquence** : `stdlib/effects.hvn` est **court** exprès. Il expose
`resume k v = (k v)` pour la lisibilité, et c'est tout. Les magics
(`handle_rec`, `perform`, `@prompt`, `@throw`, `yield`) s'appellent
directement, **sans import qualifié** — c'est noté dans
`tests/test_effects.hvn` :

```heaven
import "stdlib/effects.hvn" as E
# (E.handle_rec …) NE MARCHE PAS.
# (handle_rec …) direct.
```

## Exercices

### Ex. 1 — Imbrication à valeurs distinctes (guidé)

Reproduisez `nested : distinction des valeurs (200 + 100 = 300)` :

```heaven
inner_body_b s = (if (= s 0) 100 (perform "inner-b" s))
inner_handler_b v k = (k 0)

outer_body_b s =
  (if (= s 0)
    (+ 200 (handle_rec inner_body_b inner_handler_b 1))
    (perform "outer-b" s))
outer_handler_b v k = (k 0)

(handle_rec outer_body_b outer_handler_b 1)
# => 300
```

**Question** : si vous remplacez `100` par `1000` dans `inner_body_b`,
quel est le résultat ? Pourquoi ?

### Ex. 2 — `throw` par abandon (libre)

Implémentez un effet `fail` polymorphe. Le handler rend `"negatif"` si
`s < 0`, sans jamais appeler `k`.

```heaven
(handle_rec
  (lambda s -> (if (< s 0) (perform "fail" "negatif") s))
  (lambda v k -> (if (== v "negatif") v (k v)))
  -5)
# => "negatif"
```

Testez avec `+5` et vérifiez que le résultat est bien `5` (et non `"negatif"`).

### Ex. 3 — Ordre des handlers sur même tag (libre)

Comparez les deux ordres d'imbrication avec `h_plus10` / `h_plus100`
(section 2). Notez les deux résultats. **Question** : quel handler est
« le plus proche » du `perform` ? Écrivez un commentaire dans votre code
qui l'explique à un futur lecteur.

### Ex. 4 — `@prompt` vs `handle_rec` (casse)

Ouvrez `tests/test_continuations.hvn` (15 tests, `@prompt`/`@throw`).
Trouvez un test qui abandonne via `@throw`, un autre via `handle_rec` +
abandon de `k`. **Question** : quelle est la différence de portée ?
(Indice : `@prompt` est **délimité** — il ferme une frontière, comme
`try`/`catch`. `handle_rec` est **général** — il ouvre un handler qui
peut rester actif à travers plusieurs `perform`. Relisez
`docs/spec/_continuations.md`.)

---

## Ce qu'il faut retenir

1. **`init` porte l'état** — `body` fait varier `s`, pas le handler.
2. **Les `handle_rec` s'imbriquent** — pile `prompts`, sommet gagne.
3. **L'ordre compte** — le plus interne gagne sur même tag.
4. **Abandonner `k` = `throw`** — une primitive, trois comportements
   (reprendre, abandonner, transformer).
5. **`@prompt`/`@throw`** — version délimitée, intégrée ; `handle_rec` +
   abandon — version générale, manuelle. Les deux coexistent.
6. **Multi-shot** : pas testé. **Deep/shallow** : pas décidé.

Le chapitre 18 applique tout ça au cas le plus fréquent : les **erreurs**
(`Result`, `Validation`, `Option`). Vous verrez que `Validation ≠ Result`
même quand les deux « gèrent une erreur » — et que c'est un choix de
handler.
