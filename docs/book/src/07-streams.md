# Chapitre 7 — Streams

Un **stream** est une suite d'éléments. Tu en as déjà vu dans les
chapitres précédents, sous forme de `Cons x rest | End`. Ce chapitre
montre ce qui les rend vraiment utiles : leur **paresse**.

## La structure

    data Stream a = Cons a (Stream a) | End

Un stream est soit vide (`End`), soit un élément suivi d'un autre
stream (`Cons x rest`). Rien de nouveau. La différence : dans un
stream **paresseux**, `rest` n'est pas encore évalué.

## delay et force

Deux magics manipulent le calcul différé :

    delay expr      -- capture expr sans l'evaluer
    force t         -- evalue t (une seule fois, memoise)

`delay` produit un **thunk** : une valeur qui représente un calcul
en attente. `force` la déclenche. Le résultat est mémorisé : un
thunk n'est calculé qu'une fois.

    let t = delay (+ 1 2) in
    (+ (force t) (force t))   -- = 3 + 3 = 6, (+ 1 2) calcule une fois

## Générer un stream infini

    stream_nats_from n = Cons n (delay (stream_nats_from (+ n 1)))

    (stream_take 5 (stream_nats_from 0))
    -- (Cons 0 (Cons 1 (Cons 2 (Cons 3 (Cons 4 End)))))

La récursion ne s'arrête jamais dans `stream_nats_from`, mais elle
n'est **pas exécutée** tant que personne ne `force` la queue. On
peut écrire `stream_nats_from 0` sans exploser la pile.

Autres générateurs :

    stream_repeat x         -- Cons x (Cons x (Cons x ...))
    stream_iterate f x      -- x, f x, f (f x), ...

## Consommer un stream

`stream_take n s` limite à n éléments :

    (stream_take 5 (stream_nats_from 0))
    -- 5 éléments, puis End

`stream_nth n s` extrait le n-ième :

    (stream_nth 3 (stream_nats_from 0))   -- 3
    (stream_nth 5 (Cons 1 End))           -- 0 (au-delà de End)

`stream_sum s` somme les éléments (sur un stream fini) :

    (stream_sum (stream_take 5 (stream_nats_from 0)))   -- 10
    (stream_sum (stream_take 3 (stream_repeat 7)))      -- 21

`stream_length s` compte les éléments d'un stream fini :

    (stream_length (stream_take 5 (stream_nats_from 0)))   -- 5

## Transformations

Les transformations sont **paresseuses** : elles ne calculent rien
tant qu'aucun `force` ne l'exige.

    stream_map f End = End
    stream_map f (Cons x rest) = Cons (f x) (delay (stream_map f (force rest)))

    (stream_sum (stream_take 4 (stream_map (lambda x -> (* x x))
                                          (stream_nats_from 0))))
    -- 0 + 1 + 4 + 9 = 14

`stream_filter` garde les éléments qui satisfont un prédicat :

    (stream_length (stream_filter (lambda x -> (= (% x 2) 0))
                                  (stream_take 5 (stream_nats_from 0))))
    -- les pairs parmi 0..4 : 0, 2, 4 → 3

## Le pipeline complet

C'est là que la paresse paie : on peut composer **map**, **filter**,
**take**, **sum** sans jamais matérialiser d'intermédiaire.

    (stream_sum
      (stream_take 1000
        (stream_filter (lambda x -> (= (% x 2) 0))
          (stream_map (lambda x -> (* x 10))
            (stream_nats_from 1)))))
    -- somme des 1000 premiers multiples de 20

Chaque étape ne calcule que ce qui est demandé. Sur un stream
**infini**, aucune étape ne bloque, parce qu'aucune ne demande la
totalité.

## Pourquoi « paresseux » ?

Compare avec une liste **stricte** (celle de `core/std/list.hvn`) :

    -- Strict : calcule tous les éléments d'abord
    -- Laziness : ne calcule qu'à la demande

Un stream paresseux permet :

- **Streams infinis** (`stream_nats_from 0`).
- **Pipelines** où chaque étape ne fait que ce qu'elle doit.
- **Séparation** : la génération est infinie, la consommation
  (via `take`, `nth`) borne.

## Différence avec `List`

`core/std/list.hvn` a ses propres `map`, `filter`, `take`, **stricts**.
`core/stream.hvn` a les mêmes, **préfixés `stream_`** — pour éviter
les collisions. Les deux coexistent :

| Type | Module | Style | Taille |
|---|---|---|---|
| `List a` | `core/std/list.hvn` | strict | finie |
| `Stream a` | `core/stream.hvn` | paresseux | finie ou infinie |

Utiliser `stream_take` sur un stream fini marche exactement comme
sur un stream infini — la différence n'apparaît que si on oublie
`take`.

## Limites connues

- **`delay` n'existe qu'à l'interpréteur**. Le code compilé (QBE,
  WASM) n'a pas encore de thunks.
- **Mémoization par Id**. Un thunk forcé garde sa valeur jusqu'à la
  fin du programme. Pas de GC.
- **`let` multi-lignes** : mettre le corps sur une seule ligne
  (voir annexe B).
- **Pattern `zero`** : les clauses `f zero = ...` ne matchent pas
  les littéraux `0`, `1`, ... Utiliser `if (= n 0)` dans une
  fonction auxiliaire.

## À retenir

- Un **stream paresseux** est une valeur, comme une liste, mais
  dont la queue est un thunk.
- `delay` crée, `force` déclenche (et mémorise).
- On compose librement : `map`, `filter`, `take`, `sum`.
- Les streams infinis sont utilisables tant qu'on les **borne**.
- Les streams stricts (`List`) et paresseux (`Stream`) coexistent.

## Pour aller plus loin

- `tests/test_stream_lazy.hvn` : 8 tests qui couvrent tous les
  exemples de ce chapitre.
- `docs/DECISIONS.md` (D12) : décision de design de la laziness.
- `docs/spec/_syntax_gaps.md` : quirks du parser rencontrés sur
  les streams.
