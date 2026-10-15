# Applications en ligne

Toutes ces applications sont compilées en WebAssembly et tournent
directement dans votre navigateur. Aucune installation requise.

| Application | Description |
|---|---|
| **[REPL](/heaven/repl/)** | Évaluez du code Heaven |
| **[IDE](/heaven/ide/)** | Éditeur complet |
| **[Dashboard](/heaven/dashboard/)** | Métriques, swarm, E-Graph |
| **[Tests](/heaven/test/)** | Suite de tests navigateur |
| **[E-Graph](/heaven/egraph/)** | Visualiseur de graphes |
| **[Process](/heaven/process/)** | Manager d'acteurs |
| **[Debugger](/heaven/debugger/)** | Débogueur de session |
| **[Docs API](/heaven/docs/)** | Documentation technique |

## REPL inline

Vous pouvez aussi essayer Heaven directement dans ce livre via
le [chapitre REPL](00b-repl.md), ou l'iframe ci-dessous :

<iframe
  id="heaven-apps-frame"
  width="100%"
  height="600px"
  style="border:1px solid #444;border-radius:8px;background:#0a0a0a">
</iframe>

<script>
  (function() {
    var path = location.pathname;
    var prefix = path.indexOf('/heaven/') >= 0 ? '/heaven' : '';
    var iframe = document.getElementById('heaven-apps-frame');
    if (iframe) iframe.src = prefix + '/repl/';
  })();
</script>
