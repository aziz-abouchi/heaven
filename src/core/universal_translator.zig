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

        const category = self.mapCategory(matrix.kind);
        const role = self.mapSemanticRole(matrix.kind, matrix.text);

        const node = mlcpd_mod.MlcpdNode{
            .id = node_id,
            .node_type = @tagName(matrix.kind),
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

    fn mapCategory(self: *MlcpdConverter, kind: NodeKind) mlcpd_mod.NodeCategory {
        _ = self;
        return switch (kind) {
            .fn_decl, .bind_decl, .type_decl => .declaration,
            .apply_expr => .expression,
            .binary_expr => .expression,
            .unary_expr => .expression,
            .block => .statement,
            .identifier => .expression,
            .integer_literal, .float_literal, .string_literal, .boolean_literal => .expression,
            .param_list => .declaration,
            .type_expr => .declaration,
            else => .unknown,
        };
    }

    fn mapSemanticRole(self: *MlcpdConverter, kind: NodeKind, text: ?[]const u8) mlcpd_mod.SemanticRole {
        _ = self;
        _ = text;
        return switch (kind) {
            .fn_decl => .function_decl,
            .bind_decl => .variable_decl,
            .apply_expr => .call_expr,
            .binary_expr => .binary_expr,
            .unary_expr => .unary_expr,
            .identifier => .identifier_expr,
            .integer_literal, .float_literal, .string_literal, .boolean_literal => .literal_expr,
            .block => .block_stmt,
            .param_list => .parameter_decl,
            .type_expr => .type_decl,
            else => .unknown,
        };
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
        if (parsed.nodes.items.len == 0) return error.InvalidStructure;

        for (parsed.nodes.items) |node| {
            const heaven_id = try self.convertNode(parsed, node.id);
            try parsed.node_to_expr.put(self.allocator, node.id, heaven_id);
        }

        return parsed.node_to_expr.get(0) orelse error.InvalidStructure;
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
            else => try self.convertDefault(parsed, node_id),
        };
    }

    fn convertFunction(self: *MlcpdToHeaven, parsed: *mlcpd_mod.ParsedFile, node_id: u32) !Id {
        const node = parsed.nodes.items[node_id];
        const children = parsed.nodes.items[node.children_start..][0..node.children_count];

        var name_sym: expr.Sym = undefined;
        var param_ids: std.ArrayList(Id) = .empty;
        defer param_ids.deinit(self.allocator);
        var body_id: ?Id = null;

        for (children) |child| {
            if (child.role == .identifier_expr and name_sym == 0) {
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

        const actual_body = body_id orelse try self.store.addNode(.{
            .tag = .lit,
            .payload = 0,
            .aux = try self.store.addLit(.{ .unit = {} }),
            .span_a = Span.EMPTY,
            .span_b = Span.EMPTY,
        });

        const lambda_span = try self.store.reserveSpan(1 + param_ids.items.len);
        self.store.pool.items[lambda_span.start] = actual_body;
        for (param_ids.items, 0..) |param_id, i| {
            self.store.pool.items[lambda_span.start + 1 + i] = param_id;
        }

        const lambda_id = try self.store.addNode(.{
            .tag = .lambda,
            .payload = 0,
            .aux = 0,
            .span_a = lambda_span,
            .span_b = Span.EMPTY,
        });

        const bind_span = try self.store.reserveSpan(1);
        self.store.pool.items[bind_span.start] = lambda_id;

        return try self.store.addNode(.{
            .tag = .bind,
            .payload = name_sym,
            .aux = 0,
            .span_a = bind_span,
            .span_b = Span.EMPTY,
        });
    }

    fn convertBinaryExpr(self: *MlcpdToHeaven, parsed: *mlcpd_mod.ParsedFile, node_id: u32) !Id {
        const node = parsed.nodes.items[node_id];
        const children = parsed.nodes.items[node.children_start..][0..node.children_count];

        if (children.len < 3) return error.InvalidStructure;

        const op_text = children[0].code_snippet;
        const left_id = parsed.node_to_expr.get(children[1].id) orelse return error.InvalidStructure;
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
        for (arg_ids.items, 0..) |arg_id, i| {
            self.store.pool.items[apply_span.start + 1 + i] = arg_id;
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

        var last_id: Id = undefined;
        for (children) |child| {
            if (parsed.node_to_expr.get(child.id)) |child_id| {
                last_id = child_id;
            }
        }

        return last_id;
    }

    fn convertVariable(self: *MlcpdToHeaven, parsed: *mlcpd_mod.ParsedFile, node_id: u32) !Id {
        const node = parsed.nodes.items[node_id];
        const children = parsed.nodes.items[node.children_start..][0..node.children_count];

        var name_sym: expr.Sym = undefined;
        var value_id: ?Id = null;

        for (children) |child| {
            if (child.role == .identifier_expr and name_sym == 0) {
                name_sym = try self.store.interner.intern(child.code_snippet);
            } else if (parsed.node_to_expr.get(child.id)) |cid| {
                value_id = cid;
            }
        }

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
            .payload = name_sym,
            .aux = 0,
            .span_a = bind_span,
            .span_b = Span.EMPTY,
        });
    }

    fn convertDefault(self: *MlcpdToHeaven, parsed: *mlcpd_mod.ParsedFile, node_id: u32) !Id {
        const node = parsed.nodes.items[node_id];

        if (node.children_count == 0) {
            return try self.convertIdentifier(node);
        }

        const children = parsed.nodes.items[node.children_start..][0..node.children_count];
        if (children.len == 1) {
            return parsed.node_to_expr.get(children[0].id) orelse error.InvalidStructure;
        }

        return try self.convertIdentifier(node);
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
        var converter = MlcpdConverter.init(self.allocator);
        var parsed = try converter.convert(matrix, lang);
        defer parsed.deinit();

        var to_heaven = MlcpdToHeaven.init(self.allocator, self.store);
        const heaven_id = try to_heaven.convert(&parsed);

        return heaven_id;
    }
};
