# TCO etendue : recursion mutuelle

> Statut : **fait** (2026-10-02). WASM : `return_call` natif. QBE :
> fusion SCC au niveau MIR — paires (`e6a31ff`) puis SCC 3+
> (`8fcfa20`). `isEven 100000000 = 1` (2-cycle) et `f 1000000 = 200`
> (3-cycle) sur les deux backends, non-regression fib/count_down/arith
> OK.

## Approche retenue par backend

### WASM : `return_call` natif (FAIT)

wasmtime 49 supporte le proposal `tail-call`, expose en WAT via
`return_call`. La transformation est triviale :

    (call $f (local.get $r0))    ; non-tail
    ;; devient
    (return_call $f (local.get $r0))    ; tail

Avantages : aucune fusion de fonctions, aucun tag, aucune
construction de SCC. Marche pour self ET mutual recursion
indifferemment.

Verifie sur :
- `isEven 1000000` -> 1
- `isEven 100000000` -> 1 (100M iterations, pas de trap)
- non-regression : `count_down 100000` -> 100000, `fib 25` -> 75025

### QBE : fusion SCC (FAIT)

QBE 1.2 **n'accepte pas** `ret %r =l call $f(...)` — erreur de
syntaxe "newline expected". Le language QBE ne fait pas de TCO.

Solution : fusion SCC **au niveau MIR** (pas dans le backend).
- `findTailPairs` / `findTailSCCs` : detectent les SCC (paires via
  pairs, taille arbitraire via SCCs).
- `fuseTailPairs` / `fuseTailSCCs` : pour chaque SCC, cree une
  fonction `$scc_N` avec tag dispatch. La variante N-ary utilise
  un dispatch a N branches (bloc 0 : check tag==0, bloc 1 : check
  tag==1, ..., bloc N-2 : fallback). Chaque membre occupe une region
  contigue de blocs et regs, decalee (`copyBlocksForFusionN`).
- `wrapWithSccCall` : remplace le corps des fonctions originales
  par un wrapper qui appelle `$scc_N` avec le bon tag.
- Couvre SCC de taille 2 et 3+. Verifie : `isEven 100000000 = 1`
  (2-cycle), `f 1000000 = 200` (3-cycle f -> g -> h -> f).

Avantage : une seule implementation pour les deux backends. WASM
continue a beneficier de `return_call` en bonus pour les tail-calls
hors SCC.

Le plan detaille ci-dessous (approche A) reste valide pour QBE.

## Etat historique (approches analysees)

Le document ci-dessous presente les trois approches possibles :

1. SCC simple + tag dispatch (retenue pour QBE)
2. SCC general (extension naturelle)
3. Trampoline general (non retenu)

---

## Le probleme

## Le probleme

### Reproduction

    cat > /tmp/mutual.hvn <<'HVN'
    fn isEven(n) = (if (= n 0) 1 (isOdd (- n 1)))
    fn isOdd(n)  = (if (= n 0) 0 (isEven (- n 1)))
    (isEven 1000000)
    HVN
    ./zig-out/bin/heaven compile-qbe /tmp/mutual.hvn -o /tmp/mutual && /tmp/mutual

Resultat : segfault. La pile native explose apres ~100 000 frames.

### Cause

La TCO actuelle (dans `mir_qbe.zig` et `mir_wat.zig`) detecte les blocs
dont la derniere instruction est un `call_user` vers **la fonction
courante** (`cur_sym`). Le pattern :

    (isEven 999999) -> appel isOdd
    (isOdd  999998) -> appel isEven

n'est jamais transforme, parce qu'a l'interieur de `isEven`, le
`call_user isOdd` ne cible pas `cur_sym`. Chaque appel empile une
nouvelle frame native. A 1 000 000 de tours, la pile deborde.

### Ce qui est deja couvert

- Self-tail-call direct : `f` appelle `f` en tail. Transforme en boucle.
- Non-tail-call (comme `fib`) : rien, comportement normal.

### Ce qui n'est pas couvert

- Trampolines generaux (tail-call inter-fonction hors du SCC).
- Le cas ou des fonctions d'un SCC ont des arites differentes
  (le code exige `param_regs.len` identiques pour tous les membres).

## Approche A : SCC simple + tag dispatch

### Principe

1. Construire le **graphe des appels tail** : une arete `f -> g` si le
   corps de `f` contient un `call_user g` terminal.
2. Calculer les **composantes fortement connexes** (SCC) de ce graphe.
3. Pour chaque SCC de taille > 1 : **fusionner** les fonctions du SCC en
   une seule fonction MIR, avec un argument de tag qui identifie
   laquelle executer.
4. A l'entree, un dispatch `switch(tag)` saute au bloc d'entree de la
   bonne fonction.
5. Un `call_user g` terminal vers un membre du meme SCC devient :
   - copie des arguments dans les temporaires,
   - copie du tag de `g`,
   - `jmp @b0` (ou `(local.set $cur (i32.const 0))` en WAT).

### Concretement pour isEven / isOdd

Avant :

    fn $isEven(n) { ... call $isOdd ... }
    fn $isOdd(n)  { ... call $isEven ... }

Apres :

    fn $scc_0(tag, n) {
      @entry
        jmp @b0
      @b0
        %t =l phi @entry %tag_a0, @bTCO %tag_b0
        %r0 =l phi @entry %n_a0, @bTCO %n_b0
        switch %t, @case_isEven, @case_isOdd
      @case_isEven
        // corps de isEven, call_user isOdd terminal remplace par:
        //   %tmp0 =l copy %r0
        //   %tmp1 =l copy (- 1 %r0)
        //   %tag_b0 =l copy 1        ; tag de isOdd
        //   %n_b0 =l copy %tmp1
        //   jmp @b0
      @case_isOdd
        // symetrique
    }

Les fonctions `isEven` et `isOdd` originales deviennent des **wrappers**
qui appellent `$scc_0` avec le bon tag a l'entree. Le reste du code
appelle les wrappers normalement.

### Effort

- `mir_qbe.zig` : ~80 lignes.
- `mir_wat.zig` : ~60 lignes (meme logique, locals mutables).
- Tests : 3 cas (isEven/isOdd, cycle de 3, non-SCC).

## Approche B : SCC general (SCC de taille N)

L'approche A s'etend naturellement a des cycles plus longs. Le seul
changement est la taille du switch de dispatch : N branches au lieu de 2.

Cette approche est recommandee en production. La complexite
d'implementation est lineaire en taille du SCC.

## Approche C : trampoline general (non retenue)

Un trampoline transforme **tout** tail-call inter-fonction en retour de
code (le "tag" est l'adresse de la fonction a executer ensuite). C'est le
modele des compilateurs Scheme qui garantissent la TCO partout.

**Non retenu** pour trois raisons :

1. Effort disproportionne par rapport au besoin.
2. Transforme la semantique des appels non-tail aussi (impact perf).
3. Contredit le contrat MIR actuel (`call_user` reste un appel).

On peut revisiter cette approche si un cas reel l'exige.

## Plan d'implementation

### Etape 1 (cette spec)

Document de design, decision sur le niveau A vs B, limites explicites.

### Etape 2

- Implementer `buildCallGraph()` : liste des aretes tail `f -> g` a
  partir des `fn_defs`.
- Implementer `findSCCs()` : Tarjan ou Kosaraju, sur `u32` (les symbols).
- Filtrer : ne garder que les SCC de taille > 1.

### Etape 3

- Pour chaque SCC : allouer une fonction cible `$scc_N` avec un tag.
- Emettre la fusion dans `mir_qbe.zig`.
- Emettre les wrappers pour les fonctions d'origine.
- Tester avec `isEven 1000000`, `isEven 1000001`, cycle de 3.

### Etape 4

- Meme chose dans `mir_wat.zig`.

### Etape 5

- Docs : STATUS.md, BACKENDS.md, CHANGELOG.md, book/04-recursion.md.
- Bench : `count_down` deja OK, ajouter un bench `mutual.hvn` si
  interessant.

## Limites explicites

- **Appels non-tail** : `f` qui appelle `g` avec un `+` apres le call
  ne sera jamais transforme. C'est correct (comportement standard).
- **Sortie du SCC** : `f` du SCC qui appelle `h` en tail (hors SCC)
  reste un `call_user` normal. Pas de TCO cross-SCC.
- **Recursion indirecte via un if** : si l'appel tail est conditionnel
  (`(if c (g x) (h x))`), les deux branches doivent etre tail pour que
  la transformation s'applique au bloc entier. Sinon, la branche
  concernant le SCC est transformee, l'autre non.
- **Cycles avec data** : le tag remplace la fonction, pas les donnees.
  Chaque membre du SCC garde ses propres parametres et son propre
  registre de valeurs.

## Impact sur les benchs

Aujourd'hui, les benchs n'ont pas de cas de recursion mutuelle. Mais
`isEven 1000000` en QBE avec la TCO actuelle :

- Stack usage : O(n) frames natives -> ~64 MB pour n = 1e6.
- Apres TCO A : stack constant (une frame).
- Speedup attendu : significatif pour les grands n (moins de pression
  cache, moins de page faults).

Un bench dedie est a prevoir en Etape 5.

## Probleme connexe, non couvert ici

Un bug separe a ete observe pendant la reproduction : `src/core/matrix.zig`
fait un `free` invalide au shutdown du REPL (`Invalid free` dans
`debug_allocator.zig:875`, `matrix.zig:237`). Ce bug est **independant**
de la TCO mutuelle. Il est probablement lie a D1 (deplacer l'ecosysteme
Astra vers `src/legacy/`). A traiter separement.
