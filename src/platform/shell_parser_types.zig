const std = @import("std");

pub const ParseError = error{
    ParserInitFailed,
    LanguageLoadFailed,
    ParseFailed,
    OutOfMemory,
    NotSupported,
};

/// Langages supportés par le système de parsing
pub const Language = enum {
    heaven,
    pie,
    c,
    zig,

    pub fn fromString(s: []const u8) ?Language {
        const map = .{
            .{ "heaven", Language.heaven },
            .{ "pie", Language.pie },
            .{ "c", Language.c },
            .{ "zig", Language.zig },
        };
        inline for (map) |entry| {
            if (std.mem.eql(u8, s, entry[0])) return entry[1];
        }
        return null;
    }

    pub fn fromExtension(ext: []const u8) ?Language {
        const map = .{
            .{ ".hvn", Language.heaven },
            .{ ".pie", Language.pie },
            .{ ".c", Language.c },
            .{ ".zig", Language.zig },
        };
        inline for (map) |entry| {
            if (std.mem.eql(u8, ext, entry[0])) return entry[1];
        }
        return null;
    }

    pub fn toString(self: Language) []const u8 {
        return switch (self) {
            .heaven => "heaven",
            .pie => "pie",
            .c => "c",
            .zig => "zig",
        };
    }
};

/// Types de nœuds produits par le parser tree-sitter
pub const NodeKind = enum {
    unknown,
    err_node,

    // Littéraux
    integer_literal,
    float_literal,
    string_literal,
    boolean_literal,
    hole_lit,

    // Identifiants et opérateurs
    identifier,
    operator,

    // Déclarations
    bind_decl,
    fn_decl,
    type_decl,
    prove_decl,
    sig_decl,
    eq_decl,
    import_decl,
    data_decl,
    theorem_decl,

    // Déclarations logiques (Prolog/miniKanren)
    fact_decl,
    rule_decl,
    query_decl,

    // Expressions
    apply_expr,
    binary_expr,
    unary_expr,
    lambda_expr,
    if_expr,
    match_expr,
    paren_expr,
    sum_expr,
    prod_expr,
    let_expr,
    relation_expr,

    // Patterns
    pattern,
    ctor_pat,
    list_pat,
    tuple_pat,

    // Types
    type_expr,
    arrow_type,

    // Structure
    program,
    block,
    param_list,
    arg_list,
    match_arm,
    comment,

    // Autres nœuds Prolog possibles
    clause_decl, // Clause générique (fait ou règle)
    conjunction_expr, // Conjonction dans le corps d'une règle (a, b, c)
    disjunction_expr, // Disjonction (a ; b)
    negation_expr, // Négation (\+ goal)
    cut_expr, // Cut (!)
    var_expr, // Variable logique (?X ou _X)
    atom_expr, // Atome Prolog
};

/// Représentation d'un nœud de l'arbre de syntaxe abstraite (CST)
pub const Matrix = struct {
    kind: NodeKind,
    text: ?[]const u8,
    children: []const Matrix, // ← Changement ici : []const au lieu de []
    row: u32 = 0,
    col: u32 = 0,

    /// Retourne le i-ème enfant, ou null si l'index est hors limites
    pub fn child(self: *const Matrix, i: usize) ?*const Matrix {
        if (i >= self.children.len) return null;
        return &self.children[i];
    }

    /// Retourne le nombre d'enfants
    pub fn childCount(self: *const Matrix) usize {
        return self.children.len;
    }

    /// Cherche le premier enfant avec le NodeKind spécifié
    pub fn find(self: *const Matrix, target_kind: NodeKind) ?*const Matrix {
        for (self.children) |*c| {
            if (c.kind == target_kind) return c;
        }
        return null;
    }

    /// Cherche tous les enfants avec le NodeKind spécifié
    pub fn findAll(self: *const Matrix, target_kind: NodeKind, allocator: std.mem.Allocator) ![]*const Matrix {
        var result = std.ArrayList(*const Matrix).init(allocator);
        for (self.children) |*c| {
            if (c.kind == target_kind) {
                try result.append(c);
            }
        }
        return result.toOwnedSlice();
    }

    /// Vérifie si le nœud a un enfant avec le NodeKind spécifié
    pub fn hasChild(self: *const Matrix, target_kind: NodeKind) bool {
        return self.find(target_kind) != null;
    }
};

/// Fabrique générique du ShellParser tree-sitter.
/// `Ts`          : module tree-sitter (cImport de api.h)
/// `getLanguage` : fonction retournant le TSLanguage de la grammaire
pub fn TreeSitterParser(comptime Ts: type, comptime getLanguage: anytype) type {
    return struct {
        const Self = @This();
        parser: *Ts.TSParser,
        alloc: std.mem.Allocator,
        arena: std.heap.ArenaAllocator,

        pub fn init(alloc: std.mem.Allocator) ParseError!Self {
            const parser = Ts.ts_parser_new() orelse return ParseError.ParserInitFailed;
            return .{
                .parser = parser,
                .alloc = alloc,
                .arena = std.heap.ArenaAllocator.init(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            Ts.ts_parser_delete(self.parser);
            self.arena.deinit();
        }

        pub fn parse(self: *Self, source: []const u8) ParseError!Matrix {
            if (!Ts.ts_parser_set_language(self.parser, getLanguage())) {
                return ParseError.LanguageLoadFailed;
            }
            const tree = Ts.ts_parser_parse_string(
                self.parser,
                null,
                source.ptr,
                @intCast(source.len),
            ) orelse return ParseError.ParseFailed;
            defer Ts.ts_tree_delete(tree);

            const root = Ts.ts_tree_root_node(tree);
            return self.traverse(root, source) catch ParseError.OutOfMemory;
        }

        pub fn reset(self: *Self) void {
            _ = self.arena.reset(.retain_capacity);
        }

        fn traverse(self: *Self, node: Ts.TSNode, source: []const u8) !Matrix {
            const alloc = self.arena.allocator();
            const kind = mapNodeKind(Ts.ts_node_type(node));

            const sb: usize = @intCast(Ts.ts_node_start_byte(node));
            const eb: usize = @intCast(Ts.ts_node_end_byte(node));
            const text: ?[]const u8 = if (sb <= eb and eb <= source.len) source[sb..eb] else null;

            const cc: usize = @intCast(Ts.ts_node_named_child_count(node));
            const children = try alloc.alloc(Matrix, cc);
            var i: usize = 0;
            while (i < cc) : (i += 1) {
                const child = Ts.ts_node_named_child(node, @intCast(i));
                children[i] = try self.traverse(child, source);
            }

            const sp = Ts.ts_node_start_point(node);
            return .{
                .kind = kind,
                .text = text,
                .children = children,
                .row = @intCast(sp.row),
                .col = @intCast(sp.column),
            };
        }

        fn mapNodeKind(node_type: ?[*:0]const u8) NodeKind {
            if (node_type == null) return .unknown;
            const t = std.mem.span(node_type.?);
            const K = NodeKind;
            const table = .{
                // Heaven
                .{ "source_file", K.program },
                .{ "eq_decl", K.eq_decl },
                .{ "bind_decl", K.bind_decl },
                .{ "fn_decl", K.fn_decl },
                .{ "type_decl", K.type_decl },
                .{ "prove_decl", K.prove_decl },
                .{ "sig_decl", K.sig_decl },
                .{ "import_decl", K.import_decl },
                .{ "data_decl", K.data_decl },
                .{ "theorem_decl", K.theorem_decl },
                .{ "apply_expr", K.apply_expr },
                .{ "binary_expr", K.binary_expr },
                .{ "unary_expr", K.unary_expr },
                .{ "lambda_expr", K.lambda_expr },
                .{ "if_expr", K.if_expr },
                .{ "match_expr", K.match_expr },
                .{ "paren_expr", K.paren_expr },
                .{ "let_expr", K.let_expr },

                // C
                .{ "function_definition", K.fn_decl },
                .{ "function_declarator", K.fn_decl },
                .{ "primitive_type", K.type_expr },
                .{ "parameter_list", K.param_list },
                .{ "parameter_declaration", K.param_list },
                .{ "compound_statement", K.block },
                .{ "return_statement", K.apply_expr },
                .{ "binary_expression", K.binary_expr },
                .{ "call_expression", K.apply_expr },
                .{ "argument_list", K.arg_list },
                .{ "translation_unit", K.program },

                // Zig
                .{ "FnDef", K.fn_decl },
                .{ "FnProto", K.fn_decl },
                .{ "ParamDeclList", K.param_list },
                .{ "ParamDecl", K.param_list },
                .{ "Block", K.block },
                .{ "BlockExpr", K.block },
                .{ "ReturnExpr", K.apply_expr },
                .{ "InfixOp", K.binary_expr },
                .{ "SuffixOp", K.apply_expr },
                .{ "PrefixOp", K.unary_expr },
                .{ "Identifier", K.identifier },
                .{ "ContainerDecl", K.program },
                .{ "ErrorUnionExpr", K.type_expr },
                .{ "PtrType", K.type_expr },
                .{ "ArrayType", K.type_expr },
                .{ "SuffixExpr", K.apply_expr },
                .{ "PrimaryTypeExpr", K.type_expr },
                .{ "AsmExpr", K.apply_expr },
                .{ "BuiltinCall", K.apply_expr },
                .{ "Call", K.apply_expr },
                .{ "FnCallArguments", K.arg_list },
                .{ "ParamDecl", K.param_list },
                .{ "Payload", K.param_list },
                .{ "PtrList", K.type_expr },
                .{ "PtrIndexPayload", K.apply_expr },
                .{ "PtrTypeFieldInit", K.apply_expr },
                .{ "SwitchProng", K.match_arm },
                .{ "SwitchCase", K.match_arm },
                .{ "SwitchExpr", K.match_expr },
                .{ "TestDecl", K.theorem_decl },
                .{ "VarDecl", K.bind_decl },
                .{ "WhileExpr", K.apply_expr },
                .{ "ForExpr", K.apply_expr },
                .{ "IfExpr", K.if_expr },
                .{ "AssignExpr", K.apply_expr },
                .{ "BoolAndExpr", K.binary_expr },
                .{ "BoolOrExpr", K.binary_expr },
                .{ "CompareExpr", K.binary_expr },
                .{ "BoolNotExpr", K.unary_expr },
                .{ "AdditionExpr", K.binary_expr },
                .{ "SubtractionExpr", K.binary_expr },
                .{ "MultiplyExpr", K.binary_expr },
                .{ "DivideExpr", K.binary_expr },
                .{ "ModuloExpr", K.binary_expr },
                .{ "BitShiftLeftExpr", K.binary_expr },
                .{ "BitShiftRightExpr", K.binary_expr },
                .{ "BitAndExpr", K.binary_expr },
                .{ "BitXorExpr", K.binary_expr },
                .{ "BitOrExpr", K.binary_expr },
                .{ "ErrorUnionExpr", K.type_expr },
                .{ "UnwrapOptionalExpr", K.apply_expr },
                .{ "FieldAccess", K.apply_expr },
                .{ "FieldInit", K.apply_expr },
                .{ "StructLiteral", K.apply_expr },
                .{ "ArrayLiteral", K.apply_expr },
                .{ "SliceExpr", K.apply_expr },
                .{ "ComptimeExpr", K.apply_expr },

                // Common
                .{ "identifier", K.identifier },
                .{ "number_literal", K.integer_literal },
                .{ "integer_literal", K.integer_literal },
                .{ "float_literal", K.float_literal },
                .{ "string_literal", K.string_literal },
                .{ "true", K.boolean_literal },
                .{ "false", K.boolean_literal },
                .{ "operator", K.operator },
                .{ "+", K.operator },
                .{ "-", K.operator },
                .{ "*", K.operator },
                .{ "/", K.operator },
                .{ "ERROR", K.err_node },
            };
            inline for (table) |entry| {
                if (std.mem.eql(u8, t, entry[0])) return entry[1];
            }
            return .unknown;
        }
    };
}
