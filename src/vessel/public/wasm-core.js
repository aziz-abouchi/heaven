// wasm-core.js – Chargement WASM partagé (script classique, sans modules)
window.wasm = null;
window.memory = null;

window.loadWasm = async function() {
  try {
    const resp = await fetch('heaven.wasm?t=' + Date.now());
    const bytes = await resp.arrayBuffer();
    const result = await WebAssembly.instantiate(bytes, {
      env: new Proxy(window.jsImports || {}, {
        // HEAVEN:WASM_PROXY — fallback auto pour imports manquants.
        // Evite LinkError quand le wasm importe une nouvelle fonction.
        // Heuristique sur le nom pour deviner le type de retour.
        get: (target, prop) => {
          if (prop in target) return target[prop];
          const p = String(prop);
          return (...args) => {
            if (p.includes('now') || p.includes('time') || p.includes('timestamp')) return performance.now();
            if (p.includes('len') || p.includes('read_file')) return 0;
            return undefined;
          };
        }
      })
    });
    window.wasm = result.instance.exports;
    window.memory = window.wasm.memory;
    window.wasm.init();
    if (window.wasm.set_debug_logging) {
      window.wasm.set_debug_logging(false);
    }
    console.log('WASM exports:', Object.keys(window.wasm).filter(k => k.includes('proof')));
    return { wasm: window.wasm, memory: window.memory };
  } catch (e) {
    console.error('WASM load failed:', e);
    throw e;
  }
};

window.readWasmString = function(ptr, len) {
  return new TextDecoder().decode(new Uint8Array(window.memory.buffer, ptr, len));
};

window.sendReplInput = function(text) {
  if (!window.wasm || !window.wasm.wasm_inject_repl_input) return;
  const bytes = new TextEncoder().encode(text);
  const ptr = window.wasm.alloc ? window.wasm.alloc(bytes.length) : 0;
  
  if (ptr) {
    new Uint8Array(window.memory.buffer, ptr, bytes.length).set(bytes);
    window.wasm.wasm_inject_repl_input(ptr, bytes.length);
    if (window.wasm.free) window.wasm.free(ptr, bytes.length);
  }
};