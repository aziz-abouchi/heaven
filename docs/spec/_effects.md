# Effets de portee dans Heaven — conception

Date : 2026-09-26
Statut : analyse + recommandation. Aucun code prod modifie.
Source : src/core/engine_expr.zig l.734-797, core/test_suite.hvn.

## 1. Contrat reel de perform / handle

### 1.1 Implementation (citations)

perform (l.735-767) :
- Evalue le DERNIER argument, le stocke dans engine.last_performed
- Si pas in_handle et qu'un IO handler est installe -> dispatch sur le label
- Sinon -> retourne last_performed ou args[0]

handle (l.769-797) :
- Sauve green_mode, last_performed, in_handle
- Met in_handle = true, last_performed = null
- Evalue le corps
- Restaure tous les flags
- Si last_performed a ete mis PENDANT le corps ET qu'un handler est fourni :
  - call_id = apply(handler, [val])
  - return evaluate(call_id)
- Sinon -> retourne le resultat du corps

engine.last_performed est un CHAMP GLOBAL de l'engine
(src/core/engine_expr.zig:148), pas un contexte par appel.

### 1.2 Semantique effective

| Propriete | Valeur | Preuve |
|---|---|---|
| Shallow | OUI | Le handler n'est pas reinstalle |
| Final | OUI | h(v) remplace tout le handle |
| One-shot | OUI | Seul le DERNIER perform est capture |
| Non type | OUI | grep dans elab.zig = 0 occurrence |
| Non composable (nesting) | OUI | Flag global ecrase par handle interne |
| Sans continuation | OUI | Aucun mecanisme de reprise |

Ce n'est PAS un systeme d'effets algebriques. C'est une exception
one-shot via flag global. Le nom perform/handle evoque Plotkin-Power,
la semantique n'y ressemble pas.

### 1.3 Impact reel

grep "handle\|perform" core/test_suite.hvn = 2 lignes (l.30 et l.37).
Deux. Pas "12-15". Toute migration qui touche le contrat
h : arg -> result n'impacte QUE ces 2 cas.

## 2. Ce qu'on veut — 3 cas d'usage concrets

### 2.1 catch (annulation)
catch { risky_computation } — si erreur, retourne une valeur par defaut.
Nessite : le handler peut ARRETER le corps. Pas de reprise.

### 2.2 local (modification d'environnement restreinte)
local (env_mod) { body } — pendant body, env modifie ; apres, restaure.

### 2.3 bracket (acquisition/liberation)
bracket { setup } { body } teardown
Nessite : setup, run, teardown, retour du resultat de run.

## 3. Quatre techniques d'implementation

### 3.1 Scoped syntax (pas des effets)

Ajouter au parseur trois constructions :
  bracket { setup } { body } teardown
  local (env_mod) { body }
  catch { body } default

Implementation : dans engine_expr.evaluate, un case pour chaque.
Le bracket sauve l'env, execute setup, execute body avec defer sur
teardown, retourne resultat.

Cout : ~60-100 lignes dans engine_expr.zig + cases dans le parser.
Risque : FAIBLE. N'affecte pas perform/handle existants.
Limite : pas composables avec handle.

### 3.2 handle-rec shallow (sans continuation)

Etendre handle avec un variant handle-rec :
  handle-rec e h — h : op -> arg -> HandleAction
  HandleAction = Stop(result) | Continue(arg)

Si le handler retourne .Stop(v), le corps est abandonne et handle-rec
retourne v. Si .Continue(a), le corps continue avec une nouvelle valeur.

Attention : sans continuation, .Continue ne peut pas vraiment
"continuer" — il faut re-evaluer le corps depuis le debut, ce qui
rejoue les effets. Sur du tree-walking avec I/O, ca double les Print.

Cout : ~150 lignes. Risque : MOYEN. Semantique piegeuse.
Limite : utilisable SEULEMENT pour catch (annulation).

### 3.3 handle-rec avec continuation (CPS)

Transformer evaluate en style passage de continuation :
  fn evaluate(store, env, engine, id, depth, k: *const fn (Id) EvalError!Id) EvalError!Id

Chaque retour devient un appel a k. Le handle-rec peut alors capturer
k comme valeur, l'appeler plus tard.

Cout : refonte de ~600 lignes de evaluate, plus tous les call-sites.
Risque : ELEVE. Casse potentiellement tout.
Gain : systeme d'effets algebriques COMPLET (Plotkin-Power).

### 3.4 Continuations delimitees via trampoline

Ajouter un mode "CPS" uniquement aux frontieres magiques (handle,
if, while), laisser le reste direct-style.

Cout : ~300-500 lignes. Risque : ELEVE (boundary entre les 2 modes).

## 4. Decision recommandee

Pour ton cas d'usage (ressources par message d'acteur) : technique 3.1.

Raisons :
1. Couvre 100 % du besoin reel (bracket autour d'un handler de message,
   local pour variables d'env, catch pour isolation)
2. Cout faible (~60-100 lignes), risque faible
3. Ne touche pas au systeme perform/handle existant (2 tests continuent)
4. Ne necessite pas de choisir entre CPS et trampoline maintenant

Ce qu'on perd : composition avec handle. Pas prioritaire pour Heaven.

Si un jour on veut un vrai systeme d'effets algebriques complet ->
technique 3.3, session dediee de refonte de evaluate.

## 5. Plan de sessions

| Session | Sujet | Livrable |
|---|---|---|
| 1 (cette) | Conception, ce doc | _effects.md |
| 2 | Scoped syntax bracket / local / catch | ~80 lignes engine + 4 tests |
| 3 (si besoin) | handle-rec shallow pour catch type | ~150 lignes |
| 4+ (optionnel) | Refonte CPS | 2-3 sessions |

## 6. Decisions a valider par l'auteur

1. Technique : 3.1 (scoped syntax) ou 3.3 (CPS refonte) ?
   Recommandation : 3.1.
2. Syntaxe cible (proposee) :
   bracket { setup } { body } teardown
   local (env_mod) { body }
   catch { body } default
3. Priorite : apres rule/SLD (STATUS #2) ou avant ?
   Recommandation : apres.

## 7. Ce qu'il faudra verifier avant la session 2

- if, while sont des magic symbols (isMagicSymbol l.485). Ou sont
  leurs cases dans evaluate ?
- Comment evaluate interagit avec env.put / env.delete
- Les effets Print/ReadFile traversent io_handler, pas le flag
  in_handle — comment eviter les conflits ?
- green active/desactive des flags engine-wide

## 8. Note methode

Cette conception a ete redigee apres LECTURE du code reel, pas apres
lecture d'une reponse LLM. Les verifications demandees ont revele que
le plan initial (fourni par un LLM) contenait des FAITS INVENTES :

- "~12-15 tests handle/perform" -> en realite 2
- "typage par inference directe" -> en realite AUCUN typage
- "capture la stack frame sous forme de Lambda" -> IMPOSSIBLE en
  tree-walking sans CPS

Toute conception de ce chantier doit se baser sur les CITATIONS du
code, pas sur des paraphrases plausibles.
