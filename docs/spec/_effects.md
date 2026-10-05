# Heaven — Effects, `perform` / `handle` et suspension

> Statut : fondations expérimentales mesurées
> Portée : `src/core/engine_expr.zig`

## 1. État actuel

Le système `perform` / `handle` est expérimental.

`perform` utilise actuellement `Engine.last_performed` pour exposer la dernière valeur produite.

`handle` évalue actuellement la computation puis inspecte `last_performed`.

Il n'y a actuellement aucune capture de continuation.

Le mécanisme actuel ne doit donc pas être décrit comme un shallow handler ou un deep handler.

## 2. `perform`

Le comportement actuel est essentiellement :

    perform operation argument
        → évaluer argument
        → last_performed = résultat
        → retourner le résultat

Lorsqu'un `io_handler` est installé et qu'aucun `handle` explicite n'est actif, `perform` peut dispatcher vers cet handler.

Le dispatch actuel utilise un label textuel.

Ce mécanisme est expérimental et ne constitue pas encore la sémantique définitive des effets de Heaven.

## 3. `handle`

Le `handle` actuel :

1. active `in_handle` ;
2. évalue la computation ;
3. récupère `last_performed` ;
4. restaure l'état précédent ;
5. appelle éventuellement le handler avec cette valeur.

Il n'y a pas :

- de capture de continuation ;
- de reprise exacte ;
- de continuation one-shot ;
- de sémantique shallow/deep formellement implémentée.

## 4. `last_performed`

`last_performed` est un seul emplacement :

    Engine.last_performed : ?expr.Id

Plusieurs `perform` peuvent donc s'écraser mutuellement.

Le mécanisme actuel est un mécanisme one-slot / post-evaluation.

Le terme « one-shot » ne signifie pas continuation one-shot : aucune continuation n'est capturée.

## 5. Effets structurés — direction future

La direction architecturale est de représenter les opérations d'effet comme des `Expr` normales.

Exemple conceptuel :

    perform (ReadFile cap path)

plutôt que :

    perform "ReadFile" path

Les opérations pourront être par exemple :

    ReadFile cap path
    WriteFile cap path bytes
    HttpGet cap url
    Send socket message
    Receive socket

Aucun Effects IR séparé n'est prévu.

## 6. Capacités

Les effets système doivent être contrôlés par des capacités explicites.

Exemples :

    FileCap
    NetCap
    ProcessCap
    StorageCap
    DomCap
    WebSocketCap
    RemoteCap

Le MVP n'impose pas `Eff<T>`.

Une signature comme :

    read_one : FileCap -> Path -> Bytes

reste possible, avec l'effet exprimé dans le corps.

## 7. `do`

`do` reste du sucre syntaxique pour les opérations de liaison.

Il n'introduit pas de nouvelle primitive runtime.

## 8. Safepoints et `reductions`

Le moteur possède déjà un safepoint coopératif.

À chaque appel d'évaluation :

    if reductions == 0
        → SuspendRequested

puis :

    reductions -= 1

`evalWithBudget` installe temporairement un budget de réductions.

À épuisement :

    EvalOutcome.suspended

Le budget et le fuel sont ensuite restaurés.

## 9. Signification de `.suspended`

`.suspended` signifie actuellement :

    l'évaluation a atteint un safepoint alors que son budget était épuisé.

Il ne signifie pas :

    une continuation a été capturée et peut être reprise.

Donc :

    suspended != resumable continuation

## 10. `evalWithRetry`

`evalWithRetry` augmente progressivement le budget et recommence l'évaluation depuis le début.

Schéma :

    evaluate(id)
        → suspended
        → budget augmenté
        → evaluate(id) depuis le début

Le code documente ce mécanisme comme redémarrable et valide uniquement pour du calcul pur.

Il ne constitue pas un mécanisme général pour les effets.

## 11. Budget versus continuation

Deux mécanismes doivent rester distincts.

`reductions` répond à :

    Combien de travail cette évaluation peut-elle effectuer avant de rendre la main ?

Une continuation répond à :

    Comment reprendre exactement cette computation là où elle a été interrompue ?

Donc :

    reductions = quand rendre la main
    continuation = comment reprendre

## 12. D8

D8 est la future mécanique générale de continuation et de suspension.

> D8 est la mécanique générale de suspension du langage, pas une fonctionnalité spécifique au HTTP.

Conceptuellement :

    evaluate
        → suspension
        → continuation
        → resume / discard

Un futur `perform` pourra évoluer vers un modèle conceptuel :

    perform operation
        → capture continuation k
        → handler(operation, k)

La forme exacte de cette API reste à définir.

D8 n'est pas encore implémenté.

## 13. Laziness

La direction architecturale est que Heaven soit lazy lorsque la sémantique le permet.

Une stream pure peut utiliser des thunks sans nécessiter D8.

Une stream effectful nécessitant :

    ReadFile
    HttpGet
    Receive
    perform ...

a besoin d'un mécanisme de suspension et de reprise.

D8 est destiné à fournir cette mécanique.

## 14. Convergence

Le même mécanisme de suspension doit pouvoir servir à terme pour :

    lazy streams
    actors
    events
    scheduler
    HTTP
    WebSocket
    RPC
    remote execution

D8 est donc une primitive générale, pas une fonctionnalité HTTP.

## 15. État d'implémentation

| Fonctionnalité | État |
|---|---|
| perform | expérimental |
| handle | expérimental |
| last_performed | implémenté |
| IO handler | implémenté |
| safepoint | implémenté |
| reductions | implémenté |
| evalWithBudget | implémenté |
| evalWithRetry | implémenté |
| suspension coopérative | partielle |
| reprise exacte | non implémentée |
| continuation | non implémentée |
| D8 | futur |
| handlers continuation-based | futur |
| lazy effectful streams | futur |
| scheduler basé sur continuation | futur |

## 16. Contraintes

1. Les effets restent des `Expr`.
2. Aucun Effects IR séparé.
3. Les capacités contrôlent les ressources.
4. `reductions` ne doit pas être confondu avec D8.
5. `evalWithRetry` reste réservé aux calculs redémarrables sans effets problématiques.
6. D8 ne doit être conçu qu'après mesure des besoins réels de suspension.
7. Les mécanismes futurs doivent être mesurés sur le code existant avant de figer leur sémantique.

## 17. Décision actuelle

    perform / handle
        → expérimental
        → last_performed
        → aucune continuation

    reductions
        → safepoint coopératif
        → budget d'évaluation

    evalWithBudget
        → interruption contrôlée
        → aucune reprise exacte

    evalWithRetry
        → restart depuis le début
        → calcul pur uniquement

    D8
        → future continuation machine
        → fondation générale de suspension
