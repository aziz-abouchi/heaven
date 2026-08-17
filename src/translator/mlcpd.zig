// src/core/mlcpd.zig — Intégration MLCPD (MultiLang Code Parser Dataset)
// Référence: https://arxiv.org/html/2510.16357v1
//
// MLCPD fournit un universal AST schema en 4 couches:
//   Layer 1: Metadata (lines, nodes, errors, source_hash)
//   Layer 2: Flat Node Array (nœuds linéarisés avec parent/enfant)
//   Layer 3: Node Categorization (declarations, statements, expressions)
//   Layer 4: Cross-Language Map (rôles sémantiques universels)

const std = @import("std");
const Allocator = std.mem.Allocator;
const expr_mod = @import("expr");
const Store = expr_mod.Store;
const Id = expr_mod.Id;

pub const MlcpdError = error{
    InvalidSchema,
    MissingField,
    UnsupportedNodeType,
    OutOfMemory,
    ParseError,
};

// ═══════════════════════════════════════════════════════════
// Layer 1: Metadata Block
// ═══════════════════════════════════════════════════════════
pub const FileMetadata = struct {
    lines: u32 = 0,
    avg_line_length: f32 = 0,
    nodes: u32 = 0,
    errors: u32 = 0,
    source_hash: [64]u8 = undefined, // SHA-256 hex
    language: Language = .unknown,

    pub const Language = enum(u8) {
        unknown = 0,
        c = 1,
        cpp = 2,
        csharp = 3,
        go = 4,
        java = 5,
        javascript = 6,
        python = 7,
        ruby = 8,
        scala = 9,
        typescript = 10,
    };
};

// ═══════════════════════════════════════════════════════════
// Layer 3: Node Categorization (taxonomie universelle)
// ═══════════════════════════════════════════════════════════
pub const NodeCategory = enum(u8) {
    unknown = 0,
    declaration = 1, // function, class, variable, type def
    statement = 2, // if, while, return, assignment
    expression = 3, // binary, unary, call, literal
    comment = 4,
    directive = 5, // import, include, pragma
};

// ═══════════════════════════════════════════════════════════
// Layer 4: Cross-Language Semantic Role
// ═══════════════════════════════════════════════════════════
pub const SemanticRole = enum(u16) {
    unknown = 0,
    // Declarations
    function_decl = 100,
    class_decl = 101,
    variable_decl = 102,
    parameter_decl = 103,
    type_decl = 104,
    field_decl = 105,
    // Statements
    if_stmt = 200,
    while_stmt = 201,
    for_stmt = 202,
    return_stmt = 203,
    assign_stmt = 204,
    block_stmt = 205,
    // Expressions
    binary_expr = 300,
    unary_expr = 301,
    call_expr = 302,
    member_expr = 303,
    literal_expr = 304,
    identifier_expr = 305,
    index_expr = 306,
    // Other
    comment_node = 400,
    import_directive = 500,
};

// ═══════════════════════════════════════════════════════════
// Layer 2: Flat Node Array (représentation linéarisée)
// ═══════════════════════════════════════════════════════════
pub const MlcpdNode = struct {
    id: u32, // Index dans le flat array
    node_type: []const u8, // Type syntaxique original (ex: "function_definition")
    category: NodeCategory,
    role: SemanticRole,
    code_snippet: []const u8, // Fragment de code source
    parent_id: i32, // -1 si racine
    children_start: u32, // Index premier enfant dans flat array
    children_count: u16,
    start_byte: u32,
    end_byte: u32,
    start_row: u32,
    start_col: u16,
    end_row: u32,
    end_col: u16,
};

// ═══════════════════════════════════════════════════════════
// Parsed File: contient toutes les couches MLCPD
// ═══════════════════════════════════════════════════════════
pub const ParsedFile = struct {
    allocator: Allocator,
    metadata: FileMetadata,
    nodes: std.ArrayListUnmanaged(MlcpdNode),
    /// Mapping MLCPD node id → Heaven Expr Id (après conversion)
    node_to_expr: std.AutoHashMapUnmanaged(u32, Id),

    pub fn init(allocator: Allocator) ParsedFile {
        return .{
            .allocator = allocator,
            .metadata = .{},
            .nodes = .{},
            .node_to_expr = .{},
        };
    }

    pub fn deinit(self: *ParsedFile) void {
        // Libère uniquement les tableaux et la hashmap.
        // Les chaînes ne sont pas libérées pour l'instant car elles peuvent
        // pointer vers des données statiques ou être partagées.
        self.nodes.deinit(self.allocator);
        self.node_to_expr.deinit(self.allocator);
    }

    pub fn nodeCount(self: *const ParsedFile) usize {
        return self.nodes.items.len;
    }

    pub fn getNode(self: *const ParsedFile, id: u32) ?*const MlcpdNode {
        if (id >= self.nodes.items.len) return null;
        return &self.nodes.items[id];
    }

    /// Convertir l'AST MLCPD en Expr IR Heaven
    pub fn toExprIr(self: *ParsedFile, store: *Store) MlcpdError!Id {
        if (self.nodes.items.len == 0) return store.unitLit();

        // Construire bottom-up: les feuilles d'abord, puis les parents
        // Les nœuds sans enfants sont convertis en premier
        var converted: usize = 0;
        var max_passes: usize = self.nodes.items.len + 1;

        while (converted < self.nodes.items.len and max_passes > 0) : (max_passes -= 1) {
            for (self.nodes.items, 0..) |*node, idx| {
                const nid = @as(u32, @intCast(idx));
                if (self.node_to_expr.contains(nid)) continue;

                // Vérifier que tous les enfants sont déjà convertis
                var all_children_ready = true;
                var child_ids: std.ArrayListUnmanaged(Id) = .{};
                defer child_ids.deinit(self.allocator);

                for (0..node.children_count) |ci| {
                    const child_idx = node.children_start + @as(u32, @intCast(ci));
                    if (self.node_to_expr.get(child_idx)) |cid| {
                        child_ids.append(self.allocator, cid) catch return error.OutOfMemory;
                    } else {
                        all_children_ready = false;
                        break;
                    }
                }

                if (!all_children_ready) continue;

                // Convertir ce nœud selon son rôle sémantique
                const expr_id = try self.convertNode(store, node, child_ids.items);

                try self.node_to_expr.put(self.allocator, nid, expr_id);
                converted += 1;
            }
        }

        // Retourner l'expression de la racine (node 0)
        const root_expr = self.node_to_expr.get(0) orelse store.unitLit();

        return root_expr;
    }

    fn convertNode(self: *ParsedFile, store: *Store, node: *const MlcpdNode, children: []const Id) MlcpdError!Id {
        _ = self;
        switch (node.role) {
            .literal_expr => {
                // Essayer de parser comme entier
                if (std.fmt.parseInt(i64, node.code_snippet, 10)) |v| {
                    return store.int(v);
                } else |_| {}
                // Sinon symbole
                return store.sym(node.code_snippet) catch return error.OutOfMemory;
            },
            .identifier_expr => {
                const sym_id = store.sym(node.code_snippet) catch return error.OutOfMemory;
                return sym_id;
            },
            .binary_expr => {
                if (children.len != 2) return store.sym(node.code_snippet) catch return error.OutOfMemory;
                // Le type syntaxique contient l'opérateur
                const op = extractBinOp(node.node_type);
                const op_sym = store.sym(op) catch return error.OutOfMemory;
                const app = store.apply(op_sym, children) catch return error.OutOfMemory;
                return app;
            },
            .call_expr => {
                if (children.len == 0) return store.sym(node.code_snippet) catch return error.OutOfMemory;
                const func_name = if (node.code_snippet.len > 0) node.code_snippet else "call";
                const sym = store.sym(func_name) catch return error.OutOfMemory;
                const all = try std.mem.concat(store.allocator, Id, &.{ &[_]Id{sym}, children });
                defer store.allocator.free(all);
                return store.apply(sym, children) catch return error.OutOfMemory;
            },
            .function_decl => {
                // Créer un lambda: λ(params). body
                // children[0] = nom de la fonction (identifier)
                // children[1] = paramètres (peut être un tuple ou liste)
                // children[2] = corps de la fonction

                if (children.len < 3) {
                    // Pas assez d'enfants, fallback
                    return store.unitLit();
                }

                const func_name_id = children[0];
                const params_id = children[1];
                const body_id = children[2];

                // Pour l'instant, créer un lambda simple avec un paramètre "x"
                // TODO: extraire les vrais noms de paramètres depuis params_id
                // Extraire le VRAI nom du paramètre depuis params_id
                const param_node = store.get(params_id);
                const param_name: []const u8 = if (param_node.tag == .sym)
                    store.interner.resolve(param_node.payload)
                else
                    "x"; // Fallback
                const lambda = store.lambdaNative(&.{param_name}, body_id) catch return error.OutOfMemory;

                _ = func_name_id;
                return lambda;
            },
            .parameter_decl => {
                // Retourner le nom du paramètre comme symbole
                // Chercher le premier enfant qui est un symbole (le nom)
                for (children) |child_id| {
                    const child_node = store.get(child_id);
                    if (child_node.tag == .sym) {
                        return child_id;
                    }
                }
                // Fallback
                if (children.len > 0) {
                    return children[0];
                }
                return store.sym("param") catch return error.OutOfMemory;
            },
            .return_stmt => {
                if (children.len == 1) return children[0];
                return store.unitLit();
            },
            .block_stmt => {
                if (children.len == 0) return store.unitLit();
                if (children.len == 1) return children[0];
                // Séquence: imbriquer les expressions
                var result = children[0];
                for (1..children.len) |i| {
                    const seq_sym = store.sym("__seq") catch return error.OutOfMemory;
                    result = store.apply(seq_sym, &[_]Id{ result, children[i] }) catch return error.OutOfMemory;
                }
                return result;
            },
            .if_stmt => {
                // if cond then branch1 else branch2
                if (children.len >= 3) {
                    const cond = children[0];
                    const then_branch = children[1];
                    const else_branch = children[2];

                    const if_sym = store.sym("if") catch return error.OutOfMemory;
                    const args = &[_]Id{ cond, then_branch, else_branch };
                    return store.apply(if_sym, args) catch return error.OutOfMemory;
                }
                return store.unitLit();
            },
            else => {
                // Fallback: créer un nœud symbolique avec le rôle
                const tag = @tagName(node.role);
                if (children.len == 0) return store.sym(tag) catch return error.OutOfMemory;
                const sym = store.sym(tag) catch return error.OutOfMemory;
                return store.apply(sym, children) catch return error.OutOfMemory;
            },
        }
    }

    /// Appliquer toutes les normalisations MLCPD cross-langage
    /// Modifie les code_snippet en place pour uniformisation
    pub fn normalizeParsedFile(self: *ParsedFile) void {
        for (self.nodes.items) |*node| {
            // Normaliser les booléens
            if (node.role == .literal_expr) {
                const norm = normalizeBoolLiteral(node.code_snippet);
                if (!std.mem.eql(u8, norm, node.code_snippet)) {
                    if (self.allocator.dupe(u8, norm)) |duped| {
                        // Libérer l'ancienne chaîne dupliquée dans parseNode
                        if (node.code_snippet.len > 0) {
                            self.allocator.free(node.code_snippet);
                        }
                        node.code_snippet = duped;
                    } else |_| {}
                }
            }
            // Normaliser les identifiants (snake_case)
            if (node.role == .identifier_expr or node.role == .function_decl) {
                if (normalizeSymbolName(self.allocator, node.code_snippet)) |normed| {
                    if (!std.mem.eql(u8, normed, node.code_snippet)) {
                        // Libérer l'ancienne chaîne dupliquée dans parseNode
                        if (node.code_snippet.len > 0) {
                            self.allocator.free(node.code_snippet);
                        }
                        node.code_snippet = normed;
                    } else {
                        self.allocator.free(normed);
                    }
                } else |_| {}
            }
        }
    }
};

/// Extraire l'opérateur binaire depuis le type syntaxique Tree-sitter
fn extractBinOp(node_type: []const u8) []const u8 {
    const BinOpEntry = struct { prefix: []const u8, op: []const u8 };
    const mappings: []const BinOpEntry = &.{
        .{ .prefix = "add", .op = "+" },
        .{ .prefix = "sub", .op = "-" },
        .{ .prefix = "mul", .op = "*" },
        .{ .prefix = "div", .op = "/" },
        .{ .prefix = "mod", .op = "%" },
        .{ .prefix = "eq", .op = "=" },
        .{ .prefix = "neq", .op = "!=" },
        .{ .prefix = "lt", .op = "<" },
        .{ .prefix = "gt", .op = ">" },
        .{ .prefix = "lte", .op = "<=" },
        .{ .prefix = "gte", .op = ">=" },
        .{ .prefix = "and", .op = "&&" },
        .{ .prefix = "or", .op = "||" },
    };
    for (mappings) |m| {
        if (std.mem.indexOf(u8, node_type, m.prefix) != null) return m.op;
    }
    return "+"; // fallback
}

// ═══════════════════════════════════════════════════════════
// JSON Parser pour le format MLCPD
// ═══════════════════════════════════════════════════════════
pub fn parseMlcpdJson(allocator: Allocator, json_data: []const u8) MlcpdError!ParsedFile {
    var file = ParsedFile.init(allocator);
    errdefer file.deinit();

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_data, .{}) catch return error.ParseError;
    defer parsed.deinit();

    const root = parsed.value;

    // Layer 1: Metadata
    if (root.object.get("metadata")) |meta| {
        if (meta.object.get("lines")) |v| file.metadata.lines = @intCast(v.integer);
        if (meta.object.get("nodes")) |v| file.metadata.nodes = @intCast(v.integer);
        if (meta.object.get("errors")) |v| file.metadata.errors = @intCast(v.integer);
        if (meta.object.get("language")) |v| {
            const lang_str = v.string;
            file.metadata.language = parseLanguage(lang_str);
        }
    }

    // Layer 2: Flat Node Array
    if (root.object.get("nodes")) |nodes_arr| {
        if (nodes_arr != .array) return error.InvalidSchema;
        for (nodes_arr.array.items) |node_val| {
            const node = try parseNode(file.allocator, node_val);
            try file.nodes.append(allocator, node);
        }
    }

    return file;
}

fn parseLanguage(s: []const u8) FileMetadata.Language {
    const LangEntry = struct { name: []const u8, tag: FileMetadata.Language };
    const langs: []const LangEntry = &.{
        .{ .name = "c", .tag = .c },
        .{ .name = "cpp", .tag = .cpp },
        .{ .name = "csharp", .tag = .csharp },
        .{ .name = "go", .tag = .go },
        .{ .name = "java", .tag = .java },
        .{ .name = "javascript", .tag = .javascript },
        .{ .name = "python", .tag = .python },
        .{ .name = "ruby", .tag = .ruby },
        .{ .name = "scala", .tag = .scala },
        .{ .name = "typescript", .tag = .typescript },
    };
    for (langs) |l| {
        if (std.ascii.eqlIgnoreCase(s, l.name)) return l.tag;
    }
    return .unknown;
}

fn parseNode(allocator: Allocator, val: std.json.Value) MlcpdError!MlcpdNode {
    if (val != .object) return error.InvalidSchema;
    const obj = val.object;

    var node = MlcpdNode{
        .id = 0,
        .node_type = "",
        .category = .unknown,
        .role = .unknown,
        .code_snippet = "",
        .parent_id = -1,
        .children_start = 0,
        .children_count = 0,
        .start_byte = 0,
        .end_byte = 0,
        .start_row = 0,
        .start_col = 0,
        .end_row = 0,
        .end_col = 0,
    };

    if (obj.get("id")) |v| node.id = @intCast(v.integer);
    if (obj.get("type")) |v| {
        node.node_type = allocator.dupe(u8, v.string) catch return error.OutOfMemory;
    }
    if (obj.get("snippet")) |v| {
        node.code_snippet = allocator.dupe(u8, v.string) catch return error.OutOfMemory;
    }
    if (obj.get("parent")) |v| node.parent_id = @intCast(v.integer);
    if (obj.get("children_start")) |v| node.children_start = @intCast(v.integer);
    if (obj.get("children_count")) |v| node.children_count = @intCast(v.integer);
    if (obj.get("start_byte")) |v| node.start_byte = @intCast(v.integer);
    if (obj.get("end_byte")) |v| node.end_byte = @intCast(v.integer);
    if (obj.get("start_row")) |v| node.start_row = @intCast(v.integer);
    if (obj.get("end_row")) |v| node.end_row = @intCast(v.integer);

    if (obj.get("category")) |v| {
        node.category = parseCategory(v.string);
    }
    // Essayer d'abord "role", puis "semantic_role" pour compatibilité
    if (obj.get("role")) |v| {
        node.role = parseRole(v.string);
    } else if (obj.get("semantic_role")) |v| {
        node.role = parseRole(v.string);
    }

    return node;
}

fn parseCategory(s: []const u8) NodeCategory {
    if (std.mem.eql(u8, s, "declaration")) return .declaration;
    if (std.mem.eql(u8, s, "statement")) return .statement;
    if (std.mem.eql(u8, s, "expression")) return .expression;
    if (std.mem.eql(u8, s, "comment")) return .comment;
    if (std.mem.eql(u8, s, "directive")) return .directive;
    return .unknown;
}

fn parseRole(s: []const u8) SemanticRole {
    const RoleEntry = struct { name: []const u8, tag: SemanticRole };
    const roles: []const RoleEntry = &.{
        .{ .name = "function_decl", .tag = .function_decl },
        .{ .name = "class_decl", .tag = .class_decl },
        .{ .name = "variable_decl", .tag = .variable_decl },
        .{ .name = "parameter_decl", .tag = .parameter_decl },
        .{ .name = "if_stmt", .tag = .if_stmt },
        .{ .name = "while_stmt", .tag = .while_stmt },
        .{ .name = "for_stmt", .tag = .for_stmt },
        .{ .name = "return_stmt", .tag = .return_stmt },
        .{ .name = "assign_stmt", .tag = .assign_stmt },
        .{ .name = "block_stmt", .tag = .block_stmt },
        .{ .name = "binary_expr", .tag = .binary_expr },
        .{ .name = "unary_expr", .tag = .unary_expr },
        .{ .name = "call_expr", .tag = .call_expr },
        .{ .name = "member_expr", .tag = .member_expr },
        .{ .name = "literal_expr", .tag = .literal_expr },
        .{ .name = "identifier_expr", .tag = .identifier_expr },
        .{ .name = "index_expr", .tag = .index_expr },
        .{ .name = "import_directive", .tag = .import_directive },
    };
    for (roles) |r| {
        if (std.mem.eql(u8, s, r.name)) return r.tag;
    }
    return .unknown;
}

// ═══════════════════════════════════════════════════════════
// MLCPD Cross-Language Normalization Rules
// ═══════════════════════════════════════════════════════════
// Appliquées avant comparaison EGraph pour unifier les conventions

/// Normaliser un nom de fonction/symbole cross-langage
/// isAdult → is_adult, camelCase → snake_case
pub fn normalizeSymbolName(allocator: Allocator, name: []const u8) ![]const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    for (name, 0..) |c, i| {
        if (std.ascii.isUpper(c)) {
            if (i > 0) try buf.append(allocator, '_');
            try buf.append(allocator, std.ascii.toLower(c));
        } else {
            try buf.append(allocator, c);
        }
    }
    return buf.toOwnedSlice(allocator);
}

/// Normaliser les littéraux booléens cross-langage
/// True/true/TRUE → true, False/false/FALSE → false
pub fn normalizeBoolLiteral(s: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(s, "true")) return "true";
    if (std.ascii.eqlIgnoreCase(s, "false")) return "false";
    return s;
}
