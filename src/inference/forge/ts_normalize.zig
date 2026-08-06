const std = @import("std");

pub const NodeKind = enum {
    Function, Call, Return, BinOp, If, Loop, VarDecl, Assign,
    LiteralInt, LiteralFloat, LiteralString, LiteralBool,
    Identifier, TypeName, StructDecl, EnumDecl, ImplBlock,
    FactDecl, RuleDecl, QueryExpr, ActorDecl, SpawnExpr, SendExpr,
    MatchExpr, Lambda, PipeExpr, RangeExpr, EffectDecl, HandleExpr,
    Quote,
    Unquote,
    FieldAccess, IndexExpr, Block, Unknown,
    SigDecl, EqDecl,
};

pub fn classifyNode(ntype: []const u8) NodeKind {
    if (eql(ntype, "fn_decl") or eql(ntype, "dist_fn") or eql(ntype, "function_declaration") or eql(ntype, "function_definition") or eql(ntype, "fn_proto")) return .Function;
    if (eql(ntype, "call") or eql(ntype, "call_expression") or eql(ntype, "latom")) return .Call;
    if (eql(ntype, "ret") or eql(ntype, "return_statement") or eql(ntype, "return_expression")) return .Return;
    if (eql(ntype, "binary") or eql(ntype, "binary_expression")) return .BinOp;
    if (eql(ntype, "if_stmt") or eql(ntype, "if_expr") or eql(ntype, "if_statement") or eql(ntype, "if_expression")) return .If;
    if (eql(ntype, "while_stmt") or eql(ntype, "for_stmt") or eql(ntype, "loop_stmt") or eql(ntype, "while_statement") or eql(ntype, "for_statement")) return .Loop;
    if (eql(ntype, "var_decl") or eql(ntype, "declaration") or eql(ntype, "variable_declaration")) return .VarDecl;
    if (eql(ntype, "assign") or eql(ntype, "assignment_expression") or eql(ntype, "assignment_statement")) return .Assign;
    if (eql(ntype, "struct_decl") or eql(ntype, "struct_specifier") or eql(ntype, "container_declaration")) return .StructDecl;
    if (eql(ntype, "enum_decl") or eql(ntype, "enum_specifier")) return .EnumDecl;
    if (eql(ntype, "impl_block")) return .ImplBlock;
    if (eql(ntype, "fact_decl")) return .FactDecl;
    if (eql(ntype, "rule_decl")) return .RuleDecl;
    if (eql(ntype, "query_expr")) return .QueryExpr;
    if (eql(ntype, "actor_decl")) return .ActorDecl;
    if (eql(ntype, "spawn") or eql(ntype, "spawn_expr")) return .SpawnExpr;
    if (eql(ntype, "send") or eql(ntype, "send_expr")) return .SendExpr;
    if (eql(ntype, "match_stmt") or eql(ntype, "match_expr") or eql(ntype, "switch_statement")) return .MatchExpr;
    if (eql(ntype, "lambda") or eql(ntype, "arrow_function")) return .Lambda;
    if (eql(ntype, "quote_expr") or eql(ntype, "quote")) return .Quote;
    if (eql(ntype, "unquote_expr") or eql(ntype, "unquote")) return .Unquote;
    if (eql(ntype, "pipe") or eql(ntype, "pipe_expr")) return .PipeExpr;
    if (eql(ntype, "range") or eql(ntype, "range_expr")) return .RangeExpr;
    if (eql(ntype, "effect_decl")) return .EffectDecl;
    if (eql(ntype, "handle_expr")) return .HandleExpr;
    if (eql(ntype, "member") or eql(ntype, "field_expression") or eql(ntype, "field_access")) return .FieldAccess;
    if (eql(ntype, "index") or eql(ntype, "subscript_expression")) return .IndexExpr;
    if (eql(ntype, "block") or eql(ntype, "compound_statement") or eql(ntype, "params") or eql(ntype, "recv_block")) return .Block;
    if (eql(ntype, "int") or eql(ntype, "number_literal") or eql(ntype, "integer_literal")) return .LiteralInt;
    if (eql(ntype, "float") or eql(ntype, "float_literal")) return .LiteralFloat;
    if (eql(ntype, "str") or eql(ntype, "string_literal") or eql(ntype, "string")) return .LiteralString;
    if (eql(ntype, "bool_lit") or eql(ntype, "true") or eql(ntype, "false")) return .LiteralBool;
    if (eql(ntype, "identifier") or eql(ntype, "lvar")) return .Identifier;
    if (eql(ntype, "type_name") or eql(ntype, "prim_type")) return .TypeName;
    if (eql(ntype, "sig_decl")) return .SigDecl;
    if (eql(ntype, "eq_decl")) return .EqDecl;
    if (eql(ntype, "forall_type")) return .TypeName;
    if (eql(ntype, "exists_type")) return .TypeName;
    if (eql(ntype, "math_expr")) return .Call;
    return .Unknown;
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
