# Chapitre 27 — Hab : Heaven Web natif

> **Hab** est le framework Web de Heaven, en référence aux *habs* du
> Bobiverse : des habitats autonomes où chaque composant vit de façon
> indépendante, distribué, et formellement vérifiable. Hab n'est pas
> un wrapper JS de plus — c'est le langage UI de Heaven, compilé vers
> WebAssembly, qui parle le DOM avec les effets algébriques du noyau.

## 1. Pourquoi un framework Web ?

Des langages comme Elm ont montré la voie : un langage fonctionnel peut
remplacer React sans Virtual DOM, en compilant le *Model-View-Update*
(MVU) d'Elm directement vers des mises à jour ciblées. Hab applique
la même idée à Heaven, avec trois avantages supplémentaires :

1. **Effets algébriques** (`perform`/`handle`) au lieu de callbacks.
2. **QTT + zéro-GC** pour les composants UI.
3. **Acteurs distribués** (Swarm) : un composant peut migrer du
   serveur au navigateur sans changer une ligne.

## 2. Architecture MVU

Un composant Hab est un triplet pur :

    component = (init, update, view)

- `init : unit -> state`     — état initial
- `update : state -> msg -> state` — transition
- `view : state -> tree`     — arbre de rendu

Le **noyau ne touche jamais au DOM**. Il produit un `tree`
(`(node tag children)` ou `(leaf text)`) que le runtime consomme.
Conséquence : le même composant tourne en test (sans navigateur) et
en production (dans le navigateur).

## 3. Le premier composant — counter

    -- hab/apps/counter.hvn
    import "hab/component.hvn" as H

    counter_init _ = 0

    counter_update state msg =
      (if (= msg "inc")
        (+ state 1)
        (if (= msg "dec")
          (- state 1)
          state))

    counter_view state = (H.node "button" (cons (H.leaf (int_to_string state)) nil))

    counter _ = (H.mk_component counter_init counter_update counter_view)

    -- hab/component.hvn
    mk_component init update view = (pair init (pair update view))
    apply_one comp state msg = ((component_update comp) state msg)
    tree_tag (pair t _) = t
    node tag children = (pair tag children)
    leaf text = (pair "leaf" text)

En test :

    test "counter_init": (counter_init 0) == 0
    test "counter_inc":  (apply_one (counter unit) 0 "inc") == 1
    test "counter_view": (tree_tag (counter_view 0)) == "button"

En navigateur :

    http://127.0.0.1:18080/hab/runtime/index.html
    → bouton 0 qui s'incrémente au clic

## 4. Runtime navigateur

Le wasm freestanding n'a **pas de FS** : les `import "..."` du `.hvn`
échouent silencieusement. Le runtime inline donc le prelude (21
clauses) côté JS, puis charge le wasm et appelle `heavenEvalRaw` :

    // hab/runtime/hab_runtime.js (extrait)
    const PRELUDE = [
      'data Pair a b = pair a b',
      'data List a = nil | cons a (List a)',
      'mk_component init update view = (pair init (pair update view))',
      // ... 18 autres clauses
    ];

    async function loadWasm() {
      const bytes = await (await fetch('/heaven.wasm')).arrayBuffer();
      const { instance } = await WebAssembly.instantiate(bytes, { env: ... });
      wasm = instance.exports;
      wasm.init();
    }

    function defineH(name, value) {
      const line = name + " = " + value;
      writeInput(line);
      wasm.heavenEvalRaw(line.length);   // h.eval, pas cmds.eval
      return readOutput();
    }

    function evalH(src) {
      writeInput(src);
      wasm.heavenEvalRaw(src.length);
      return readOutput();
    }

`heavenEvalRaw` (dans `src/vessel/wasm_entry.zig`) fait `h.eval(line)`
directement, comme `--eval-file`. À l'inverse `heavenEval` route via
`cmds.eval`, qui refuse les patterns user-defined
(`counter_view state = ...` → ArityMismatch).

## 5. Cinq outils de test, tous en Heaven pur

| Outil | Rôle | Tests |
|---|---|---|
| `mocker.hvn` | DI minimale (`fixed v`) | 4 |
| `smocker.hvn` | Vrai spy (record + verify + seq) | 6 |
| `quickcheck.hvn` | Property testing (points) | 6 |
| `fuzzer.hvn` | Fuzz (trajectoires de msgs) | 4 |
| `loadtest.hvn` | Charge in-process (max 50) | 4 |

Tous en Heaven pur, zéro Zig. Utilisés par `hab/tests/*.hvn` (24
tests sur counter : MVU pur, smocker, quickcheck, fuzzer, loadtest).

## 6. Contraintes connues

**TCO partiel** — `let` et `seq` cassent le TCO. `loadtest` max 50
iters, `fuzzer.fuzz_run` remplacé par `Q.check`. Dette Phase 7
(étendre la détection TCO).

**Pas d'import wasm** — les `data Pair`/`List` sont inlinés dans le
prelude JS. Le vrai fix (résolution de modules dans le parser
wasm) viendra en W2.

**Rendu hardcodé** — `hab_runtime.js` ne sait rendre que `button`
(1 child leaf). `serialize_tree` en `.hvn` (W1c) généralisera à
tout arbre.

## 7. Lancer

    cd ~/Desktop/Dev/langage/boot
    zig build
    HEAVEN_NO_LEAK_CHECK=1 ./zig-out/bin/heaven --http-serve 18080
    # → http://127.0.0.1:18080/hab/runtime/index.html
    # → http://127.0.0.1:18080/hab/runtime/debug.html (12 expressions testées)

Tests :

    ./zig-out/bin/heaven --run-test hab/tests/test_component.hvn   # 24/24
    ./zig-out/bin/heaven --run-test hab/tests/test_fuzzer.hvn       # 9/9
    ./zig-out/bin/heaven --run-test hab/tests/test_loadtest.hvn     # 9/9

## 8. Vision : Heaven Web natif complet

Hab est la première brique. À terme :

- **Effets algébriques UI** : `perform DOM.click`, `handle` au
  runtime (W2).
- **Acteurs composables** : un composant = un `@spawn`, capable de
  migrer serveur ↔ navigateur (W4).
- **Preuves d'invariants UI** : `theorem ui_valid : (panier == Nil)
  -> (ecran_paiement == False)` (W5).
- **Zero Virtual DOM** : mises à jour ciblées par signaux (W3).

C'est la vision d'un runtime UI *universel*, formellement vérifié,
distribué, minimal. Heaven ne fait pas que le Web — il le **prouve**.
