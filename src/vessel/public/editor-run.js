// editor-run.js — Run autonome WASM (override propre)
// Ne touche pas au JS existant de editor-frame.html.
// Override window.runCode + window.evalHeaven après chargement.

(function () {
  // ── jsImports : capture des logs ──
  window.jsImports = window.jsImports || {};
  window.jsImports.js_console_log = function (ptr, len) {
    try {
      var t = new TextDecoder().decode(new Uint8Array(window.memory.buffer, ptr, len));
      (window._outputBuf = window._outputBuf || []).push(t);
    } catch (_) {}
  };
  window.jsImports.js_console_error = function (ptr, len) {
    try {
      var t = new TextDecoder().decode(new Uint8Array(window.memory.buffer, ptr, len));
      (window._outputBuf = window._outputBuf || []).push('[err] ' + t);
    } catch (_) {}
  };
  window.jsImports.js_performance_now = function () { return performance.now(); };

  function setOutput(text) {
    var out = document.getElementById('output');
    if (out) out.textContent = text;
  }

  async function evalHeaven(code) {
    if (!window.wasm) await window.loadWasm();
    if (!window.wasm.heavenEvalRaw) throw new Error('heavenEvalRaw absent');
    var bytes = new TextEncoder().encode(code);
    var inPtr = window.wasm.getInputPtr();
    new Uint8Array(window.memory.buffer, inPtr, bytes.length).set(bytes);
    window.wasm.heavenEvalRaw(bytes.length);
    var outPtr = window.wasm.getOutputPtr();
    var outLen = window.wasm.getOutputLen();
    return new TextDecoder().decode(new Uint8Array(window.memory.buffer, outPtr, outLen));
  }

  async function runCode() {
    console.log('runCode v3 (editor-run.js)');
    window._outputBuf = [];
    setOutput('...running...');
    try {
      var src = document.getElementById('editor').value.trim();
      if (!src) { setOutput('(empty)'); return; }
      var result = await evalHeaven(src);
      var logs = (window._outputBuf || []).join('');
      var text = '';
      if (logs) text += '[log]\n' + logs + '\n\n';
      text += (result && result.length) ? result : '(no output)';
      // Hint : let-in en RHS de = casse le parser (annexe G.2)
      if (/\blet\b/.test(src) && /\bin\b/.test(src) && /syntax|let/i.test(result + ' ' + logs)) {
        text += '\n\n[hint] let-in en RHS de = casse le parser (G.2).';
        text += '\n[hint] Contournement : ((lambda _ -> (let x = 5 in x + 1)) 0)';
      }
      setOutput(text);
    } catch (e) {
      setOutput('ERROR: ' + (e && e.message ? e.message : e));
    }
  }

  // Override global après chargement
  window.evalHeaven = evalHeaven;
  window.runCode = runCode;

  // Brancher Clear (si le panel existe)
  document.addEventListener('DOMContentLoaded', function () {
    var btn = document.getElementById('btn-clear-out');
    if (btn) btn.addEventListener('click', function () {
      window._outputBuf = [];
      setOutput('');
    });
  });
})();
