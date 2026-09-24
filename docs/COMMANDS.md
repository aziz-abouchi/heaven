# Commandes et mots-clés — carte de référence

**Source de vérité** pour distinguer ce qui est *langage* et ce qui est *shell*.

## Règle

Un mot est **du langage** si :
- il a un sens dans un fichier `.hvn` exécuté hors REPL ;
- il produit une **valeur** ou **définit** quelque chose (théorème, type, fait…) ;
- il peut apparaître dans `core/test_suite.hvn`.

Un mot est **du shell** si :
- il **inspecte** ou **modifie** l'état de session ;
- il ne produit pas de valeur exploitable dans une expression ;
- il est conventionnellement préfixé par `:` (le préfixe peut être omis au REPL pour les commandes sans ambiguïté).

**Conflits** : un mot ne peut pas être à la fois shell et langage. En cas d'ambiguïté, la version shell porte `:`.

---

## 1. Langage

### 1.1 Structure
| Mot-clé | Rôle |
|---|---|
| `module M` | Ouvre un namespace |
| `import "path" [as Name]` | Charge un fichier |
| `import Name` | Cherche `core/std/<nom>.hvn` puis `core/<nom>.hvn` |
| `export foo` | Marque un nom exporté |
| `strict on\|off` | Active le mode strict |
| `data D p1 p2 = C1 \| C2` | Déclare un type |
| `sig f : A -> B` | Déclare une signature |
| `f x = ...` | Équation (définition) |
| `let x = v in b` | Liaison locale |

### 1.2 Types
| Mot-clé | Rôle |
|---|---|
| `type e` | Retourne la string du type de `e` |

### 1.3 Preuves
| Mot-clé | Rôle |
|---|---|
| `theorem t : a = b` | Déclare un théorème |
| `prove t by eval\|simplify\|induction x\|...` | Prouve (stratégie monolithique) |
| `prove t by { t1; t2; ... }` | Prouve (tactics composables) |
| `skill name` | Applique une skill au théorème actif |

### 1.4 Calcul symbolique
Les opérateurs CAS sont **des fonctions** appelables dans une expression.

| Fonction | Rôle |
|---|---|
| `(simplify e)` | Simplifie |
| `(derive e)` | Dérive (variable implicite `x`) |
| `(derive e v)` | Dérive selon `v` |
| `(integrate e)` | Intègre |
| `(solve e)` | Résout |
| `(expand e)` | Développe |
| `(plot e)` | Trace ASCII |
| `(latex e)` | Rend LaTeX |

Ces fonctions acceptent aussi la forme préfixe `simplify e`, `derive e` au REPL (compatibilité), mais la forme canonique dans un `.hvn` est parenthésée.

### 1.5 Effets
| Mot-clé | Rôle |
|---|---|
| `perform "Op" v` | Émet un effet |
| `handle e h` | Intercepte les effets |
| `green e` | Profile `e` (CPU + énergie) |

### 1.6 Tests
| Mot-clé | Rôle |
|---|---|
| `test "name": expr == expr` | Test nommé |
| `assert_eq lhs == rhs` | Assertion d'égalité |
| `assert_err expr` | Attend une erreur |

**Note** : `assert` est **réservé aux tests**. Pour la logique, on utilise `fact`.

### 1.7 Logique — miniKanren
| Mot-clé | Rôle |
|---|---|
| `fact name arg1 arg2 ...` | Assert un fait (retourne OK/erreur) |
| `rule name args... => body` | Ajoute une clause (retourne OK/erreur) |
| `query name arg1 arg2 ...` | Retourne les solutions (liste) |
| `rules` | Retourne la KB (règles de réécriture) comme valeur |

**Note** : `rules` remplace `meta` et `:rules` côté langage. La commande shell `:rules` reste pour l'inspection interactive.

### 1.8 Prolog
| Mot-clé | Rôle |
|---|---|
| `?- goal` | Requête Prolog |

**Note** : remplace `ask`, qui redevient disponible pour l'agent IA.

### 1.9 Ontologie
| Mot-clé | Rôle |
|---|---|
| `isa a b` | Retourne `Bool` |

### 1.10 Agent IA
| Mot-clé | Rôle |
|---|---|
| `ai "prompt"` | Envoie un prompt à l'agent, retourne la réponse |

**Note** : ancien `ask` (avant redéfinition Prolog).

### 1.11 Mécanismes (acteurs, macros)
| Mot-clé | Rôle |
|---|---|
| `let actor X = v with handler` | Spawn un acteur |
| `let macro M(args) = body` | Macro hygiénique |
| `fn handler(state, msg) = ...` | Handler d'acteur |
| `send(X, msg)` | Envoie |
| `state(X)` | État |
| `spawn(...)` | Green thread |

---

## 2. Shell

Toutes les commandes shell acceptent la forme `:cmd` ou `cmd`. Certaines ont un raccourci (`:` omis) réservé aux commandes sans conflit avec un identifiant utilisateur.

### 2.1 Session
| Commande | Alias | Rôle |
|---|---|---|
| `:help` | `:h` | Aide |
| `:exit` | `:q`, `:quit` | Quitter |
| `:load <path>` | | Charge un fichier `.hvn` |
| `:stats` | `:s` | Statistiques moteur |
| `:doc` | | Doc des primitives |
| `:history` | | Historique |
| `:save-history` | | Sauvegarde |

### 2.2 Inspection
| Commande | Rôle |
|---|---|
| `:theorems` | Liste les théorèmes et axiomes |
| `:rules` | Liste la KB (règles de réécriture) |
| `:hole [id]` | Liste les trous / détail |
| `:refine <id> <expr>` | Raffine un trou |
| `:io on\|off\|status` | État du handler IO |
| `:qtt <expr>` | Vérification QTT |
| `:subst <expr>` | Substitution explicite |
| `:sexpr <expr>` | Format S-Expression |
| `:onto` | Ontologie |
| `:trace <name>` | Trace |

### 2.3 Outils externes
| Commande | Rôle |
|---|---|
| `:spawn`, `:go` | Green thread |
| `:threads`, `:gt` | Liste threads |
| `:await`, `:aw` | Attend un thread |
| `:swarm`, `:sw` | Pilote le swarm |
| `:mcp` | Serveur MCP |
| `:mlcpd` | Parser MLCPD |
| `:mlcpd-convert` | MLCPD → Expr IR |
| `:mlcpd-stats` | Stats MLCPD |
| `:mlcpd-equiv` | Équivalence MLCPD |
| `:parseFileWithLanguage` | Parse selon extension |
| `:dumpAstFile` | Dump AST |
| `:translateAndDump` | Traduit + dump |

### 2.4 Compilation
| Commande | Rôle |
|---|---|
| `:transpile` | Génère du C |
| `:compile` | Compile en exécutable |
| `:c` | Transpile en C brut |
| `:optimize`, `:opt` | Optimise |

---

## 3. Suppressions et renommages

### À supprimer
- `meta` (langage) → remplacé par `rules` (langage) ou `:rules` (shell)
- `:meta` (shell) → `:rules`
- `axioms` (référence morte dans `is_command`)

### À renommer
| Ancien | Nouveau | Raison |
|---|---|---|
| `ask` (Prolog) | `?-` (langage) | Libère `ask` pour l'IA |
| `ask` (réservé) | `ai "..."` (langage) | Agent IA |
| `fact` (shell) | `fact` (langage) | Doit être évaluable dans un `.hvn` |
| `rule` (shell) | `rule` (langage) | Idem |
| `query` (shell) | `query` (langage) | Idem |
| `run*` (shell) | `run*` (langage) ou `query` | Dédupliqué |
| `simplify <e>` | `(simplify e)` canonique + préfixe compat | Cohérence |

### À nettoyer (doublons)
- `type ` : deux branches dans `Heaven.eval` (lignes 589 et 905)
- `green ` : deux branches (lignes 593 et 911)
- `latex ` : route shell + route langage

---

## 4. Plan de migration

1. **Nettoyage trivial** — supprimer les doublons, `meta`, `axioms` de `is_command`. Aucune rupture.
2. **`rules` (langage)** — nouvelle fonction `rules` qui retourne la KB comme `Id`. Suppression de `meta` partout.
3. **Logic en langage** — `fact` / `rule` / `query` deviennent évaluables (sortie du shell). `?-` remplace `ask` pour Prolog. `ai "..."` prend `ask`.
4. **CAS en fonctions** — `(simplify e)` etc. canoniques. Compatibilité préfixe conservée 1 version.

Chaque étape = un commit. Les tests `core/test_suite.hvn` doivent rester verts.
