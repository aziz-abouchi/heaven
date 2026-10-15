// vfs.js — VFS simple pour le WASM Heaven.
// Precharge les fichiers .hvn via fetch() puis les sert depuis un cache.
// Interface avec wasm :
//   js_vfs_read_file(ptr, len) -> usize
//   js_vfs_copy_buffer(out_ptr, len) -> void

(function() {
  const VFS = new Map();       // path -> Uint8Array
  let pending = null;          // fichier en cours de copie

  async function vfsInit(basePath) {
    try {
      const r = await fetch(basePath + '/vfs_manifest.json');
      if (!r.ok) { console.warn('[vfs] manifest introuvable'); return; }
      const list = await r.json();
      await Promise.all(list.map(async p => {
        try {
          const rr = await fetch(basePath + '/' + p);
          if (rr.ok) VFS.set(p, new Uint8Array(await rr.arrayBuffer()));
        } catch (_) {}
      }));
      console.log(`[vfs] ${VFS.size} fichiers charges`);
    } catch (e) {
      console.warn('[vfs] init echoue:', e);
    }
  }

  function readWasmString(memory, ptr, len) {
    return new TextDecoder().decode(new Uint8Array(memory.buffer, ptr, len));
  }

  function makeVfsImports(getMemory) {
    return {
      js_vfs_read_file: (ptr, len) => {
        const path = readWasmString(getMemory(), ptr, len);
        const data = VFS.get(path);
        if (!data) return 0;
        pending = data;
        return data.length;
      },
      js_vfs_copy_buffer: (outPtr, len) => {
        if (!pending) return;
        const n = Math.min(pending.length, len);
        new Uint8Array(getMemory().buffer, outPtr, n).set(pending.slice(0, n));
        pending = null;
      },
    };
  }

  window.HeavenVFS = { vfsInit, makeVfsImports };
})();
