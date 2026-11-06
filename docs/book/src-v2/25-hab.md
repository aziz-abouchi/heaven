# Chapitre 25 — Hab : le Web natif en Heaven

> **Piège d'entrée.** Hab n'est pas React. Ce n'est pas non plus du MVC,
> ni du Svelte, ni du HTMX. C'est **MVU avec optiques** — et la
> différence n'est pas cosmétique : elle détermine tout ce qui suit.
> Si vous lisez ce chapitre avec les réflexes React, vous allez écrire
> du code qui compile et fait *presque* la bonne chose.

## 1. Pourquoi un framework Web natif

Un langage sans Web est un langage de niche. Heaven a déjà un serveur
HTTP natif (ch. 24), un stdlib réseau (TCP, UDP, bitstrings), et un
serveur statique en Heaven pur. Ce qui manque, c'est le **côté
navigateur** : un composant qui prend un modèle, le rend, et le met
à jour.

Hab est ce framework. Il tient en **5 modules** (`lib/hab/*.hvn`) et
**9 tests** dans `tests/hab/` :

| Module | Rôle | Tests |
|---|---|---|
| `app` | cycle MVU, composition d'enfants | 3 (`app_2children`, `app_3children`, `app_tick_list`) |
| `render` | HTML par catamorphisme | 3 (`render_basic`, `render_quickcheck`, `render_smocker`) |
| `router` | dispatch par route, optiques | 3 (`router_basic`, `router_quickcheck`, `router_smocker`) |

**Ce qui est testé** : les trois. **Ce qui n'est pas testé** : le
runtime navigateur (chapitre 27 §4, à vérifier dans le repo). Le
serveur HTTP ch. 24 sert des fichiers statiques ; Hab est censé
servir du **dynamique** — mais c'est la cible, pas l'état.

> **Capot d'entrée.** Ce chapitre décrit Hab **tel qu'il est testé**,
> pas tel qu'il est rêvé. Quand un bout est cible (runtime navigateur,
> supervision OTP-like, HKT complet), c'est écrit.

## 2. Piège : MVU ≠ React ≠ MVC

Voici les trois architectures que les gens confondent :

| Architecture | Modèle | Mise à jour | Rendu |
|---|---|---|---|
| **MVC** (Rails, Django) | mutable | controlleur modifie | template re-rendu |
| **React** | immutable (useState) | setState → re-render | virtual DOM diff |
| **MVU (Hab)** | immutable | `update : Msg -> Model -> Model` | catamorphisme |

La différence critique est la **colonne 3** :

- **MVC** re-rend le template à chaque requête. Pas d'état entre deux
  requêtes (sauf en session).
- **React** diff un virtual DOM pour minimiser les écritures réelles.
  Le state est local au composant (`useState`), propagé par hooks.
- **MVU (Hab)** applique un **catamorphisme** sur l'AST du modèle pour
  produire du HTML. Pas de virtual DOM, pas de diff — juste un fold.

Vous voyez la conséquence ? **MVU ne fait pas de diff**. Le modèle est
la source de vérité, et à chaque `update`, on **re-fold** tout. C'est
lent en théorie, suffisant en pratique, et **beaucoup plus simple** à
raisonner : pas d'état caché, pas de hooks, pas de cycle de vie.

## 3. Le counter — modèle minimal

Le plus petit composant Hab, celui que `tests/hab/app_2children.hvn`
exerce, c'est un compteur. Trois choses : un modèle, un message, une
fonction `update`.

```heaven
-- modèle : un entier
model = 0

-- message : incrémenter ou décrémenter
msg_inc = Inc
msg_dec = Dec

-- update : Msg -> Model -> Model
update m s =
  match m with
  | Inc -> s + 1
  | Dec -> s - 1

-- vue : Model -> Html
view s = html_div [ text (show s) ]
```

`update` est **pure** : elle prend un message et un modèle, rend un
nouveau modèle. Pas d’effet, pas d’état caché, pas de `setState`.
C’est le point que React rend difficile à voir : `setState` **mute**
l’état interne du composant ; `update` en MVU **construit** un
nouveau modèle.

### `dispatch_from` — le threading pur

Dans `27-hab.md` v1, une fonction revient sans cesse :
`dispatch_from`. C'est le cœur du MVU avec optiques.

```heaven
dispatch_from lens msg model =
  let child_state = lens.get model in
  let new_child   = child_update msg child_state in
  lens.set new_child model
```

Trois étapes, toutes pures :
1. **Lire** l'état de l'enfant via une optique `lens.get`.
2. **Appliquer** la mise à jour (`child_update msg`).
3. **Écrire** le nouvel état via `lens.set`.

Pas de mutation, pas de référence partagée, pas de `useState`. Le
parent sait **exactement** ce qui change chez l'enfant, et l'enfant
ne sait **rien** du parent. C'est ce que `31-hab-mvu.md` appelle
« l'idée Hab » : la séparation Modèle / Vue est une **optique**, pas
une frontière d'exécution.

## 4. Capot : render par catamorphisme (pas de virtual DOM)

Voici le point où Hab s'éloigne le plus de React. `36-hab-render.md`
tient en 35 l. et pose une idée simple : **rendre = un fold sur l'AST**.

Concrètement, le modèle est un arbre. `render` est une fonction qui :

1. parcourt l'arbre,
2. à chaque nœud, applique une transformation,
3. concatène les résultats en HTML.

C'est exactement une **catamorphisme** — un fold qui consomme un
arbre récursif. `render_basic.hvn`, `render_quickcheck.hvn` et
`render_smocker.hvn` testent trois aspects :

| Test | Ce qu'il vérifie |
|---|---|
| `render_basic` | cas triviaux : `text`, `div` vide, `div` avec un enfant |
| `render_quickcheck` | propriétés aléatoires : profondeur, largeur, ordre |
| `render_smocker` | effets simulés (mock I/O) — voir `_runtime_gaps.md` |

**Conséquence** : à chaque `update`, on **re-fold tout**. Pas de diff,
pas de reconciliation, pas de "shouldComponentUpdate". Le HTML produit
est **le même** à modèle égal — c'est testé par `render_quickcheck`
(propriété : `render s = render (update (noop) s)`).

Vous vous demandez : « mais c'est lent, non ? » Oui, en théorie. En
pratique, pour les composants que Hab cible (formulaires, listes,
dashboards), le coût de re-fold est négligeable devant le coût de
transmission HTTP. **MVU échange de la performance brute contre de la
simplicité de raisonnement** — c'est un choix, pas un défaut.

## 5. Router : Lens + foncteur + HKT

`37-hab-router.md` (49 l.) est le morceau théorique. Trois concepts
s'empilent :

### Lens(RouteState, Child)

Un router a un état global (`RouteState`) et un état par route
(`Child`). L'optique `Lens(RouteState, Child)` donne :

- `get` : `RouteState → Child`
- `set` : `Child → RouteState → RouteState`

C'est exactement ce que §3 (`dispatch_from`) utilise. Rien de nouveau,
juste une composition.

### Foncteur `Path → A`

Une route est une fonction `Path → A`. `Path` est la clé (string), `A`
est le composant. C'est un foncteur au sens strict : on peut mapper
sur `A` sans toucher à `Path`.

```heaven
router_mk : (Path -> A) -> Router A
router_map : (A -> B) -> Router A -> Router B
```

### HKT : `router_mk strat = ∀h`

`router_mk` prend une stratégie `strat` (match exact, préfixe, regex)
et rend un router **polymorphe en son handler**. C'est du HKT (Higher-
Kinded Type) — le `∀h` que `32-hab-app.md` appelle « Imports
unprefixed » est un artefact du parser, pas du typage. Ce qui compte,
c'est que `router_mk` **ne sait pas** ce qu'il va rendre, et c'est
voulu.

**Tests** : `router_basic` (3 cas), `router_quickcheck` (propriétés
sur le dispatch), `router_smocker` (mock du handler). Comme render :
mêmes 3 angles (basique, propriété, mock).

> **Capot.** HKT est **partiel** en Heaven. Le `∀h` de `router_mk`
> est testé, mais pas garanti pour tous les cas de figure. Si vous
> avez besoin d'un HKT complet, vous êtes en avance sur le langage —
> voyez `docs/spec/_hkt.md` si elle existe, sinon remontez à
> `_runtime_gaps.md`.

## 6. Ce qui tourne vraiment (vs ce qui est cible)

Comme pour le chapitre 24, la frontière est explicite. Voici l'état
tiré de `27-hab.md` §6 (« Contraintes connues ») et des 9 tests :

| Chose | État | Preuve |
|---|---|---|
| Composition d'enfants (`app_2children`, `app_3children`) | ✅ | tests |
| `dispatch_from` par optique | ✅ | `app_tick_list` |
| Render HTML par catamorphisme | ✅ | `render_basic` |
| Propriétés render (`render ∘ noop = render`) | ✅ | `render_quickcheck` |
| Router par `Lens(RouteState, Child)` | ✅ | `router_basic` |
| Propriétés router (dispatch pur) | ✅ | `router_quickcheck` |
| Mocks I/O (render, router) | ✅ | `render_smocker`, `router_smocker` |
| **Runtime navigateur** | ⚠️ cible | §4 de `27-hab`, à vérifier |
| **Supervision OTP-like** | ⚠️ vision | `31-hab-mvu.md` §« Vision — supervision » |
| **HKT complet** | ⚠️ partiel | voir §5 capot |

**Règle de lecture** : les 9 tests couvrent la **logique** MVU
(update, render, dispatch). Ils ne couvrent **pas** le pont
navigateur — c'est-à-dire le code qui prend le HTML produit et le
pose dans le DOM. Ce pont est en JavaScript, hors du périmètre
Heaven, et donc hors du périmètre des tests. Si vous cherchez à
debugger un composant Hab qui « ne s'affiche pas », vérifiez d'abord
le pont JS, pas `update`.

## Exercices

### Ex. 1 — Counter minimal (guidé)

Reproduisez le counter de §3 : modèle entier, messages `Inc`/`Dec`,
`update` pure, `view` qui affiche le nombre. Testez mentalement :
`update Inc 0 = 1`, `update Dec 0 = -1`, `update Inc (update Inc 0) = 2`.

**Question** : que se passe-t-il si vous remplacez `update m s = s + 1`
par `update m s = s + 1; s + 1` (double incrément) ? Notez le résultat.

### Ex. 2 — `dispatch_from` avec deux enfants (libre)

Reprenez `app_2children.hvn`. Deux enfants, chacun avec son optique
`Lens(ParentState, Child)`. Écrivez `dispatch_from` pour chacun, et
vérifiez qu'un message sur l'enfant A ne touche pas l'enfant B.

**Question** : pourquoi `dispatch_from` est-elle *pure* ? Que se
passerait-il si elle mutait `model` en place plutôt que de rendre
un nouveau modèle ?

### Ex. 3 — Render : catamorphisme vs template (libre)

Écrivez `render` pour un modèle à 3 niveaux : `div` > `span` > `text`.
Comparez avec un template HTML classique (`"<div><span>…</span></div>"`).

**Question** : que se passe-t-il si le texte contient des caractères
spéciaux (`<`, `>`, `&`) ? Le catamorphisme les échappe-t-il
automatiquement, ou faut-il une étape d'échappement séparée ? (Indice :
regardez `render_basic.hvn`.)

### Ex. 4 — Router avec stratégie (casse)

Écrivez `router_mk` avec deux stratégies : match exact (`"/foo"`) et
préfixe (`"/foo/*"`). Testez `"/foo"` et `"/foo/bar"`.

**Question** : que se passe-t-il si deux routes matchent ? Le premier
gagne, le dernier gagne, ou erreur ? (Indice : `router_quickcheck`
teste cette propriété — vérifiez ce qu'il attend.)

---

## Ce qu'il faut retenir

1. **Hab = MVU + optiques** — ni React, ni MVC. La différence est le
   rendu par **catamorphisme**, pas par diff.
2. **`update` est pure** — prend un message et un modèle, rend un
   nouveau modèle. Pas de mutation, pas d'état caché.
3. **`dispatch_from` est une optique** — le parent sait ce qui change
   chez l'enfant via `Lens(Parent, Child)`.
4. **Render = fold sur l'arbre** — pas de virtual DOM. Re-fold à
   chaque update. Lent en théorie, suffisant en pratique, simple à
   raisonner.
5. **Ce qui est testé = la logique MVU** (9 tests). Ce qui n'est pas
   testé = le pont JS navigateur. Ne confondez pas les deux quand
   vous debuggez.

Le chapitre 25 (annexe ? ou ouverture vers la suite) reprend du
service — le livre va maintenant vers les outils, l'écosystème, et
les promesses à long terme (selfhost, HoTT, essaim).
