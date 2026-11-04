# Chapitre 19 — Les acteurs : des processus qui parlent

> **Version 2 (2026-11-04)** — intro from scratch + §2 repris de
> `09-real-world.md` (v1, §4). Les sections I/O, HTTP, ABI C,
> vessel de v1 iront au chapitre `23-réseau` (fusion
> `24-reseau` + `25-stdlib-net-http`).
> Référentiel de style : `05-recursion.md` (v2, pilote).

> *« Un acteur, c'est quelqu'un qui a une boîte aux lettres, et qui
> répond aux lettres qu'on lui envoie. Rien de plus. »*
> — Carl Hewitt, inventeur du modèle acteur (1973)

Jusqu'ici, on a parlé de **fonctions** — des valeurs qu'on applique à
d'autres valeurs. C'est le cœur du fonctionnel. Mais un programme
réel a besoin de **processus** : des choses qui tournent en
parallèle, qui s'envoient des messages, qui survivent aux pannes.

Heaven a un modèle simple pour ça : les **acteurs**. Un acteur est
une tâche avec un identifiant (`Pid`, entier unique), une
**mailbox** (file FIFO de messages), et un **handler** (fonction qui
traite un message et met à jour l'état). C'est tout. Pas de locks,
pas de mémoire partagée, pas de race conditions.

## 1. Pourquoi des acteurs

Carl Hewitt invente le modèle en 1973. Erlang le popularise en 1986.
WhatsApp, Discord, RabbitMQ l'utilisent. L'idée : **isolation par
défaut**. Un acteur ne partage **rien** avec un autre. Il communique
uniquement par messages.

Conséquences :
- **Pas de race conditions** : personne ne lit la même mémoire.
- **Distribution gratuite** : même API en local et en réseau (le
  `Pid` encode l'adresse, ch22 MPST).
- **Tolérance aux pannes** : superviseurs qui redémarrent (ch20 OTP).

C'est le modèle de BEAM (Erlang VM) depuis 40 ans. WhatsApp : 900 M
d'utilisateurs, 50 ingénieurs. Le modèle fait ses preuves.

## 2. Comment un acteur fonctionne

Le modèle d'**acteurs** vient de Carl Hewitt (1973), et a été
popularisé par Joe Armstrong avec Erlang (1986). C'est un modèle de
concurrence sans mémoire partagée :

- Un **acteur** est un objet avec un état privé et une boîte aux
  lettres.
- Un acteur ne communique **que** par messages — pas de variable
  partagée, pas de verrou.
- Chaque acteur traite ses messages **un par un**, dans l'ordre
  d'arrivée.

En Heaven :

    heaven> actor Counter state =
              recv (lambda msg.
                tell (pair "count" (state + 1))
                (Counter (state + 1)))

L'acteur `Counter` reçoit un message, incrémente son état, répond
avec `tell`, et se relance. Trois primitives : `spawn` (créer),
`tell` (envoyer), `recv` (recevoir). C'est tout.

Le modèle d'acteurs est **conservateur** : il n'y a rien à protéger
(sinon les boîtes aux lettres), donc pas besoin de verrous. C'est
l'équivalent en programmation de ce que le sociologue Niklas
Luhmann (1927-1998) appelait les **systèmes autopoïétiques** : des
systèmes qui se maintiennent par leurs propres communications, sans
contrôle central.

Heaven V0 supporte les acteurs en mode **séquentiel** (pas de
préemption). Depuis 2026-10, un contournement coopératif existe :
`(@budget_left)` permet à une tâche de `yield` quand son budget est
épuisé (voir chapitre 13). Voir D8 et D31 dans `docs/DECISIONS.md`.

*Vérifiable : les exemples `readFile`, `writeFile` et le serveur
HTTP fonctionnent tels quels. Les acteurs fonctionnent mais sans
préemption (V0).*


## 3. Piège — Le cycle de vie est manuel

Un acteur n'est pas un thread. Il **n'existe** que quand tu le
crées, il **traite** seulement quand tu appelles `run`, et il
**meurt** seulement quand tu appelles `exit`. Rien n'est automatique.

    p = (spawn counter 0)      -- acteur existe, pas encore lancé
    (tell p 5)                  -- message dans la mailbox
    (run p)                     -- traite 5, état = 5
    (tell p 3)                  -- message dans la mailbox
    (run p)                     -- traite 3, état = 8
    (exit p)                    -- acteur mort

**Ce qui surprend** : `spawn` ne **lance** rien. Il crée la
structure. Si tu ne fais pas `run`, la mailbox se remplit, mais
rien ne se passe. C'est **volontaire** — le scheduler est
explicite (ch21a, 21b).

    -- Bug classique
    p = (spawn counter 0)
    (tell p 5)
    (tell p 3)
    -- état de p ? Personne ne sait, `run` n'a jamais été appelé.

**La règle** : `spawn` + `tell` + `run` forment un **trio**. Tu ne
peux pas utiliser la mailbox sans `run`. Le scheduler (ch21a)
alterne entre les acteurs `run`, mais il ne les **crée** pas.

**Cas vécu** : `tests/otp2_*.hvn` (26 tests) utilisent tous
`spawn` + `tell` + `run` explicitement. Aucun test ne suppose que
`run` est automatique. C'est le contrat V0.

**Autre piège** : `run` est **synchrone** — il bloque jusqu'à ce
que la mailbox soit vide. Si un acteur A envoie un message à B
pendant son propre `run`, et B attend la réponse de A, **deadlock**.
La solution : le superviseur (ch20) ou le préemptif (ch21b)
détecte le cycle.

## 4. Sous le capot — Mailbox + scheduler

Un acteur, en mémoire (`src/core/engine_expr.zig`, `Process`) :

    Process {
      pid: u32
      mailbox: ArrayList(Message)   -- FIFO
      handler: Option(Id)           -- symbole (nom de fn)
      state: Option(Id)             -- état courant
      alive: bool
      trace: ArrayList(Str)         -- MPST (ch22)
    }

**Trois choses à retenir** :

1. **Mailbox FIFO** : `ArrayList` append + `orderedRemove(0)`.
   `tell` = append, `recv`/`run` = remove front. Pas de priorité,
   pas de sélection par pattern (contrairement à Erlang).
   Conséquence : l'ordre d'arrivée est l'ordre de traitement.

2. **Handler = symbole** : le handler est le **nom** de la fonction
   (`counter`), pas la fonction elle-même. `run` fait
   `engine.fns.get("counter")` et l'applique. Si tu redéfinis
   `counter` après `spawn`, le `run` suivant utilise la
   **nouvelle** définition — le handler est résolu à chaque message.
   C'est **dynamique**, utile pour le hot-reload, dangereux pour
   la stabilité.

3. **State = Id** : l'état est un nœud du Store (`expr.Id`). Il
   n'est **pas** copié dans le `Process` — c'est une référence.
   `run` remplace le `state` par le résultat du handler (nouvel
   `Id`). L'ancien état n'est pas libéré (pas de GC en V0) — les
   petits états s'accumulent. Attention aux gros états (listes de
   1M) : `run` en crée un nouveau à chaque message. Cf.
   `_memory.md`.

**Scheduler** (ch21a, 21b) : les acteurs sont dans une **file de
tâches prêtes**. `run` est une transition d'état. Le scheduler
alterne entre les `run` — coopératif (21a) ou préemptif (21b).

**Mailbox et trace** (MPST, ch22) : si le message est une
`string`, il est **aussi** ajouté à `proc.trace`. C'est ce qui
permet le `check(proto, trace)` du MPST (ch22). La trace est
optionnelle — elle ne change pas le comportement.

**Ce qui manque** : `receive` avec **pattern matching** (Erlang
`receive {msg, x} -> ...`). En V0, `recv` retourne le premier
message, sans filtre. Chantier `_concurrency.md` C4.

## Exercices

1. **Compteur.** Écris `counter state msg = (state + msg)`. Crée
   un acteur, envoie 5 puis 3, `run`. Vérifie que l'état final
   est 8. Puis refais sans `run` — quel est l'état ? *Piège* :
   l'état n'est mis à jour que pendant `run`.

2. **Ping-pong.** Deux acteurs `ping` et `pong`. `ping` envoie
   `(pair pong "ping")` à `pong`, qui répond `(pair ping "pong")`.
   Fais tourner 3 échanges. Combien de messages dans chaque
   mailbox à la fin ? *Indice* : `run` sur les deux, dans l'ordre.

3. **Compteur global vs acteur.** Fais la même chose (2
   incréments) avec une variable globale `counter = ...` (ch8) et
   avec un acteur. Les deux donnent 8. *Piège* : imagine deux
   threads qui incrémentent la variable globale en même temps —
   que se passe-t-il ? (Perte de mise à jour.) L'acteur évite ça
   parce que `run` est séquentiel. C'est tout l'intérêt.

4. **Le piège du handler dynamique.** Crée un acteur
   `counter_h state msg = (state + msg)`, lance, puis **redéfinis**
   `counter_h state msg = (state * msg)` et envoie un nouveau
   message. Quel est le résultat ? *Piège* : le handler est
   résolu à chaque `run` — la nouvelle définition s'applique. Si
   tu veux garder l'ancienne, il faut la copier (`(let h = counter_h
   in (spawn h 0))`) ou ne pas redéfinir.

Les solutions ne sont **pas** dans le livre — c'est en cherchant
qu'on apprend.
