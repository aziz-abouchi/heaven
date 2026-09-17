# Chapitre 9 — Real World

> *« La théorie, c'est quand on sait tout et que rien ne fonctionne.
> La pratique, c'est quand tout fonctionne et que personne ne sait
> pourquoi. »*

Jusqu'ici, on a manipulé des valeurs abstraites : listes, streams,
théorèmes. Il est temps de faire quelque chose d'utile. Ce chapitre
montre comment Heaven interagit avec le monde extérieur.

## Lire un fichier

Heaven expose quelques primitives pour les entrées-sorties. Par
exemple, pour lire un fichier :

    let contenu = readFile "data.txt" in ...

`readFile` rend le contenu sous forme de chaîne. Si le fichier
n'existe pas, Heaven retourne une erreur. On la capture avec `handle` :

    let resultat = handle (readFile "data.txt") errorHandler in ...

Cette séparation entre lecture (pure) et gestion d'erreur
(interceptée) est au cœur du modèle.

## Écrire un fichier

Symétrique :

    writeFile "sortie.txt" "bonjour"

`writeFile` ne rend rien d'intéressant (`Unit`), mais il écrit
réellement. C'est un **effet**, comme ceux du chapitre 6.

## Le serveur HTTP

Heaven embarque un serveur HTTP minimal, appelé **Vessel**. On le
lance en même temps que le noyau :

    $ heaven 8080

Le serveur démarre sur un port dérivé (généralement `8080 + 2919 =
10999`). Il sert :

- `/` : la page d'accueil (REPL web)
- `/heaven.wasm` : le module WebAssembly
- `/test_heaven.js` : les tests navigateur
- `/api/*` : quelques endpoints JSON

C'est ce qui permet d'utiliser Heaven depuis un navigateur, sans rien
installer.

## Les acteurs

Un **acteur** est un objet qui a un état et qui réagit aux messages.
C'est un modèle de concurrence classique (Erlang, Akka), et Heaven
l'implémente nativement.

Définir un handler :

    fn counterHandler(state, msg) = (+ state msg)

On a un état (`state`) et un message (`msg`). Le handler rend le
nouvel état.

Spawner un acteur :

    let Counter = 0 with counterHandler

`Counter` est un acteur avec l'état initial 0 et le handler
`counterHandler`. On lui envoie des messages :

    send(Counter, 10)   -- retourne 10
    send(Counter, 5)    -- retourne 15

À chaque message, l'état est mis à jour. On peut le consulter :

    state(Counter)      -- retourne 15

Les acteurs sont **séquentiels** : un message à la fois. Pas de course,
pas de verrous. C'est le modèle d'Erlang, et c'est particulièrement
agréable pour le code concurrent.

## Concurrence et parallélisme

Heaven n'a pas encore de vrai parallélisme (pas de threads user-space
avec préemption). Les acteurs sont séquentiels. Mais le modèle est
prêt : le jour où on ajoute un scheduler, les acteurs existants
tourneront en parallèle sans changement.

En attendant, on peut utiliser `perform` pour simuler des tâches
longues et les ordonnancer manuellement.

## Appeler du code C

Heaven peut appeler des fonctions C via l'**ABI**. On déclare :

    extern fn puts(s: String) -> Int

Puis on appelle :

    puts "bonjour"

C'est la base pour l'interopérabilité. Le compilateur TCC embarqué
compile le C à la volée, et Heaven fait le pont.

## Embarquer Heaven

Heaven s'utilise aussi comme bibliothèque. Le module `heaven_expr`
expose :

- `Heaven.init(allocator)` : crée une instance
- `heaven.eval(source)` : évalue du code
- `heaven.deinit()` : libère

On peut intégrer Heaven dans une application C, Python, ou autre. Le
module WebAssembly (`heaven.wasm`) est l'exemple le plus abouti : il
tourne dans un navigateur, avec le même code que le natif.

## Le REPL web

C'est le point d'entrée le plus accessible : ouvrez
`http://localhost:10999/` dans un navigateur. Vous avez un REPL
complet, identique à celui du terminal, mais dans la page.

Vous pouvez :

- taper des expressions et voir le résultat
- charger des fichiers `.hvn`
- exécuter les tests
- voir le rendu LaTeX des formules

C'est utile pour enseigner, pour démontrer, ou pour tester sans
installer.

## Récapitulatif

- `readFile`, `writeFile` pour les entrées-sorties de base.
- Vessel sert des pages web et des API.
- Les **acteurs** modélisent la concurrence sans verrous.
- L'ABI permet d'appeler du C.
- Heaven s'embarque comme bibliothèque.
- Le REPL web est identique au natif.

Au dernier chapitre, on ouvre le capot : comment Heaven est construit à
l'intérieur, et pourquoi ça compte.
