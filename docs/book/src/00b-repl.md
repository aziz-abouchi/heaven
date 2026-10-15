# Essayez Heaven dans votre navigateur

Le REPL ci-dessous est le moteur Heaven compilé en WebAssembly.
Vous pouvez l'utiliser directement, sans installation.

<iframe
  id="heaven-repl-frame"
  width="100%"
  height="550px"
  style="border:1px solid #444;border-radius:8px;background:#0a0a0a"
  allow="clipboard-write">
</iframe>

<script>
  // Detecte le prefixe : /heaven/ en prod GitHub Pages, "" en local.
  (function() {
    var path = location.pathname;
    var prefix = path.indexOf('/heaven/') >= 0 ? '/heaven' : '';
    var iframe = document.getElementById('heaven-repl-frame');
    if (iframe) iframe.src = prefix + '/repl/';
  })();
</script>

**Astuce** : tapez `(+ 1 2)` puis Entrée pour vérifier que tout fonctionne.
