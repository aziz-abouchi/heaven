# Chapitre 23 — Validation : accumuler les erreurs

> *« Une monade s'arrête à la première erreur. Un applicatif les
>  accumule toutes. »*
> — Bryan Lonsdorf

Imaginez un formulaire avec 5 champs. L'utilisateur tape mal son
email, oublie son âge, et met un mot de passe trop court. Quelle
erreur afficher ?

**Option 1 — Séquentielle** : on arrête à la première erreur.
« Email invalide. » L'utilisateur corrige, retente, découvre
l'erreur suivante. Frustrant.

**Option 2 — Accumulative** : on vérifie tous les champs, on
collecte **toutes** les erreurs. « Email invalide, âge manquant,
mot de passe trop court. » L'utilisateur corrige tout d'un coup.

C'est la distinction entre **Monad** (séquentiel) et
**Applicative** (parallèle). Bryan Lonsdorf (Dr. Boolean,
auteur de *Mostly Adequate Guide to Functional Programming*) a
popularisé cette distinction.

## 1. Result : la monade séquentielle

    Result e a = Ok a | Err e

Avec `chain`, on enchaîne :

    parse_email(s) : Result String Email
    parse_age(s)   : Result String Int
    validate(p) :
      parse_email(p.email) |> chain (lambda email ->
        parse_age(p.age) |> chain (lambda age ->
          Ok (Pair email age)))

Dès la première `Err`, on s'arrête. Les étapes suivantes ne
tournent pas.

## 2. Validation : l'applicatif accumulatif

    Validation e a = Valid a | Invalid (List e)

Avec `ap`, on **combine** :

    validate(p) :
      ap (ap (ap (Valid (lambda e a -> Pair e a))
                  (parse_email(p.email)))
                  (parse_age(p.age)))
                  (parse_password(p.password))

Les trois parsers tournent. Si l'un échoue, son erreur est
**ajoutée** à la liste. Si deux échouent, on a deux erreurs.

## 3. Quand utiliser quoi

| Cas | Utiliser |
|---|---|
| Chaîne d'opérations dépendantes | `Result` (Monad) |
| Vérifications indépendantes | `Validation` (Applicative) |
| Parseur qui compose | `Result` |
| Formulaire utilisateur | `Validation` |
| Typechecker | `Validation` (accumuler toutes les erreurs) |
| Évaluation d'AST | `Result` (s'arrêter à la première) |

**Règle** : si les étapes sont **indépendantes**, utilisez
`Validation`. Si elles sont **dépendantes**, utilisez `Result`.

## 4. Impact sur Heaven

Heaven utilise cette distinction :

- Le **parser** renvoie `Result` : première erreur de syntaxe,
  on s'arrête.
- Le **typechecker** utilisera `Validation` : accumuler toutes
  les erreurs de type d'un module.
- Le **proof checker** est `Result` : premier but échoué, on
  arrête.

C'est un choix d'ergonomie. L'utilisateur d'un formulaire veut
**toutes** ses erreurs. L'utilisateur d'un parseur veut **la**
première, pour corriger au plus tôt.

## Ce qu'on a appris

- **Result** (Monad) est **séquentiel** : première erreur, stop.
- **Validation** (Applicative) est **accumulatif** : toutes les
  erreurs en un coup.
- Les deux ont leur place : parser → Result, formulaire → Validation.
- Cette distinction vient de **Bryan Lonsdorf** et de la
  communauté Fantasy Land.
- Heaven utilise `Result` pour le parser et `Validation` pour le
  futur typechecker.
