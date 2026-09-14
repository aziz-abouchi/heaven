; ═══════════════════════════════════════════════════════════
; Heaven — Tree-sitter Highlights Query (Complete)
; ═══════════════════════════════════════════════════════════

; ─── Mots-clés Core ──────────────────────────────────────
[ "fn" "pub" "let" "var" "const" "mut" "return" "if" "else" "then" "while" "for" "in" "loop" "break" "continue" "match" "struct" "enum" "impl" "self" "type" "do" "with" "as" ] @keyword

; ─── Mots-clés Fonctions / Modificateurs ─────────────────
[ "total" "reactive" "spatial" "narrative" "distributed" ] @keyword.modifier

; ─── Mots-clés Effets ────────────────────────────────────
[ "effect" "handler" "handle" "perform" ] @keyword.control

; ─── Mots-clés Concurrence ───────────────────────────────
[ "actor" "receive" "spawn" "await" "supervisor" "scheduler" "protocol" "steal_policy" "topology" "affinity" "trigger" "implements" ] @keyword.control

; ─── Mots-clés Catégories & Algèbre ─────────────────────
[ "class" "instance" "law" "category" "functor" "natural_transform" "monad" "adjunction" ] @keyword.type

; ─── Mots-clés Preuves ──────────────────────────────────
[ "theorem" "proof" "qed" "axiom" "HIT" "apply" "rewrite" "assume" "have" "construct" "trivial" "case" "by" ] @keyword.control

; ─── Mots-clés Quantificateurs & Quantités ───────────────
[ "forall" "∀" "exists" "∃" "linear" "erased" ] @keyword.type

(quantity) @keyword.modifier

; ─── Mots-clés Logique ───────────────────────────────────
[ "fact" "rule" "query" "not" "and" "or" "relation" "conde" "fresh" "run" ] @keyword

; ─── Mots-clés Tests ─────────────────────────────────────
[ "test" "describe" "bench" "verify" "before_each" "before_all" "after_each" "after_all" "assert" "assert_eq" "assert_ne" "assert_err" "assert_not" "assert_is" "compare" "mock" "setup" ] @keyword.control

; ─── Mots-clés Probabiliste ──────────────────────────────
[ "prob" "model" "sample" "observe" "infer" ] @keyword

; ─── Mots-clés Temporel ─────────────────────────────────
[ "temporal" "property" "model_check" "stream_type" "after" "every" "timeout" "or_else" "debounce" "throttle" ] @keyword.control

; ─── Mots-clés Évolution ────────────────────────────────
[ "evolve" "search_space" "genome" "fitness" "constraint" "lifecycle" "canary" ] @keyword.control

; ─── Mots-clés Contrats ─────────────────────────────────
[ "contract" "invariant" "sla" "adaptive" "requires" "ensures" ] @keyword.control

; ─── Mots-clés Énergie / Capteurs ───────────────────────
[ "sensor" "module" "monitor" "track" "alert" "dashboard" "panel" "profile" "metric" "energy" ] @keyword

; ─── Mots-clés Narratif ─────────────────────────────────
[ "explain" ] @keyword

; ─── Mots-clés E-graphs ─────────────────────────────────
[ "egraph" "lang" "cost_fn" "extract" ] @keyword

; ─── Mots-clés Transpiler ───────────────────────────────
[ "transpile" "map_type" "map_expr" "map_decl" "registry" "pipeline" ] @keyword

; ─── Mots-clés FFI ──────────────────────────────────────
[ "extern" "native" "vessel" "export" ] @keyword

; ─── Mots-clés Meta ─────────────────────────────────────
[ "node" "macro" ] @keyword

; ─── Mots-clés Protocole ────────────────────────────────
[ "choice" "rec" "goto" "roles" ] @keyword.control

; ─── Opérateurs ──────────────────────────────────────────
[ "+" "-" "" "/" "%" "==" "!=" "<" ">" "<=" ">=" "=" "+=" "-=" "=" "/=" "!" "&&" "||" "++" "|>" ".." ":-" "=>" "->" "→" "<-" "::" "." "~>" "<->" "⊣" "<=>" "⊸" "-o" ">>=" ">>" "≔" "≡" "≢" "≤" "≥" "≃" "∈" "∉" "⊂" "⊃" "∘" "<>" "∨" "∧" "×" "÷" "**" ] @operator

; ─── Opérateurs mathématiques (unaires) ──────────────────
[ "∇" "√" "∑" "∏" "∫" "∂" ] @function.builtin

; ─── Délimiteurs ─────────────────────────────────────────
[ "(" ")" "{" "}" "[" "]" ] @punctuation.bracket

[ "," ";" ":" "|" "?" ] @punctuation.delimiter

; ─── Annotations (@complexity, @budget, etc.) ────────────
(annotation "@" @attribute (identifier) @attribute)

; ─── Atom literals (:name) ───────────────────────────────
(atom ":" @punctuation.special (identifier) @constant)

; ─── Fonctions ───────────────────────────────────────────
(fn_decl name: (identifier) @function)

(dist_fn name: (identifier) @function)

(eq_decl name: (identifier) @function)

(sig_decl name: (identifier) @function)

(call (identifier) @function.call)

(call (member (identifier) @function.method.call))

; ─── Types ───────────────────────────────────────────────
(type_name) @type

(prim_type) @type.builtin

; ─── Path type ───────────────────────────────────────────
(path_type "Path" @type.builtin)

; ─── Type Definitions ────────────────────────────────────
(struct_decl name: (type_name) @type.definition)

(enum_decl name: (type_name) @type.definition)

(actor_decl name: (type_name) @type.definition)

(effect_decl (type_name) @type.definition)

(type_alias (identifier) @type.definition)

(generic_type (type_name) @type)

(class_decl name: (type_name) @type.definition)

(instance_decl (type_name) @type)

(category_decl name: (type_name) @type.definition)

(functor_decl name: (type_name) @type.definition)

(natural_transform_decl name: (identifier) @function)

(monad_decl name: (type_name) @type.definition)

(adjunction_decl (type_name) @type)

(protocol_decl name: (type_name) @type.definition)

(supervisor_decl name: (type_name) @type.definition)

(scheduler_decl name: (type_name) @type.definition)

(hit_decl name: (type_name) @type.definition)

(contract_decl name: (type_name) @type.definition)

(sensor_decl name: (type_name) @type.definition)

(monitor_decl name: (type_name) @type.definition)

(dashboard_decl name: (type_name) @type.definition)

(egraph_decl name: (type_name) @type.definition)

(search_space_decl name: (type_name) @type.definition)

(spatial_topology_decl name: (type_name) @type.definition)

(registry_decl name: (type_name) @type.definition)

; ─── Test & Bench names ──────────────────────────────────
(test_decl name: (str) @string.special)

(describe_block name: (str) @string.special)

(bench_decl name: (str) @string.special)

(profile_block (str) @string.special)

; ─── Theorem ─────────────────────────────────────────────
(theorem_decl name: (identifier) @function.special)

(axiom_decl (identifier) @function.special)

; ─── Law ─────────────────────────────────────────────────
(law_decl name: (identifier) @property)

; ─── Metric ──────────────────────────────────────────────
(metric_decl (identifier) @property)

; ─── Invariant ───────────────────────────────────────────
(invariant_decl name: (identifier) @property)

; ─── Prob model ──────────────────────────────────────────
(prob_model_decl name: (identifier) @function)

; ─── Evolve ──────────────────────────────────────────────
(evolve_decl name: (identifier) @function)

; ─── Pipeline ────────────────────────────────────────────
(pipeline_decl name: (type_name) @type.definition)

; ─── Transpile ───────────────────────────────────────────
(transpile_decl (type_name) @type)

; ─── Egraph rule ─────────────────────────────────────────
(egraph_rule (identifier) @property)

; ─── Handler ─────────────────────────────────────────────
(handler_decl name: (identifier) @function)

; ─── Relation ────────────────────────────────────────────
(relation_decl name: (identifier) @function.builtin)

; ─── Steal policy ────────────────────────────────────────
(steal_policy_decl name: (_) @constant)

; ─── Panel ───────────────────────────────────────────────
(panel_decl (str) @string.special)

; ─── Audience ────────────────────────────────────────────
(audience_block "for" @keyword (_) @constant)

; ─── Variables et paramètres ─────────────────────────────
(var_decl name: (identifier) @variable)

(param (identifier) @variable.parameter)

(for_stmt (identifier) @variable)

(do_bind (identifier) @variable)

; ─── Littéraux ───────────────────────────────────────────
(int) @number

(float) @number.float

(str) @string

(bool_lit) @boolean

(duration_lit) @number.special

(unit_lit) @number.special

; ─── Commentaires ────────────────────────────────────────
(comment) @comment

; ─── Logique (Prolog-like) ───────────────────────────────
(fact_decl pred: (identifier) @function.builtin)

(rule_decl head: (latom pred: (identifier) @function.builtin))

(latom pred: (identifier) @function.builtin)

(lvar) @variable.builtin

; ─── Patterns ────────────────────────────────────────────
(ctor_pat (type_name) @constructor)

; ─── Struct littéral ─────────────────────────────────────
(struct_lit type: (type_name) @type)

; ─── Lambda ──────────────────────────────────────────────
[ "λ" "\\" ] @keyword.function

; ─── Self ────────────────────────────────────────────────
(self_expr) @variable.builtin

; ─── Refinement type ─────────────────────────────────────
(refinement_type (identifier) @variable)

; ─── Identifiants (fallback — doit rester en dernier) ────
(identifier) @variable
