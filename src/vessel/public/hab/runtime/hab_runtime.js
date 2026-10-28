// hab/runtime/hab_runtime.js — runtime navigateur Hab (W1b v2, 2026-10-28)
// v2 : utilise heavenDefine pour les définitions (cmds.eval refuse
// les définitions : ArityMismatch). heavenEval pour les expressions.
window.hab = (function () {
  let wasm = null, memory = null;

  const COMPONENT_HVN = [
    // Data constructors (core/std/pair.hvn + list.hvn). Pas de FS
    // dans le wasm freestanding → on les redéfinit localement.
    // Sans ces data, `(pair ...)` / `(cons ...)` / `nil` échouent
    // avec UnknownSymbol (data constructors non déclarés).
    'data Pair a b = pair a b',
    'data List a = nil | cons a (List a)',
    '_pair_init (pair i _) = i',
    '_pair_update (pair _ (pair u _)) = u',
    '_pair_view (pair _ (pair _ v)) = v',
    'mk_component init update view = (pair init (pair update view))',
    'component_init comp = (_pair_init (force comp))',
    'component_update comp = (_pair_update (force comp))',
    'component_view comp = (_pair_view (force comp))',
    'apply_msgs comp state nil = state',
    'apply_msgs comp state (cons msg rest) = (apply_msgs comp ((component_update comp) state msg) rest)',
    'apply_one comp state msg = ((component_update comp) state msg)',
    'leaf text = (pair "leaf" text)',
    'node tag children = (pair tag children)',
    'tree_tag (pair t _) = t',
    'tree_payload (pair _ p) = p',
    'is_leaf (pair t _) = (= t "leaf")',
  ];
  const COUNTER_HVN = [
    'counter_init _ = 0',
    'counter_update state msg = (if (= msg "inc") (+ state 1) (if (= msg "dec") (- state 1) state))',
    'counter_view state = (node "button" (cons (leaf (int_to_string state)) nil))',
    'counter _ = (mk_component counter_init counter_update counter_view)',
  ];
  const PRELUDE = COMPONENT_HVN.concat(COUNTER_HVN);

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

  function writeInput(str) {
    const bytes = new TextEncoder().encode(str);
    const ptr = wasm.getInputPtr();
    new Uint8Array(memory.buffer, ptr, bytes.length).set(bytes);
    return bytes.length;
  }

  function readOutput() {
    const ptr = wasm.getOutputPtr();
    const len = wasm.getOutputLen();
    return new TextDecoder().decode(new Uint8Array(memory.buffer, ptr, len));
  }

  // Expression : heavenEvalRaw (h.eval direct). cmds.eval route
  // mal les expressions qui appellent des fonctions user-defined
  // (counter_view, tree_tag, etc.) — bug du dispatch cmds.
  // heavenEvalRaw fait h.eval, comme --eval-file, qui marche.
  function evalH(src) {
    const len = writeInput(src);
    wasm.heavenEvalRaw(len);
    return readOutput();
  }

  // Définition : heavenEvalRaw("name = value"). cmds.define (via
  // heavenDefine) ne gère pas les patterns (counter_view state = ...),
  // seulement les symboles simples. heavenEvalRaw fait h.eval(line),
  // qui parse correctement "name args = body".
  function defineH(name, value) {
    const line = name + " = " + value;
    const bytes = new TextEncoder().encode(line);
    const ptr = wasm.getInputPtr();
    new Uint8Array(memory.buffer, ptr, bytes.length).set(bytes);
    wasm.heavenEvalRaw(bytes.length);
    return readOutput();
  }

  let preludeLoaded = false;
  function ensurePrelude() {
    if (preludeLoaded) return;
    let ok = 0, fail = 0;
    for (const line of PRELUDE) {
      // "name = value" → defineH(name, value)
      const eq = line.indexOf(' = ');
      if (eq < 0) { fail++; continue; }
      const name = line.slice(0, eq).trim();
      const value = line.slice(eq + 3).trim();
      const r = defineH(name, value);
      if (r.startsWith('error')) { fail++; console.error('[hab] def FAILED:', line.slice(0,60), '→', r); }
      else { ok++; }
    }
    console.log('[hab] prelude:', ok, 'defs ok,', fail, 'failed');
    preludeLoaded = true;
  }

  function unquote(s) {
    s = s.trim();
    return (s.length >= 2 && s[0] === '"' && s[s.length - 1] === '"') ? s.slice(1, -1) : s;
  }
  function toInt(s) { return parseInt(s.trim(), 10); }

  function render(appName, state) {
    ensurePrelude();
    const tag_raw = evalH(`(tree_tag (${appName}_view ${state}))`);
    const tag = unquote(tag_raw);
    return { tag: tag, text: String(state) };
  }

  async function mount(appName, rootSelector) {
    if (!wasm) await loadWasm();
    const root = document.querySelector(rootSelector);
    if (!root) { console.error('[hab] mount: root not found:', rootSelector); return; }
    ensurePrelude();
    const state_raw = evalH(`(${appName}_init 0)`);
    let state = toInt(state_raw);

    function draw() {
      const t = render(appName, state);
      root.innerHTML = '';
      const el = document.createElement(t.tag === 'leaf' ? 'span' : t.tag);
      el.textContent = t.text;
      if (t.tag === 'button') {
        el.addEventListener('click', () => {
          state = toInt(evalH(`(apply_one (${appName} unit) ${state} "inc")`));
          draw();
        });
      }
      root.appendChild(el);
    }
    draw();
    console.log('[hab] mounted', appName, 'at', rootSelector);
  }

  return { mount, evalH, defineH };
})();
