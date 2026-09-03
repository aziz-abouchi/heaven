// ═══════════════════════════════════════════════════════════════════════════════
//  Heaven Grammar — Complete Specification v0.2.0
//  ═══════════════════════════════════════════════════════════════════════════════

module.exports = grammar({ name: "heaven",

extras: ($) => [/\s/, $.comment], word: ($) => $.identifier,

conflicts: ($) => [
  [$.match_stmt, $.match_expr, $._expr],
  [$._item, $._stmt],
  [$._item, $._expr],
  [$._stmt, $.do_expr],
  [$._stmt, $.bench_decl],
  [$.relation_decl, $._expr],
  [$.recv_block, $._expr],
  [$.contract_clause, $.binary],
  [$.unit_type, $.unit_expr],
  [$._expr, $.simple_expr],
  [$.pattern, $.ctor_pat],
  [$._pat, $.ctor_pat],
  [$.ctor_pat],
  [$._anno_arg, $.simple_expr],
  [$.pattern, $._pat],
  [$.refinement_type, $.simple_expr],
  [$.pattern, $.type_ident, $.ctor_pat],
  [$.pattern, $.type_ident],
  [$.ctor_pat, $.simple_expr],
  [$._expr, $.ctor_pat],
  [$.pattern, $._expr, $.simple_expr, $.ctor_pat],
  [$.pattern, $._expr],
  [$.pattern, $._expr, $.ctor_pat],
  [$.pattern, $.simple_expr, $.ctor_pat],
  [$.pattern, $.type_ident, $.simple_expr, $.ctor_pat],
  [$.pattern, $.simple_expr],
  [$.pattern, $._expr, $.simple_expr],
  [$.dependent_pair_type, $.simple_expr, $.ctor_pat],
  [$._expr, $.simple_expr, $.ctor_pat],
  [$.pattern, $.type_ident, $._expr],
  [$.list_pat, $.arr],
  [$.data_constructor],
  [$._pat, $.ctor_pat, $.type_ident],
  [$.unit_type, $.ctor_pat],
  [$.dependent_pair_type, $.simple_expr],
  [$.data_decl],
  [$.pattern, $.type_ident, $.applied_type, $.ctor_pat],
  [$.type_ident, $.applied_type, $.ctor_pat],
  [
    $.pattern,
    $.applied_type,
    $.ctor_pat,
  ],
  [$.type_ident, $.simple_expr, $.pattern],

],

rules: { source_file: ($) => repeat($._item),

_item: ($) =>
  choice(
    // Core
    $.fn_decl,
    $.sig_decl,
    $.eq_decl,
    $.import_decl,
    $.data_decl,
    $.dist_fn,
    $.struct_decl,
    $.enum_decl,
    $.impl_block,
    $.type_alias,
    // Logic
    $.fact_decl,
    $.rule_decl,
    $.query_expr,
    $.relation_decl,
    // Effects
    $.effect_decl,
    $.handler_decl,
    // Concurrency
    $.actor_decl,
    $.supervisor_decl,
    $.scheduler_decl,
    $.protocol_decl,
    $.steal_policy_decl,
    $.topology_decl,
    // Categories
    $.class_decl,
    $.instance_decl,
    $.category_decl,
    $.functor_decl,
    $.natural_transform_decl,
    $.monad_decl,
    $.adjunction_decl,
    // Proofs
    $.theorem_decl,
    $.axiom_decl,
    // Types avancés
    $.hit_decl,
    // Tests
    $.test_decl,
    $.describe_block,
    $.bench_decl,
    $.verify_block,
    // Probabilistic
    $.prob_model_decl,
    // Temporal
    $.temporal_property,
    $.model_check_block,
    $.stream_type_decl,
    // Evolution
    $.evolve_decl,
    $.search_space_decl,
    // Spatial
    $.spatial_topology_decl,
    // Contracts
    $.contract_decl,
    // Energy / Monitoring
    $.sensor_decl,
    $.monitor_decl,
    $.dashboard_decl,
    $.profile_block,
    // Narrative
    $.explain_block,
    // Transpiler
    $.transpile_decl,
    $.registry_decl,
    $.pipeline_decl,
    // E-graphs
    $.egraph_decl,
    // FFI
    $.extern_block,
    $.native_block,
    $.vessel_decl,
    // Meta
    $.node_decl,
    $.macro_decl,
    $.rewrite_decl,
    // Statements
    $._stmt,
    $.config_directive
  ),

// ═══════════════════════════════════════════════════════════════════════════
// CONFIG
// ═══════════════════════════════════════════════════════════════════════════

config_directive: ($) => prec.right(2, seq(
  ":",
  field("cmd", $.identifier),
  field("args", repeat($.config_arg)),
)),

config_arg: ($) => choice(
  $.identifier,
  $.type_name,
  $.str,
  $.int,
  $.float,
  $.bool_lit,
  $.config_slug,
),

config_slug: ($) => /[a-zA-Z][a-zA-Z0-9_-]*/,

// ═══════════════════════════════════════════════════════════════════════════
// COMMENTS
// ═══════════════════════════════════════════════════════════════════════════

comment: ($) =>
  token(
    choice(
      seq("--", /.*/),
      seq("//", /.*/),
      seq("/*", /[^*]*\*+([^/*][^*]*\*+)*/, "/"),
      seq("─", /.*/),
    )
  ),

// ═══════════════════════════════════════════════════════════════════════════
// ANNOTATIONS
// ═══════════════════════════════════════════════════════════════════════════

annotation: ($) => seq(
  "@",
  $.identifier,
  optional(seq("(", optional(sep1($._anno_arg, ",")), ")"))
),

_anno_arg: ($) => choice(
  seq($.identifier, ":", $._expr),
  $._expr
),

annotation_list: ($) => repeat1($.annotation),

// ═══════════════════════════════════════════════════════════════════════════
// FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

fn_decl: ($) =>
  seq(
    optional($.annotation_list),
    optional("pub"),
    optional("total"),
    optional("reactive"),
    optional("spatial"),
    optional("narrative"),
    "fn",
    field("name", $.identifier),
    optional($.tparams),
    field("params", $.params),
    optional(seq("->", $._type)),
    optional($.effect_row),
    optional($.contract_clause),
    optional(seq("with", sep1($.identifier, ","))),
    $.block
  ),

fn_sig: ($) => seq("fn", $.identifier, $.params, optional(seq("->", $._type)), ";"),

sig_decl: ($) => prec(3, seq(
  optional($.annotation_list),
  optional("pub"),
  optional("total"),
  field("name", choice($.identifier, "theorem", "spawn", "hook", "help", "skill", "prove")),
  ":",
  $._type
)),

eq_decl: ($) => prec(2, seq(
  optional($.annotation_list),
  optional("pub"),
  optional("total"),
  field("name", $.identifier),
  optional(":"),
  repeat1($.pattern),
  optional(seq(choice("|", "when"), field("guard", $._expr))),
  choice("=", "≔", "≡"),
  $._expr,
  optional(";")
)),

dist_fn: ($) =>
  seq(
    optional($.annotation_list),
    optional("pub"),
    "distributed",
    "fn",
    field("name", $.identifier),
    optional($.tparams),
    $.params,
    optional(seq("->", $._type)),
    optional($.effect_row),
    optional(seq("with", sep1($.identifier, ","))),
    $.block
  ),

params: ($) => seq("(", optional(sep1($.param, ",")), ")"),

param: ($) => seq( optional($.quantity), choice($.identifier, $.type_name, "self"), optional(seq(":", $._type)) ),

quantity: ($) => choice("0", "1", "ω", "linear", "erased"),

tparams: ($) =>
  seq(
    "<",
    sep1(seq(
      optional($.quantity),
      choice($.identifier, $.type_name),
      optional(seq(":", $._type))
    ), ","),
    ">"
  ),

list_pat: ($) => seq("[", optional(sep1($.pattern, ",")), optional(seq("|", $.pattern)), "]"),
tuple_pat: ($) => seq("(", $.pattern, ",", sep1($.pattern, ","), ")"),

effect_row: ($) => seq("!", "{", sep1($._type, ","), "}"),

contract_clause: ($) => prec(2, repeat1(choice( seq("requires", $._expr), seq("ensures", $._expr), seq("energy", choice("<=", "<"), $._expr), seq("within", $._expr), ))),

// ═══════════════════════════════════════════════════════════════════════════
// STRUCTS / ENUMS
// ═══════════════════════════════════════════════════════════════════════════

struct_decl: ($) =>
  seq(
    optional($.annotation_list),
    optional("pub"),
    "struct",
    field("name", $.type_name),
    optional($.tparams),
    "{",
    optional(seq(sep1(seq($.identifier, ":", $._type), ","), optional(","))),
    "}"
  ),

enum_decl: ($) =>
  seq(
    optional($.annotation_list),
    optional("pub"),
    "enum",
    field("name", $.type_name),
    optional($.tparams),
    "{",
    optional(
      seq(
        sep1(
          seq($.type_name, optional(seq("(", sep1($._type, ","), ")"))),
          ","
        ),
        optional(",")
      )
    ),
    "}"
  ),

impl_block: ($) =>
  seq("impl", $.type_name, optional($.tparams), "{", repeat($.fn_decl), "}"),

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

_type: ($) =>
  choice(
    $.forall_type,
    $.exists_type,
    $.arrow_type,
    $.linear_arrow_type,
    $.generic_type,
    $.applied_type,
    $.paren_type,
    $.prim_type,
    $.type_ident,
    $.fn_type,
    $.array_type,
    $.optional_type,
    $.unit_type,
    $.refinement_type,
    $.dependent_pair_type,
    $.path_type,
  ),

paren_type: ($) => prec(13, seq("(", $._type, ")")),
arrow_type: ($) => prec.right(1, seq($._type, choice("->", "→"), $._type)),
linear_arrow_type: ($) => prec.right(1, seq($._type, choice("-o", "⊸"), $._type)),

prim_type: ($) =>
  choice(
    "i8", "i16", "i32", "i64",
    "u8", "u16", "u32", "u64",
    "f32", "f64",
    "bool", "String", "Nat", "Int", "Float",
    "Joules", "Watts", "Celsius", "Duration",
    "Type", "Prop",
    "ℕ", "ℤ", "ℚ", "ℝ", "ℂ",
    "𝟚", "⊤", "⊥",
  ),

type_ident: ($) => prec(-1, choice($.identifier, $.type_name)),
generic_type: ($) => prec(20, seq($.type_name, "<", sep1($._type, ","), ">")),
applied_type: ($) => prec(-2, seq($.type_name, repeat1($._type))),

fn_type: ($) =>
  seq("fn", "(", optional(sep1($._type, ",")), ")", "->", $._type),
array_type: ($) => seq("[", $._type, "]"),
optional_type: ($) => seq("?", $._type),
unit_type: ($) => seq("(", ")"),

refinement_type: ($) => seq(
  "{",
  $.identifier,
  ":",
  $._type,
  "|",
  sep1($._expr, ","),
  "}"
),

dependent_pair_type: ($) => seq(
  "(",
  $.identifier, ":", $._type,
  ")",
  choice("×", "**"),
  $._type
),

path_type: ($) => prec(15, seq("Path", $._type, $._expr, $._expr)),

type_alias: ($) =>
  seq("type", choice($.identifier, $.type_name), optional($.tparams), "=", $._type, ";"),

// ═══════════════════════════════════════════════════════════════════════════
// IMPORTS
// ═══════════════════════════════════════════════════════════════════════════

import_decl: ($) => seq(
  "import",
  $.str
),

// ═══════════════════════════════════════════════════════════════════════════
// DATA (ADT)
// ═══════════════════════════════════════════════════════════════════════════

data_decl: ($) => seq(
  "data",
  field("name", choice($.type_name, $.prim_type)),
  optional($.tparams),
  "=",
  $.data_constructor,
  repeat(seq('|', $.data_constructor))
),

data_constructor: ($) => seq(
  choice($.type_name, $.prim_type),
  repeat($.ctor_arg_type)
),

ctor_arg_type: ($) => choice(
  $.prim_type,
  $.generic_type,
  $.paren_type,
  $.type_name,
),

// ═══════════════════════════════════════════════════════════════════════════
// TYPECLASSES & INSTANCES
// ═══════════════════════════════════════════════════════════════════════════

class_decl: ($) => seq(
  "class",
  field("name", $.type_name),
  "(",
  sep1($.param, ","),
  ")",
  optional(seq("extends", sep1($.type_name, ","))),
  "{",
  repeat(choice($.sig_decl, $.eq_decl, $.law_decl)),
  "}"
),

instance_decl: ($) => seq(
  "instance",
  $.type_name,
  "(",
  sep1($._type, ","),
  ")",
  "{",
  repeat($.eq_decl),
  "}"
),

law_decl: ($) => seq(
  "law",
  field("name", $.identifier),
  ":",
  $._expr
),

// ═══════════════════════════════════════════════════════════════════════════
// CATEGORIES, FUNCTORS, NATURAL TRANSFORMS, MONADS
// ═══════════════════════════════════════════════════════════════════════════

category_decl: ($) => seq(
  "category",
  field("name", $.type_name),
  "{",
  repeat(choice($.sig_decl, $.eq_decl, $.law_decl)),
  "}"
),

functor_decl: ($) => seq(
  "functor",
  field("name", $.type_name),
  ":",
  $._type,
  choice("->", "→", "~>"),
  $._type,
  "{",
  repeat(choice($.sig_decl, $.eq_decl, $.law_decl)),
  "}"
),

natural_transform_decl: ($) => seq(
  "natural_transform",
  field("name", $.identifier),
  ":",
  $._type,
  "~>",
  $._type,
  "{",
  repeat(choice($.sig_decl, $.eq_decl, $.law_decl)),
  "}"
),

monad_decl: ($) => seq(
  "monad",
  field("name", $.type_name),
  ":",
  $._type,
  choice("->", "→"),
  $._type,
  "{",
  repeat(choice($.sig_decl, $.eq_decl, $.law_decl)),
  "}"
),

adjunction_decl: ($) => seq(
  "adjunction",
  "(",
  $.type_name,
  choice("⊣", "<=>"),
  $.type_name,
  ")",
  ":",
  $._type,
  "<->",
  $._type,
  "{",
  repeat(choice($.sig_decl, $.eq_decl, $.law_decl)),
  "}"
),

// ═══════════════════════════════════════════════════════════════════════════
// EFFECTS (ALGEBRAIC)
// ═══════════════════════════════════════════════════════════════════════════

effect_decl: ($) =>
  seq("effect", $.type_name, optional($.tparams), "{",
    repeat($.fn_sig),
    "}"),

handler_decl: ($) => seq(
  "handler",
  field("name", $.identifier),
  optional($.params),
  ":",
  $._type,
  "{",
  optional(seq(sep1($.handler_arm, ","), optional(","))),
  "}"
),

handler_arm: ($) => seq(
  choice("return", $.identifier),
  optional(seq("(", optional(sep1($._pat, ",")), ")")),
  optional($.identifier),
  "=>",
  $._expr
),

handle_expr: ($) =>
  prec(15, seq(
    "handle",
    $._expr,
    "with",
    "{",
    sep1(seq($._pat, "=>", $.block), ","),
    optional(","),
    "}"
  )),

perform_expr: ($) => prec(10, seq("perform", $._expr)),

// ═══════════════════════════════════════════════════════════════════════════
// ACTORS & CONCURRENCY
// ═══════════════════════════════════════════════════════════════════════════

actor_decl: ($) =>
  seq(
    optional($.annotation_list),
    "actor",
    field("name", $.type_name),
    optional($.params),
    optional(seq("implements", sep1($._type, ","))),
    "{",
    repeat(choice($.var_decl, $.recv_block, $.fn_decl, $.metric_decl)),
    "}"
  ),

recv_block: ($) =>
  seq(
    "receive",
    "{",
    sep1(seq($._pat, "=>", choice($.block, $._expr)), ","),
    optional(","),
    "}"
  ),

become_stmt: ($) => seq("become", $._expr, ";"),

metric_decl: ($) => seq(
  optional($.annotation_list),
  "metric",
  $.identifier,
  ":",
  $._type,
  optional(seq("=", $._expr)),
  optional(";"),
),

supervisor_decl: ($) => seq(
  "supervisor",
  field("name", $.type_name),
  "{",
  repeat(seq($.identifier, ":", $._expr, ",")),
  "}"
),

scheduler_decl: ($) => seq(
  optional($.annotation_list),
  "scheduler",
  field("name", $.type_name),
  optional(seq("implements", sep1($._type, ","))),
  "{",
  repeat(choice(
    $.var_decl,
    $.fn_decl,
    $.eq_decl,
    $.sig_decl,
    seq($.identifier, ":", $._expr, ","),
  )),
  "}"
),

protocol_decl: ($) => seq(
  "protocol",
  field("name", $.type_name),
  "{",
  optional(seq("roles", ":", "{", sep1($.type_name, ","), "}", ",")),
  repeat($.protocol_step),
  "}"
),

protocol_step: ($) => prec.right(choice(
  seq($.type_name, "->", $.type_name, ":", $.type_name, optional($.params)),
  seq("choice", "at", $.type_name, "{", repeat($.protocol_branch), "}"),
  seq("rec", $.type_name, "{", repeat($.protocol_step), "}"),
  seq("goto", $.type_name),
)),

protocol_branch: ($) => prec.right(seq(
  $._pat, "=>", repeat($.protocol_step),
)),

steal_policy_decl: ($) => seq(
  "steal_policy",
  field("name", $._pat),
  "{",
  repeat(choice(
    $.trigger_block,
    seq($.identifier, ":", $._expr, ","),
  )),
  "}"
),

trigger_block: ($) => seq(
  "trigger",
  "when",
  $._expr,
  $.block
),

topology_decl: ($) => seq(
  "topology",
  optional(field("name", $.identifier)),
  "{",
  repeat(choice(
    $.node_decl,
    $.affinity_decl,
    seq($.identifier, ":", $._expr, ","),
  )),
  "}"
),

affinity_decl: ($) => seq(
  "affinity",
  field("name", $._pat),
  "{",
  repeat($._stmt),
  "}"
),

// ═══════════════════════════════════════════════════════════════════════════
// PROOFS & THEOREMS
// ═══════════════════════════════════════════════════════════════════════════

theorem_decl: ($) => prec.right(seq(
  "theorem",
  field("name", $.identifier),
  ":",
  $._type,
  optional(seq("{", $.proof_block, "}"))
)),

proof_block: ($) => seq(
  "proof",
  optional(seq("by", $.proof_strategy)),
  "{",
  repeat($.proof_step),
  "}"
),

proof_strategy: ($) => choice(
  seq("induction", $.identifier),
  seq("cases", $.identifier),
  "contradiction",
  "trivial",
  "construction",
  "information_theory",
  $.identifier,
),

proof_step: ($) => prec.right(choice(
  seq("case", $._pat, "=>", repeat($.proof_step)),
  seq("apply", $._expr),
  seq("rewrite", $._expr),
  seq("assume", $.identifier, ":", $._expr),
  seq("have", $.identifier, ":", $._expr, "by", $._expr),
  seq("construct", $._expr),
  "trivial",
  "qed",
)),

axiom_decl: ($) =>
  seq(
    "axiom",
    $.identifier,
    optional($.tparams),
    ":",
    $._type,
    optional(";")
  ),

// ═══════════════════════════════════════════════════════════════════════════
// HoTT — Higher Inductive Types
// ═══════════════════════════════════════════════════════════════════════════

hit_decl: ($) => seq(
  "HIT",
  field("name", $.type_name),
  optional($.tparams),
  "{",
  optional(seq(sep1($.hit_constructor, ","), optional(","))),
  "}"
),

hit_constructor: ($) => seq(
  $.identifier,
  ":",
  $._type,
),

// ═══════════════════════════════════════════════════════════════════════════
// LOGIC (PROLOG + KANREN)
// ═══════════════════════════════════════════════════════════════════════════

fact_decl: ($) =>
  seq(
    "fact",
    field("pred", $.identifier),
    "(",
    optional(sep1($._lterm, ",")),
    ")",
    "."
  ),

rule_decl: ($) =>
  seq(
    "rule",
    field("head", $.latom),
    optional(seq(":-", sep1($._rbody, ","))),
    "."
  ),

_rbody: ($) => choice($.latom, $.lcmp, $.lnot),

latom: ($) =>
  seq(
    field("pred", $.identifier),
    "(",
    optional(sep1($._lterm, ",")),
    ")"
  ),

lcmp: ($) =>
  seq(
    $._lterm,
    choice("==", "!=", ">", "<", ">=", "<="),
    $._lterm
  ),

lnot: ($) => seq("not", "(", $.latom, ")"),

_lterm: ($) =>
  choice($.lvar, $.identifier, $.int, $.float, $.str, $.llist, "_"),

lvar: ($) => /[A-Z][a-zA-Z0-9_]*/,

llist: ($) =>
  seq(
    "[",
    optional(
      seq(sep1($._lterm, ","), optional(seq("|", $._lterm)))
    ),
    "]"
  ),

// miniKanren
relation_decl: ($) => seq(
  "relation",
  field("name", $.identifier),
  $.params,
  "{",
  repeat(choice($.conde_expr, $.fresh_expr, $._stmt, $._expr)),
  "}"
),

conde_expr: ($) => seq(
  "conde",
  "{",
  repeat($.block),
  "}"
),

fresh_expr: ($) => seq(
  "fresh",
  "(",
  sep1($.identifier, ","),
  ")",
  $.block
),

run_expr: ($) => seq(
  "run",
  choice($.int, "*"),
  "(",
  sep1($.identifier, ","),
  ")",
  $.block
),

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

test_decl: ($) => seq(
  "test",
  field("name", $.str),
  optional($.tag_list),
  optional($.with_clause),
  $.block
),

describe_block: ($) => seq(
  "describe",
  field("name", $.str),
  "{",
  repeat(choice(
    $.test_decl,
    $.describe_block,
    $.bench_decl,
    $.before_block,
    $.after_block,
    $.fn_decl,
    $.var_decl,
  )),
  "}"
),

bench_decl: ($) => seq(
  "bench",
  field("name", $.str),
  optional($.with_clause),
  "{",
  repeat(choice(
    seq("setup", $.block),
    seq("run", $.block),
    $.assert_stmt,
    $.compare_block,
    $._stmt,
  )),
  "}"
),

verify_block: ($) => seq(
  "verify",
  $._expr,
  optional($.with_clause),
  $.block
),

before_block: ($) => seq(choice("before_each", "before_all"), $.block),
after_block: ($) => seq(choice("after_each", "after_all"), $.block),

tag_list: ($) => repeat1(seq("@", $.identifier)),

with_clause: ($) => seq(
  "with",
  $._expr,
  "as",
  choice(
    $.identifier,
    seq("(", sep1($.identifier, ","), ")")
  )
),

assert_stmt: ($) => choice(
  seq("assert", $._expr, ";"),
  seq("assert_eq", $._expr, ",", $._expr, ";"),
  seq("assert_ne", $._expr, ",", $._expr, ";"),
  seq("assert_err", $._expr, ";"),
  seq("assert_not", $._expr, ";"),
  seq("assert_is", $._expr, ",", $._type, ";"),
),

compare_block: ($) => seq(
  "compare",
  "{",
  repeat(seq($._expr, ",")),
  "}"
),

mock_expr: ($) => prec.right(10, seq(
  "mock",
  $._expr,
  optional(seq("->", $._expr))
)),

// ═══════════════════════════════════════════════════════════════════════════
// PROBABILISTIC
// ═══════════════════════════════════════════════════════════════════════════

prob_model_decl: ($) => seq(
  "prob",
  "model",
  field("name", $.identifier),
  $.params,
  optional(seq("->", $._type)),
  $.block
),

sample_expr: ($) => prec(10, seq("sample", "(", $._expr, ")")),
observe_expr: ($) => prec(10, seq("observe", "(", $._expr, ",", $._expr, ")")),
infer_expr: ($) => prec(10, seq(
  "infer",
  "(",
  $._expr,
  optional(seq(",", sep1($._anno_arg, ","))),
  ")"
)),

// ═══════════════════════════════════════════════════════════════════════════
// TEMPORAL
// ═══════════════════════════════════════════════════════════════════════════

temporal_property: ($) => seq(
  "temporal",
  "property",
  field("name", $.identifier),
  ":",
  $.temporal_expr
),

temporal_expr: ($) => $._expr,

model_check_block: ($) => seq(
  "model_check",
  $.type_name,
  "{",
  repeat(seq($.identifier, ":", $._expr, ",")),
  "}"
),

stream_type_decl: ($) => seq(
  "stream_type",
  $.type_name,
  "=",
  $._type,
),

after_expr: ($) => prec(10, seq("after", $._expr, $.block)),
every_expr: ($) => prec(10, seq("every", $._expr, $.block)),
timeout_expr: ($) => prec(10, seq(
  "timeout", $._expr, $.block,
  optional(seq("or_else", $.block))
)),
debounce_expr: ($) => prec(10, seq("debounce", $._expr, $.block)),
throttle_expr: ($) => prec(10, seq("throttle", $._expr, $.block)),

// ═══════════════════════════════════════════════════════════════════════════
// EVOLUTION
// ═══════════════════════════════════════════════════════════════════════════

evolve_decl: ($) => seq(
  "evolve",
  optional($.identifier),
  field("name", choice($.identifier, $.type_name)),
  "{",
  repeat(choice(
    $.genome_block,
    $.fitness_block,
    $.constraint_decl,
    $.lifecycle_block,
    seq($.identifier, ":", $._expr, ","),
    $.fn_decl,
  )),
  "}"
),

search_space_decl: ($) => seq(
  "search_space",
  field("name", $.type_name),
  "{",
  repeat(choice(
    $.type_alias,
    $.struct_decl,
    $.invariant_decl,
    $.fn_decl,
  )),
  "}"
),

genome_block: ($) => seq(
  "genome",
  "{",
  repeat(seq(
    $.identifier,
    ":",
    $._type,
    optional(seq("in", $._expr)),
    ","
  )),
  "}"
),

fitness_block: ($) => seq(
  "fitness",
  $.params,
  optional(seq("->", $._type)),
  $.block
),

constraint_decl: ($) => prec.right(seq(
  "constraint",
  $.identifier,
  ":",
  $._expr
)),

lifecycle_block: ($) => seq(
  "lifecycle",
  $.block
),

canary_expr: ($) => seq(
  "canary",
  "(",
  $._expr,
  ",",
  sep1($._anno_arg, ","),
  ")",
  $.block
),

// ═══════════════════════════════════════════════════════════════════════════
// SPATIAL
// ═══════════════════════════════════════════════════════════════════════════

spatial_topology_decl: ($) => seq(
  "topology",
  field("name", $.type_name),
  optional($.tparams),
  "{",
  repeat(choice(
    $.sig_decl,
    $.eq_decl,
    $.fn_decl,
    seq($.identifier, ":", $._type, ","),
  )),
  "}"
),

spatial_transform: ($) => seq(
  "spatial",
  "transform",
  ":",
  $._type,
  "->",
  $._type,
  "{",
  repeat($.spatial_rule),
  "}"
),

spatial_rule: ($) => seq(
  "rule",
  $.identifier,
  "at",
  $.identifier,
  optional(seq("when", $._expr)),
  $.block
),

// ═══════════════════════════════════════════════════════════════════════════
// CONTRACTS
// ═══════════════════════════════════════════════════════════════════════════

contract_decl: ($) => seq(
  "contract",
  field("name", $.type_name),
  "{",
  repeat(choice(
    $.invariant_decl,
    $.sla_block,
    $.adaptive_contract,
    $.fn_decl,
  )),
  "}"
),

invariant_decl: ($) => prec(1, seq(
  "invariant",
  optional(field("name", $.identifier)),
  choice(
    $.block,
    $._expr,
  )
)),

sla_block: ($) => seq(
  "sla",
  "{",
  repeat(seq($._expr, ",")),
  "}"
),

adaptive_contract: ($) => seq(
  "adaptive",
  optional("contract"),
  field("name", $.identifier),
  "{",
  repeat(choice(
    seq($.identifier, ":", $._expr),
    $.fn_decl,
    $.trigger_block,
  )),
  "}"
),

// ═══════════════════════════════════════════════════════════════════════════
// ENERGY / SENSORS / MONITORING
// ═══════════════════════════════════════════════════════════════════════════

sensor_decl: ($) => prec.right(seq(
  "sensor",
  optional("module"),
  field("name", $.type_name),
  optional(seq(":", $._type)),
  optional(seq("{",
    repeat(choice($.fn_sig, $.fn_decl, $.sig_decl, $.eq_decl, seq($.identifier, ":", $._expr, ","))),
  "}"))
)),

monitor_decl: ($) => seq(
  optional($.annotation_list),
  "monitor",
  field("name", $.type_name),
  "{",
  repeat(choice(
    seq("track", "{", repeat(seq($._expr, ",")), "}"),
    seq("alert", "when", $._expr, $.block),
    $.fn_decl,
    $.eq_decl,
    seq($.identifier, ":", $._expr, ","),
  )),
  "}"
),

dashboard_decl: ($) => seq(
  "dashboard",
  field("name", $.type_name),
  "{",
  repeat(choice(
    $.panel_decl,
    seq($.identifier, ":", $._expr, ","),
  )),
  "}"
),

panel_decl: ($) => seq(
  "panel",
  $.str,
  "{",
  repeat(seq($.identifier, ":", $._expr, ",")),
  "}"
),

profile_block: ($) => seq(
  "profile",
  $.str,
  $.block
),

// ═══════════════════════════════════════════════════════════════════════════
// NARRATIVE
// ═══════════════════════════════════════════════════════════════════════════

explain_block: ($) => seq(
  "explain",
  $._expr,
  "{",
  repeat($.audience_block),
  "}"
),

audience_block: ($) => seq(
  "for",
  $._pat,
  "{",
  repeat(seq($.identifier, ":", $._expr, ",")),
  "}"
),

// ═══════════════════════════════════════════════════════════════════════════
// E-GRAPHS
// ═══════════════════════════════════════════════════════════════════════════

egraph_decl: ($) => seq(
  "egraph",
  field("name", $.type_name),
  "{",
  repeat(choice(
    $.lang_block,
    $.egraph_rule,
    $.cost_fn_decl,
    $.extract_decl,
  )),
  "}"
),

lang_block: ($) => seq(
  "lang",
  $.type_name,
  "{",
  optional(seq(sep1(seq(
    $.type_name,
    ":",
    $._type,
  ), ","), optional(","))),
  "}"
),

egraph_rule: ($) => seq(
  "rule",
  $.identifier,
  ":",
  $._expr,
  "=>",
  $._expr,
  optional(seq("when", $._expr)),
),

cost_fn_decl: ($) => seq(
  "cost_fn",
  $.identifier,
  $.params,
  "->",
  $._type,
  "{",
  optional(seq(sep1(seq($._pat, "=>", $._expr), ","), optional(","))),
  "}"
),

extract_decl: ($) => seq(
  "extract",
  $.identifier,
  ":",
  $._expr,
),

// ═══════════════════════════════════════════════════════════════════════════
// TRANSPILER
// ═══════════════════════════════════════════════════════════════════════════

transpile_decl: ($) => seq(
  "transpile",
  $.type_name,
  $.type_name,
  "{",
  repeat(choice(
    $.map_type_rule,
    $.map_expr_rule,
    $.map_decl_rule,
    $.fn_decl,
  )),
  "}"
),

map_type_rule: ($) => seq("map_type", $._expr, "=", $._expr),
map_expr_rule: ($) => seq("map_expr", $._expr, "=", $._expr),
map_decl_rule: ($) => seq("map_decl", $._expr, "=", $._expr),

registry_decl: ($) => seq(
  "registry",
  field("name", $.type_name),
  "{",
  repeat(seq($.identifier, ":", $._expr, ",")),
  "}"
),

pipeline_decl: ($) => seq(
  "pipeline",
  field("name", $.type_name),
  optional(seq(":", $._type, "~>", $._type)),
  "{",
  repeat(choice(
    $.sig_decl,
    $.eq_decl,
    $.fn_decl,
    seq($.identifier, ":", $._expr, ","),
  )),
  "}"
),

// ═══════════════════════════════════════════════════════════════════════════
// FFI
// ═══════════════════════════════════════════════════════════════════════════

extern_block: ($) =>
  seq(
    "extern",
    optional($.str),
    "{",
    repeat($.fn_sig),
    "}"
  ),

native_block: ($) =>
  seq("native", $.identifier, "{", token(prec(-1, /[^}]+/)), "}"),

vessel_decl: ($) =>
  seq("vessel", $.type_name, "from", $.str, "{",
    repeat(seq("export", $.identifier, $.params, optional(seq("->", $._type)), ";")),
    "}"),

// ═══════════════════════════════════════════════════════════════════════════
// META
// ═══════════════════════════════════════════════════════════════════════════

node_decl: ($) =>
  seq(
    "node",
    $.identifier,
    "{",
    repeat(seq($.identifier, ":", $._expr, ",")),
    "}"
  ),

macro_decl: ($) =>
  seq(
    "macro",
    $.identifier,
    "(",
    optional(sep1($.identifier, ",")),
    ")",
    $.block
  ),

rewrite_decl: ($) =>
  seq(
    "rewrite",
    "{",
    "match",
    ":",
    $._expr,
    ",",
    "replace",
    ":",
    $._expr,
    optional(","),
    "}"
  ),

// ═══════════════════════════════════════════════════════════════════════════
// STATEMENTS
// ═══════════════════════════════════════════════════════════════════════════

_stmt: ($) =>
  choice(
    $.var_decl,
    $.assign,
    $.ret,
    $.if_stmt,
    $.while_stmt,
    $.for_stmt,
    $.loop_stmt,
    $.match_stmt,
    $.become_stmt,
    $.assert_stmt,
    $.do_bind,
    $.after_expr,
    $.every_expr,
    $.timeout_expr,
    $.debounce_expr,
    $.throttle_expr,
    seq("break", ";"),
    seq("continue", ";"),
    seq($._expr, ";"),
    $.fact_decl,
    $.rule_decl,
    $.store_stmt,
  ),

store_stmt: ($) => seq(
  "store",
  field("target", choice($.identifier, $.member, $.index)),
  optional(seq("=", field("value", $._expr))),
  ";"
),

var_decl: ($) =>
  prec.right(seq(
    choice("let", "var", "const"),
    optional("mut"),
    optional($.quantity),
    field("name", choice($.identifier, $.tuple_pat)),
    optional(seq(":", $._type)),
    optional(seq("=", $._expr)),
    optional(";")
  )),

do_bind: ($) => seq(
  $.identifier,
  "<-",
  $._expr,
  ";"
),

assign: ($) =>
  seq(
    choice($.identifier, $.member, $.index),
    choice("=", "+=", "-=", "*=", "/="),
    $._expr,
    ";"
  ),

ret: ($) => seq("return", optional($._expr), ";"),

if_stmt: ($) =>
  prec.right(
    seq(
      "if",
      $._expr,
      $.block,
      optional(seq("else", choice($.block, $.if_stmt)))
    )
  ),

while_stmt: ($) => seq("while", $._expr, $.block),
for_stmt: ($) => seq("for", $.identifier, "in", $._expr, $.block),
loop_stmt: ($) => seq("loop", $.block),

match_stmt: ($) =>
  seq(
    "match",
    $._expr,
    "{",
    repeat1(
      seq(
        $._pat,
        optional(seq("if", $._expr)),
        "=>",
        choice($.block, seq($._expr, ","))
      )
    ),
    "}"
  ),

// ═══════════════════════════════════════════════════════════════════════════
// EXPRESSIONS
// ═══════════════════════════════════════════════════════════════════════════

_expr: ($) =>
  choice(
    $.math_expr,
    $.identifier,
    $.type_name,
    $.int,
    $.float,
    $.str,
    $.bool_lit,
    $.arr,
    $.struct_lit,
    $.paren_expr,
    $.self_expr,
    $.unary,
    $.binary,
    $.call,
    $.member,
    $.index,
    $.lambda,
    $.if_expr,
    $.match_expr,
    $.spawn,
    $.await_expr,
    $.send,
    $.pipe,
    $.range,
    $.recv_expr,
    $.query_expr,
    $.handle_expr,
    $.perform_expr,
    $.do_expr,
    $.sample_expr,
    $.observe_expr,
    $.infer_expr,
    $.run_expr,
    $.conde_expr,
    $.fresh_expr,
    $.mock_expr,
    $.canary_expr,
    $.unit_expr,
    $.block,
    $.atom,
    $.duration_lit,
    $.unit_lit,
    $.list_comprehension,
    $.app_expr,
  ),

list_comprehension: ($) => seq( "[", $._expr, repeat1(seq("for", $.identifier, "in", $._expr)), optional(seq("if", $._expr)), "]" ),
unit_expr: ($) => seq("(", ")"),
paren_expr: ($) => seq("(", $._expr, ")"),
self_expr: ($) => "self",

atom: ($) => seq(":", $.identifier),

duration_lit: ($) => /[0-9][0-9_]*(ns|us|ms|s|m|h|d)/,

unit_lit: ($) => /[0-9][0-9_]*\.?[0-9]*(J|W|C|KB|MB|GB|TB|Hz|GHz)/,

unary: ($) => prec(8, seq(choice("-", "not"), $._expr)),

binary: ($) =>
  choice(
    prec.left(-2, seq($._expr, "implies", $._expr)),
    prec.left(0, seq($._expr, "within", $._expr)),
    prec.left(1, seq($._expr, choice("or", "||", "∨"), $._expr)),
    prec.left(2, seq($._expr, choice("and", "&&", "∧"), $._expr)),
    prec.left(3, seq($._expr, choice("==", "!=", "≡", "≢"), $._expr)),
    prec.left(4, seq($._expr, choice("<", ">", "<=", ">=", "≤", "≥", "∈", "∉", "⊂", "⊃", "≃"), $._expr)),
    prec.left(5, seq($._expr, choice("++", "∘", "<>"), $._expr)),
    prec.left(6, seq($._expr, choice("+", "-"), $._expr)),
    prec.left(7, seq($._expr, choice("*", "/", "%", "×", "÷"), $._expr)),
    prec.right(0, seq($._expr, ">>=", $._expr)),
    prec.right(0, seq($._expr, ">>", $._expr)),
  ),

call: ($) => prec.dynamic(2, prec(13, seq($._expr, "(", optional(sep1($._expr, ",")), ")"))),

member: ($) => prec(14, seq($._expr, choice(".", "::"), $.identifier)),

index: ($) => prec(14, seq($._expr, "[", $._expr, "]")),

lambda: ($) =>
  choice(
    prec.right(-3, seq("|", optional(sep1($.identifier, ",")), "|", choice($.block, $._expr))),
    prec.right(-3, seq(choice("λ", "\\", "fn"), "(", optional(sep1($.param, ",")), ")", choice("=>", "→"), $._expr))
  ),

if_expr: ($) =>
  prec.right(
    1,
    seq("if", $._expr, "then", $._expr, "else", $._expr)
  ),

match_expr: ($) =>
  prec(
    1,
    seq(
      "match",
      $._expr,
      "{",
      repeat1(
        seq(
          $._pat,
          optional(seq("if", $._expr)),
          "=>",
          choice($.block, seq($._expr, ","))
        )
      ),
      "}"
    )
  ),

spawn: ($) => prec(10, seq("spawn", $._expr)),

await_expr: ($) => prec(10, seq("await", $._expr)),

send: ($) => prec.right(9, seq($._expr, "!", $._expr)),

pipe: ($) => prec.left(-1, seq($._expr, "|>", $._expr)),

range: ($) => prec.left(11, seq($._expr, "..", $._expr)),

recv_expr: ($) =>
  seq(
    "receive",
    "{",
    sep1(seq($._pat, "=>", $._expr), ","),
    "}"
  ),

query_expr: ($) => seq("query", sep1($.latom, ","), "?"),

do_expr: ($) => seq(
  "do",
  "{",
  repeat(choice($.do_bind, $._stmt)),
  optional($._expr),
  "}"
),

simple_expr: ($) =>
  choice(
    $.identifier,
    $.type_name,
    $.int,
    $.float,
    $.str,
    $.bool_lit,
    $.paren_expr,
    $.struct_lit,
    $.atom
  ),

app_expr: ($) =>
  prec.dynamic(1, prec.left(
    12,
    seq(
      $.simple_expr,
      repeat1($.simple_expr)
    )
  )),

// ═══════════════════════════════════════════════════════════════════════════
// PATTERNS
// ═══════════════════════════════════════════════════════════════════════════

_pat: ($) =>
  choice(
    "_",
    $.identifier,
    $.int,
    $.str,
    $.bool_lit,
    $.atom,
    $.tuple_pat,
    $.list_pat,
    seq("(", $.ctor_pat, ")")
  ),

ctor_pat: ($) =>
  seq(
    choice($.type_name, $.identifier),
    repeat1($._pat)
  ),

pattern: ($) =>
  choice(
    $.identifier,
    prec(-1, $.type_name),
    $.int,
    $.float,
    $.str,
    $.bool_lit,
    seq("(", $.ctor_pat, ")"),
    $.list_pat,
    $.tuple_pat,
    seq("(", $.pattern, ")"),
    "_"
  ),

// ═══════════════════════════════════════════════════════════════════════════
// STRUCT LITERAL
// ═══════════════════════════════════════════════════════════════════════════

struct_lit: ($) =>
  prec(-1, seq(
    field("type", $.type_name),
    "{",
    optional(seq(sep1(seq($.identifier, ":", $._expr), ","), optional(","))),
    "}"
  )),

// ═══════════════════════════════════════════════════════════════════════════
// BLOCK
// ═══════════════════════════════════════════════════════════════════════════

block: ($) =>
  seq("{", repeat($._stmt), optional($._expr), "}"),

// ═══════════════════════════════════════════════════════════════════════════
// LITERALS
// ═══════════════════════════════════════════════════════════════════════════

type_name: ($) => /[A-Z][a-zA-Z0-9_]*/,

identifier: ($) => /[a-z_α-ωℕℤℚℝℂ∀∃][a-zA-Z0-9_α-ωΑ-Ωℕℤℚℝℂ₀-₉⁰-⁹′]*/,

int: ($) =>
  token(
    choice(/[0-9][0-9_]*/, /0x[0-9a-fA-F_]+/, /0b[01_]+/)
  ),

float: ($) => /[0-9][0-9_]*\.[0-9][0-9_]*/,

str: ($) =>
  seq(
    '"',
    optional(token.immediate(/[^"\\]*(\\.[^"\\]*)*/)),
    '"'
  ),

bool_lit: ($) => choice("true", "false"),

arr: ($) =>
  seq("[", optional(seq(sep1($._expr, ","), optional(seq("|", $._expr)))), "]"),

// ═══════════════════════════════════════════════════════════════════════════
// QUANTIFIERS
// ═══════════════════════════════════════════════════════════════════════════

forall_type: ($) => prec.right(0, seq(
  choice("forall", "∀"),
  choice(
    // Style 1 : forall (a b : Term) (c : Nat) . Body  — binders typés parenthésés
    seq(
      repeat1(seq("(", repeat1(seq(optional($.quantity), $.identifier)), ":", $._type, ")")),
      choice(".", "→", "->"),
      $._type
    ),
    // Style 2 : forall a b c . Body — binders nus, non typés
    seq(
      repeat1(seq(optional($.quantity), $.identifier)),
      choice(".", "→", "->"),
      $._type
    )
  )
)),

exists_type: ($) => prec.right(0, seq(
  choice("exists", "∃"),
  repeat1($.identifier),
  choice(".", "×"),
  $._type
)),

// ═══════════════════════════════════════════════════════════════════════════
// NOTATION MATHÉMATIQUE
// ═══════════════════════════════════════════════════════════════════════════

math_expr: ($) => prec(8, choice(
  seq("∑", "(", $._expr, ",", $._expr, ",", $._expr, ")"),
  seq("∏", "(", $._expr, ",", $._expr, ",", $._expr, ")"),
  seq("∫", "(", $._expr, ",", $._expr, ",", $._expr, ")"),
  seq("∂", "(", $._expr, ",", $._expr, ")"),
  seq("∇", $._expr),
  seq("√", $._expr),
)),
}, });

function sep1(r, d) { return seq(r, repeat(seq(d, r))); }
