//! Traducteur universel multi-langage via MLCPD
//! Architecture : Code source → tree-sitter → Matrix → MLCPD IR → Heaven AST (6 primitives)
const std = @import("std");
const expr = @import("expr");
const mlcpd_mod = @import("mlcpd");
const platform = @import("platform");
const Allocator = std.mem.Allocator;

const Store = expr.Store;
const Id = expr.Id;
const Span = expr.Span;
const Matrix = platform.shell_parser_types.Matrix;
const NodeKind = platform.shell_parser_types.NodeKind;

pub const TranslatorError = error{
    InvalidStructure,
    UnsupportedNodeType,
    OutOfMemory,
    ParseError,
};

// ═══════════════════════════════════════════════════════════
// MlcpdConverter : Matrix → ParsedFile (IR MLCPD)
// ═══════════════════════════════════════════════════════════
pub const MlcpdConverter = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) MlcpdConverter {
        return .{ .allocator = allocator };
    }

    pub fn convert(self: *MlcpdConverter, matrix: *const Matrix, lang: mlcpd_mod.FileMetadata.Language) !mlcpd_mod.ParsedFile {
        var parsed = mlcpd_mod.ParsedFile.init(self.allocator);
        parsed.metadata.language = lang;
        parsed.metadata.nodes = 0;

        _ = try self.walkMatrix(matrix, -1, &parsed);

        return parsed;
    }

    fn walkMatrix(self: *MlcpdConverter, matrix: *const Matrix, parent_id: i32, parsed: *mlcpd_mod.ParsedFile) !u32 {
        const node_id: u32 = @intCast(parsed.nodes.items.len);
        parsed.metadata.nodes += 1;

        const node_type_str = @tagName(matrix.kind);

        // DEBUG : afficher chaque nœud rencontré
        // platform.debug.print("[MlcpdConverter] node_id={d} kind={s} text=\"{s}\"\n", .{ node_id, node_type_str, matrix.text orelse "<null>" });

        const category = self.mapCategory(matrix.kind, node_type_str);
        const role = self.mapSemanticRole(matrix.kind, node_type_str, matrix.text);

        // platform.debug.print("[MlcpdConverter]   → category={s} role={s}\n", .{ @tagName(category), @tagName(role) });

        const node = mlcpd_mod.MlcpdNode{
            .id = node_id,
            .node_type = node_type_str,
            .category = category,
            .role = role,
            .code_snippet = matrix.text orelse "",
            .parent_id = parent_id,
            .children_start = 0,
            .children_count = 0,
            .start_byte = 0,
            .end_byte = 0,
            .start_row = 0,
            .start_col = 0,
            .end_row = 0,
            .end_col = 0,
        };

        try parsed.nodes.append(self.allocator, node);

        const children_start: u32 = @intCast(parsed.nodes.items.len);
        for (matrix.children) |child| {
            _ = try self.walkMatrix(&child, @as(i32, @intCast(node_id)), parsed);
        }
        const children_count: u16 = @intCast(parsed.nodes.items.len - children_start);

        parsed.nodes.items[node_id].children_start = children_start;
        parsed.nodes.items[node_id].children_count = children_count;

        return node_id;
    }

    fn mapCategory(self: *MlcpdConverter, kind: NodeKind, node_type: []const u8) mlcpd_mod.NodeCategory {
        _ = self;
        _ = kind;
        // Mapper par le nom tree-sitter (plus fiable que NodeKind)
        if (std.mem.eql(u8, node_type, "function_definition") or
            std.mem.eql(u8, node_type, "function_declaration")) return .declaration;
        if (std.mem.eql(u8, node_type, "declaration") or
            std.mem.eql(u8, node_type, "variable_declaration")) return .declaration;
        if (std.mem.eql(u8, node_type, "binary_expression") or
            std.mem.eql(u8, node_type, "call_expression")) return .expression;
        if (std.mem.eql(u8, node_type, "identifier")) return .expression;
        if (std.mem.eql(u8, node_type, "number_literal") or
            std.mem.eql(u8, node_type, "string_literal") or
            std.mem.eql(u8, node_type, "true") or
            std.mem.eql(u8, node_type, "false")) return .expression;
        if (std.mem.eql(u8, node_type, "compound_statement") or
            std.mem.eql(u8, node_type, "block")) return .statement;
        if (std.mem.eql(u8, node_type, "return_statement")) return .statement;
        return .unknown;
    }

    fn mapSemanticRole(self: *MlcpdConverter, kind: NodeKind, node_type: []const u8, text: ?[]const u8) mlcpd_mod.SemanticRole {
        _ = self;
        _ = kind;
        _ = text;
        if (std.mem.eql(u8, node_type, "function_definition") or
            std.mem.eql(u8, node_type, "function_declaration")) return .function_decl;
        if (std.mem.eql(u8, node_type, "declaration") or
            std.mem.eql(u8, node_type, "variable_declaration")) return .variable_decl;
        if (std.mem.eql(u8, node_type, "binary_expression")) return .binary_expr;
        if (std.mem.eql(u8, node_type, "call_expression")) return .call_expr;
        if (std.mem.eql(u8, node_type, "identifier")) return .identifier_expr;
        if (std.mem.eql(u8, node_type, "number_literal") or
            std.mem.eql(u8, node_type, "string_literal") or
            std.mem.eql(u8, node_type, "true") or
            std.mem.eql(u8, node_type, "false")) return .literal_expr;
        if (std.mem.eql(u8, node_type, "compound_statement") or
            std.mem.eql(u8, node_type, "block")) return .block_stmt;
        if (std.mem.eql(u8, node_type, "return_statement")) return .return_stmt;
        return .unknown;
    }
};

// ═══════════════════════════════════════════════════════════
// MlcpdToHeaven : ParsedFile → AST Heaven (6 primitives)
// ═══════════════════════════════════════════════════════════
pub const MlcpdToHeaven = struct {
    allocator: Allocator,
    store: *Store,

    pub fn init(allocator: Allocator, store: *Store) MlcpdToHeaven {
        return .{ .allocator = allocator, .store = store };
    }

    pub fn convert(self: *MlcpdToHeaven, parsed: *mlcpd_mod.ParsedFile) !Id {
        // platform.debug.print("[MlcpdToHeaven] Converting {d} nodes (bottom-up)\n", .{parsed.nodes.items.len});

        if (parsed.nodes.items.len == 0) {
            // platform.debug.print("[MlcpdToHeaven] ERROR: No nodes to convert\n", .{});
            return error.InvalidStructure;
        }

        // CORRECTION BUG 1 : Traiter en ordre inverse (enfants d'abord, parents ensuite)
        var i: usize = parsed.nodes.items.len;
        while (i > 0) {
            i -= 1;
            const node = parsed.nodes.items[i];
            // platform.debug.print("[MlcpdToHeaven] Converting node {d}: role={s}, type={s}\n", .{ node.id, @tagName(node.role), node.node_type });

            const heaven_id = self.convertNode(parsed, node.id) catch {
                // platform.debug.print("[MlcpdToHeaven] ERROR converting node {d}: {}\n", .{ node.id, err });
                continue; // Skip ce nœud et continuer avec les autres
            };
            try parsed.node_to_expr.put(self.allocator, node.id, heaven_id);
        }

        const root_id = parsed.node_to_expr.get(0) orelse {
            // platform.debug.print("[MlcpdToHeaven] ERROR: Root node not found in node_to_expr\n", .{});
            return error.InvalidStructure;
        };

        // platform.debug.print("[MlcpdToHeaven] Root node converted to heaven_id={d}\n", .{root_id});
        return root_id;
    }

    fn convertNode(self: *MlcpdToHeaven, parsed: *mlcpd_mod.ParsedFile, node_id: u32) !Id {
        const node = parsed.nodes.items[node_id];

        return switch (node.role) {
            .function_decl => try self.convertFunction(parsed, node_id),
            .variable_decl => try self.convertVariable(parsed, node_id),
            .binary_expr => try self.convertBinaryExpr(parsed, node_id),
            .unary_expr => try self.convertUnaryExpr(parsed, node_id),
            .call_expr => try self.convertCallExpr(parsed, node_id),
            .identifier_expr => try self.convertIdentifier(node),
            .literal_expr => try self.convertLiteral(node),
            .block_stmt => try self.convertBlock(parsed, node_id),
            .return_stmt => try self.convertReturn(parsed, node_id),
            else => try self.convertDefault(parsed, node_id),
        };
    }

    fn convertFunction(self: *MlcpdToHeaven, parsed: *mlcpd_mod.ParsedFile, node_id: u32) !Id {
        const node = parsed.nodes.items[node_id];
        const children = parsed.nodes.items[node.children_start..][0..node.children_count];

        var name_sym: ?expr.Sym = null;
        var param_ids: std.ArrayList(Id) = .empty;
        defer param_ids.deinit(self.allocator);
        var body_id: ?Id = null;

        for (children) |child| {
            if (child.role == .identifier_expr and name_sym == null) {
                name_sym = try self.store.interner.intern(child.code_snippet);
            } else if (child.role == .parameter_decl) {
                const param_child = self.findChildByRole(parsed, child.id, .identifier_expr);
                if (param_child) |pc| {
                    const param_sym = try self.store.interner.intern(pc.code_snippet);
                    const param_sym_node = try self.store.addNode(.{
                        .tag = .sym,
                        .payload = param_sym,
                        .aux = 0,
                        .span_a = Span.EMPTY,
                        .span_b = Span.EMPTY,
                    });
                    try param_ids.append(self.allocator, param_sym_node);
                }
            } else if (child.role == .block_stmt) {
                body_id = parsed.node_to_expr.get(child.id);
            }
        }

        const actual_name = name_sym orelse return error.InvalidStructure;
        const actual_body = body_id orelse try self.store.addNode(.{
            .tag = .lit,
            .payload = 0,
            .aux = try self.store.addLit(.{ .unit = {} }),
            .span_a = Span.EMPTY,
            .span_b = Span.EMPTY,
        });

        // Lambda : (lambda (params...) body)
        var cur_body = actual_body;
        var pi: usize = param_ids.items.len;
        while (pi > 0) {
            pi -= 1;
            const param_node = self.store.get(param_ids.items[pi]);
            const span = try self.store.reserveSpan(1);
            self.store.pool.items[span.start] = cur_body;
            cur_body = try self.store.addNode(.{
                .tag = .lambda,
                .payload = param_node.payload,
                .aux = 0,
                .span_a = span,
                .span_b = Span.EMPTY,
            });
        }

        // Bind : (bind name [value, body])
        // Pour une définition de fonction : value = lambda, body = unit
        const bind_span = try self.store.reserveSpan(2);
        self.store.pool.items[bind_span.start] = cur_body;
        self.store.pool.items[bind_span.start + 1] = try self.store.addNode(.{
            .tag = .lit,
            .payload = 0,
            .aux = try self.store.addLit(.{ .unit = {} }),
            .span_a = Span.EMPTY,
            .span_b = Span.EMPTY,
        });

        return try self.store.addNode(.{
            .tag = .bind,
            .payload = actual_name,
            .aux = 0,
            .span_a = bind_span,
            .span_b = Span.EMPTY,
        });
    }

    fn convertBinaryExpr(self: *MlcpdToHeaven, parsed: *mlcpd_mod.ParsedFile, node_id: u32) !Id {
        const node = parsed.nodes.items[node_id];
        const children = parsed.nodes.items[node.children_start..][0..node.children_count];

        if (children.len < 3) return error.InvalidStructure;

        const op_text = children[1].code_snippet; // L'opérateur est généralement au milieu
        const left_id = parsed.node_to_expr.get(children[0].id) orelse return error.InvalidStructure;
        const right_id = parsed.node_to_expr.get(children[2].id) orelse return error.InvalidStructure;

        const op_sym = try self.store.interner.intern(op_text);
        const op_sym_node = try self.store.addNode(.{
            .tag = .sym,
            .payload = op_sym,
            .aux = 0,
            .span_a = Span.EMPTY,
            .span_b = Span.EMPTY,
        });

        const apply_span = try self.store.reserveSpan(3);
        self.store.pool.items[apply_span.start] = op_sym_node;
        self.store.pool.items[apply_span.start + 1] = left_id;
        self.store.pool.items[apply_span.start + 2] = right_id;

        return try self.store.addNode(.{
            .tag = .apply,
            .payload = op_sym_node,
            .aux = 0,
            .span_a = apply_span,
            .span_b = Span.EMPTY,
        });
    }

    fn convertUnaryExpr(self: *MlcpdToHeaven, parsed: *mlcpd_mod.ParsedFile, node_id: u32) !Id {
        const node = parsed.nodes.items[node_id];
        const children = parsed.nodes.items[node.children_start..][0..node.children_count];

        if (children.len < 2) return error.InvalidStructure;

        const op_text = children[0].code_snippet;
        const operand_id = parsed.node_to_expr.get(children[1].id) orelse return error.InvalidStructure;

        const op_sym = try self.store.interner.intern(op_text);
        const op_sym_node = try self.store.addNode(.{
            .tag = .sym,
            .payload = op_sym,
            .aux = 0,
            .span_a = Span.EMPTY,
            .span_b = Span.EMPTY,
        });

        const apply_span = try self.store.reserveSpan(2);
        self.store.pool.items[apply_span.start] = op_sym_node;
        self.store.pool.items[apply_span.start + 1] = operand_id;

        return try self.store.addNode(.{
            .tag = .apply,
            .payload = op_sym_node,
            .aux = 0,
            .span_a = apply_span,
            .span_b = Span.EMPTY,
        });
    }

    fn convertCallExpr(self: *MlcpdToHeaven, parsed: *mlcpd_mod.ParsedFile, node_id: u32) !Id {
        const node = parsed.nodes.items[node_id];
        const children = parsed.nodes.items[node.children_start..][0..node.children_count];

        if (children.len == 0) return error.InvalidStructure;

        const func_id = parsed.node_to_expr.get(children[0].id) orelse return error.InvalidStructure;

        var arg_ids: std.ArrayList(Id) = .empty;
        defer arg_ids.deinit(self.allocator);

        for (children[1..]) |child| {
            if (parsed.node_to_expr.get(child.id)) |arg_id| {
                try arg_ids.append(self.allocator, arg_id);
            }
        }

        const apply_span = try self.store.reserveSpan(1 + arg_ids.items.len);
        self.store.pool.items[apply_span.start] = func_id;
        for (arg_ids.items, 0..) |arg_id, idx| {
            self.store.pool.items[apply_span.start + 1 + idx] = arg_id;
        }

        return try self.store.addNode(.{
            .tag = .apply,
            .payload = func_id,
            .aux = 0,
            .span_a = apply_span,
            .span_b = Span.EMPTY,
        });
    }

    fn convertLiteral(self: *MlcpdToHeaven, node: mlcpd_mod.MlcpdNode) !Id {
        const text = node.code_snippet;

        if (std.fmt.parseInt(i64, text, 10)) |val| {
            const lit = expr.Lit{ .int = val };
            const aux = try self.store.addLit(lit);
            return try self.store.addNode(.{
                .tag = .lit,
                .payload = 0,
                .aux = aux,
                .span_a = Span.EMPTY,
                .span_b = Span.EMPTY,
            });
        } else |_| {}

        if (std.fmt.parseFloat(f64, text)) |val| {
            const lit = expr.Lit{ .float = val };
            const aux = try self.store.addLit(lit);
            return try self.store.addNode(.{
                .tag = .lit,
                .payload = 0,
                .aux = aux,
                .span_a = Span.EMPTY,
                .span_b = Span.EMPTY,
            });
        } else |_| {}

        if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false")) {
            const lit = expr.Lit{ .boolean = std.mem.eql(u8, text, "true") };
            const aux = try self.store.addLit(lit);
            return try self.store.addNode(.{
                .tag = .lit,
                .payload = 0,
                .aux = aux,
                .span_a = Span.EMPTY,
                .span_b = Span.EMPTY,
            });
        }

        const sym = try self.store.interner.intern(text);
        const lit = expr.Lit{ .str = sym };
        const aux = try self.store.addLit(lit);
        return try self.store.addNode(.{
            .tag = .lit,
            .payload = 0,
            .aux = aux,
            .span_a = Span.EMPTY,
            .span_b = Span.EMPTY,
        });
    }

    fn convertIdentifier(self: *MlcpdToHeaven, node: mlcpd_mod.MlcpdNode) !Id {
        const sym = try self.store.interner.intern(node.code_snippet);
        return try self.store.addNode(.{
            .tag = .sym,
            .payload = sym,
            .aux = 0,
            .span_a = Span.EMPTY,
            .span_b = Span.EMPTY,
        });
    }

    fn convertBlock(self: *MlcpdToHeaven, parsed: *mlcpd_mod.ParsedFile, node_id: u32) !Id {
        const node = parsed.nodes.items[node_id];
        const children = parsed.nodes.items[node.children_start..][0..node.children_count];

        if (children.len == 0) {
            return try self.store.addNode(.{
                .tag = .lit,
                .payload = 0,
                .aux = try self.store.addLit(.{ .unit = {} }),
                .span_a = Span.EMPTY,
                .span_b = Span.EMPTY,
            });
        }

        // Retourner la dernière expression du bloc
        var last_id: Id = undefined;
        for (children) |child| {
            if (parsed.node_to_expr.get(child.id)) |child_id| {
                last_id = child_id;
            }
        }

        return last_id;
    }

    fn convertReturn(self: *MlcpdToHeaven, parsed: *mlcpd_mod.ParsedFile, node_id: u32) !Id {
        const node = parsed.nodes.items[node_id];
        const children = parsed.nodes.items[node.children_start..][0..node.children_count];

        if (children.len == 0) {
            return try self.store.addNode(.{
                .tag = .lit,
                .payload = 0,
                .aux = try self.store.addLit(.{ .unit = {} }),
                .span_a = Span.EMPTY,
                .span_b = Span.EMPTY,
            });
        }

        // Retourner l'expression de retour
        return parsed.node_to_expr.get(children[0].id) orelse error.InvalidStructure;
    }

    fn convertVariable(self: *MlcpdToHeaven, parsed: *mlcpd_mod.ParsedFile, node_id: u32) !Id {
        const node = parsed.nodes.items[node_id];
        const children = parsed.nodes.items[node.children_start..][0..node.children_count];

        // CORRECTION BUG 3 : Utiliser un optionnel
        var name_sym: ?expr.Sym = null;
        var value_id: ?Id = null;

        for (children) |child| {
            if (child.role == .identifier_expr and name_sym == null) {
                name_sym = try self.store.interner.intern(child.code_snippet);
            } else if (parsed.node_to_expr.get(child.id)) |cid| {
                value_id = cid;
            }
        }

        const actual_name = name_sym orelse return error.InvalidStructure;
        const actual_value = value_id orelse try self.store.addNode(.{
            .tag = .lit,
            .payload = 0,
            .aux = try self.store.addLit(.{ .unit = {} }),
            .span_a = Span.EMPTY,
            .span_b = Span.EMPTY,
        });

        const bind_span = try self.store.reserveSpan(1);
        self.store.pool.items[bind_span.start] = actual_value;

        return try self.store.addNode(.{
            .tag = .bind,
            .payload = actual_name,
            .aux = 0,
            .span_a = bind_span,
            .span_b = Span.EMPTY,
        });
    }

    fn convertDefault(self: *MlcpdToHeaven, parsed: *mlcpd_mod.ParsedFile, node_id: u32) !Id {
        const node = parsed.nodes.items[node_id];

        if (node.children_count == 0) {
            // Feuille sans rôle connu : essayer de parser le texte comme littéral
            return self.convertLiteral(node);
        }

        const children = parsed.nodes.items[node.children_start..][0..node.children_count];
        if (children.len == 1) {
            return parsed.node_to_expr.get(children[0].id) orelse error.InvalidStructure;
        }

        // Plusieurs enfants : retourner le dernier
        for (children) |child| {
            if (parsed.node_to_expr.get(child.id)) |child_id| {
                return child_id;
            }
        }

        return error.InvalidStructure;
    }

    fn findChildByRole(self: *MlcpdToHeaven, parsed: *mlcpd_mod.ParsedFile, parent_id: u32, role: mlcpd_mod.SemanticRole) ?mlcpd_mod.MlcpdNode {
        _ = self;
        const parent = parsed.nodes.items[parent_id];
        const children = parsed.nodes.items[parent.children_start..][0..parent.children_count];
        for (children) |child| {
            if (child.role == role) return child;
        }
        return null;
    }
};

// ═══════════════════════════════════════════════════════════
// UniversalTranslator : orchestrateur
// ═══════════════════════════════════════════════════════════
pub const UniversalTranslator = struct {
    allocator: Allocator,
    store: *Store,

    pub fn init(allocator: Allocator, store: *Store) UniversalTranslator {
        return .{ .allocator = allocator, .store = store };
    }

    pub fn translate(self: *UniversalTranslator, matrix: *const Matrix, lang: mlcpd_mod.FileMetadata.Language) !Id {
        // platform.debug.print("[UniversalTranslator] Starting translation\n", .{});

        var converter = MlcpdConverter.init(self.allocator);
        var parsed = try converter.convert(matrix, lang);
        defer parsed.deinit();

        // platform.debug.print("[UniversalTranslator] ParsedFile created with {d} nodes\n", .{parsed.nodes.items.len});

        var to_heaven = MlcpdToHeaven.init(self.allocator, self.store);
        const heaven_id = try to_heaven.convert(&parsed);

        // platform.debug.print("[UniversalTranslator] Translation successful, heaven_id={d}\n", .{heaven_id});

        return heaven_id;
    }
};
