// wasm-core.js – Chargement WASM partagé (script classique, sans modules)
window.wasm = null;
window.memory = null;

window.loadWasm = async function() {
  try {
    const resp = await fetch('heaven.wasm?t=' + Date.now());
    const bytes = await resp.arrayBuffer();
    const result = await WebAssembly.instantiate(bytes, {
      env: window.jsImports || {}
    });
    window.wasm = result.instance.exports;
    window.memory = window.wasm.memory;
    window.wasm.init();
    if (window.wasm.exports.set_debug_logging) {
      window.wasm.exports.set_debug_logging(false);
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