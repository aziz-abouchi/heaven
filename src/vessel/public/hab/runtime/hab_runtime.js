// hab/runtime/hab_runtime.js — runtime navigateur Hab (W1b, 2026-10-28)
// Charge heaven.wasm (freestanding), inline le prelude MVU, expose
// window.hab.mount(appName, rootSelector).
//
// Pourquoi inline (pas d'import) : heaven.wasm est compilé en
// wasm32-freestanding (pas de FS). Les `import "..."` du .hvn
// échouent silencieusement. On inline les sources et on réécrit
// les `H.xxx` en `xxx` (W2 : résolution de modules dans le parser).
//
// W1b limite : le shape `node "tag" [children]` est hardcodé pour
// counter (1 child = leaf). W1c généralisera le rendering du tree.

window.hab = (function () {
  let wasm = null, memory = null;

  // Prelude MVU inline (hab/component.hvn + hab/apps/counter.hvn).
  // H.xxx strippés car pas de module system dans le wasm freestanding.
  const COMPONENT_HVN = `
_pair_init (pair i _) = i
_pair_update (pair _ (pair u _)) = u
_pair_view (pair _ (pair _ v)) = v
mk_component init update view = (pair init (pair update view))
component_init comp = (_pair_init (force comp))
component_update comp = (_pair_update (force comp))
component_view comp = (_pair_view (force comp))
apply_msgs comp state nil = state
apply_msgs comp state (cons msg rest) =
  (apply_msgs comp ((component_update comp) state msg) rest)
apply_one comp state msg = ((component_update comp) state msg)
leaf text = (pair "leaf" text)
node tag children = (pair tag children)
tree_tag (pair t _) = t
tree_payload (pair _ p) = p
is_leaf (pair t _) = (= t "leaf")
`;
  const COUNTER_HVN = `
counter_init _ = 0
counter_update state msg =
  (if (= msg "inc") (+ state 1) (if (= msg "dec") (- state 1) state))
counter_view state = (node "button" (cons (leaf (int_to_string state)) nil))
counter _ = (mk_component counter_init counter_update counter_view)
`;
  const PRELUDE = COMPONENT_HVN + COUNTER_HVN;

  async function loadWasm() {
    const r = await fetch('/heaven.wasm?t=' + Date.now());
    const bytes = await r.arrayBuffer();
    const result = await WebAssembly.instantiate(bytes, {
      env: new Proxy({}, {
        get: (_, prop) => (...args) => {
          const p = String(prop);
          if (p.includes('now') || p.includes('time')) return performance.now();
          if (p.includes('len') || p.includes('read_file')) return 0;
          return undefined;
        }
      })
    });
    wasm = result.instance.exports;
    memory = wasm.memory;
    wasm.init();
  }

  function evalH(src) {
    const bytes = new TextEncoder().encode(src);
    const inPtr = wasm.getInputPtr();
    new Uint8Array(memory.buffer, inPtr, bytes.length).set(bytes);
    wasm.heavenEval(bytes.length);
    const outPtr = wasm.getOutputPtr();
    const outLen = wasm.getOutputLen();
    return new TextDecoder().decode(new Uint8Array(memory.buffer, outPtr, outLen));
  }

  // Évalue le prelude une seule fois, puis l'expression.
  let preludeLoaded = false;
  function evalWithPrelude(src) {
    if (!preludeLoaded) { evalH(PRELUDE); preludeLoaded = true; }
    return evalH(src);
  }

  function unquote(s) {
    s = s.trim();
    return (s.length >= 2 && s[0] === '"' && s[s.length - 1] === '"') ? s.slice(1, -1) : s;
  }
  function toInt(s) { return parseInt(s.trim(), 10); }

  // Rendu hardcodé pour W1b : counter est (node "button" [leaf "N"]).
  // W1c : rendering générique du tree via serialize_tree côté .hvn.
  function render(appName, state) {
    const tag = unquote(evalWithPrelude(`(tree_tag (${appName}_view ${state}))`));
    return { tag: tag, text: String(state) };
  }

  async function mount(appName, rootSelector) {
    if (!wasm) await loadWasm();
    const root = document.querySelector(rootSelector);
    if (!root) { console.error('[hab] mount: root not found:', rootSelector); return; }
    let state = toInt(evalWithPrelude(`(${appName}_init unit)`));

    function draw() {
      const t = render(appName, state);
      root.innerHTML = '';
      const el = document.createElement(t.tag === 'leaf' ? 'span' : t.tag);
      el.textContent = t.text;
      if (t.tag === 'button') {
        el.addEventListener('click', () => {
          state = toInt(evalWithPrelude(`(apply_one (${appName} unit) ${state} "inc")`));
          draw();
        });
      }
      root.appendChild(el);
    }
    draw();
    console.log('[hab] mounted', appName, 'at', rootSelector);
  }

  return { mount, evalH, evalWithPrelude };
})();
