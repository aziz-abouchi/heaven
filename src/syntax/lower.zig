//! Tree-sitter CST -> Heaven Syntax AST/HIR.
//!
//! Cette couche ne construit PAS encore core.Expr.
//! Elle produit src/syntax/ast.zig.

const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("syntax_ast");
const platform = @import("platform");
const ts = platform.ts;

pub const LowerError = error{
    UnsupportedNode,
    MissingField,
    InvalidLiteral,
    InvalidCharacter,
    Overflow,
    OutOfMemory,
};

pub const Lowerer = struct {
    allocator: Allocator,
    source: []const u8,

    pub fn init(allocator: Allocator, source: []const u8) Lowerer {
        return .{
            .allocator = allocator,
            .source = source,
        };
    }

    fn kind(_: *const Lowerer, node: ts.TSNode) []const u8 {
        return std.mem.span(ts.ts_node_type(node));
    }

    fn text(self: *const Lowerer, node: ts.TSNode) []const u8 {
        const start = ts.ts_node_start_byte(node);
        const end = ts.ts_node_end_byte(node);
        return self.source[start..end];
    }

    fn span(_: *const Lowerer, node: ts.TSNode) ast.Span {
        return .{
            .start = ts.ts_node_start_byte(node),
            .end = ts.ts_node_end_byte(node),
        };
    }

    fn field(node: ts.TSNode, name: []const u8) ?ts.TSNode {
        const child = ts.ts_node_child_by_field_name(
            node,
            name.ptr,
            @intCast(name.len),
        );
        if (ts.ts_node_is_null(child)) return null;
        return child;
    }

    fn namedCount(_: *const Lowerer, node: ts.TSNode) u32 {
        return ts.ts_node_named_child_count(node);
    }

    fn namedChild(_: *const Lowerer, node: ts.TSNode, i: u32) ts.TSNode {
        return ts.ts_node_named_child(node, i);
    }

    pub fn lower(self: *Lowerer, root: ts.TSNode) LowerError!ast.Ast {
        const k = self.kind(root);

        if (!std.mem.eql(u8, k, "source_file")) {
            return LowerError.UnsupportedNode;
        }

        var items = std.ArrayListUnmanaged(ast.Item){};
        errdefer {
            for (items.items) |*item| item.deinit(self.allocator);
            items.deinit(self.allocator);
        }

        const n = self.namedCount(root);

        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const child = self.namedChild(root, i);
            if (ts.ts_node_is_extra(child)) continue;

            if (self.lowerItem(child)) |item| {
                try items.append(self.allocator, item);
            } else |err| {
                return err;
            }
        }

        const owned = try items.toOwnedSlice(self.allocator);
        return ast.Ast.init(
            self.allocator,
            self.source,
            owned,
        );
    }

    fn lowerItem(self: *Lowerer, node: ts.TSNode) LowerError!ast.Item {
        const k = self.kind(node);

        if (std.mem.eql(u8, k, "eq_decl")) {
            return .{ .equation = try self.lowerEquation(node) };
        }

        if (std.mem.eql(u8, k, "data_decl")) {
            return .{ .data_decl = try self.lowerDataDecl(node) };
        }

        if (std.mem.eql(u8, k, "axiom_decl")) {
            return .{ .axiom_decl = try self.lowerAxiomDecl(node) };
        }

        if (std.mem.eql(u8, k, "theorem_decl")) {
            return .{ .theorem_decl = try self.lowerTheoremDecl(node) };
        }

        if (std.mem.eql(u8, k, "proof_decl")) {
            return .{ .proof_decl = try self.lowerProofDecl(node) };
        }

        if (std.mem.eql(u8, k, "fn_decl")) {
            return .{ .fn_decl = try self.lowerFnDecl(node) };
        }

        return LowerError.UnsupportedNode;
    }

    fn lowerEquation(self: *Lowerer, node: ts.TSNode) LowerError!ast.Equation {
        const name_node = field(node, "name") orelse {
            // Fallback : premier enfant nommé = nom.
            if (self.namedCount(node) == 0) return LowerError.MissingField;
            return self.lowerEquationByChildren(node);
        };

        const name = self.text(name_node);

        var children = std.ArrayListUnmanaged(ts.TSNode){};
        defer children.deinit(self.allocator);

        const n = self.namedCount(node);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const child = self.namedChild(node, i);
            if (child.id == name_node.id) continue;
            try children.append(self.allocator, child);
        }

        if (children.items.len == 0) return LowerError.MissingField;

        const body_node = children.items[children.items.len - 1];

        var patterns = std.ArrayListUnmanaged(ast.Pattern){};
        errdefer {
            for (patterns.items) |*p| p.deinit(self.allocator);
            patterns.deinit(self.allocator);
        }

        for (children.items[0 .. children.items.len - 1]) |child| {
            if (std.mem.eql(u8, self.kind(child), "pattern")) {
                try patterns.append(
                    self.allocator,
                    try self.lowerPattern(child),
                );
            }
        }

        const body = try self.lowerExpr(body_node);

        return .{
            .name = name,
            .patterns = try patterns.toOwnedSlice(self.allocator),
            .body = body,
            .span = self.span(node),
        };
    }

    fn lowerEquationByChildren(self: *Lowerer, node: ts.TSNode) LowerError!ast.Equation {
        const n = self.namedCount(node);
        if (n < 2) return LowerError.MissingField;

        const name = self.text(self.namedChild(node, 0));

        var patterns = std.ArrayListUnmanaged(ast.Pattern){};
        errdefer {
            for (patterns.items) |*p| p.deinit(self.allocator);
            patterns.deinit(self.allocator);
        }

        var i: u32 = 1;
        while (i + 1 < n) : (i += 1) {
            try patterns.append(
                self.allocator,
                try self.lowerPattern(self.namedChild(node, i)),
            );
        }

        const body = try self.lowerExpr(self.namedChild(node, n - 1));

        return .{
            .name = name,
            .patterns = try patterns.toOwnedSlice(self.allocator),
            .body = body,
            .span = self.span(node),
        };
    }

    fn lowerDataDecl(self: *Lowerer, node: ts.TSNode) LowerError!ast.DataDecl {
        const name_node = field(node, "name") orelse {
            // La grammaire actuelle peut exposer le nom comme premier enfant nommé.
            if (self.namedCount(node) == 0) return LowerError.MissingField;
            return self.lowerDataDeclByChildren(node);
        };

        var constructors = std.ArrayListUnmanaged(ast.DataConstructor){};
        errdefer {
            for (constructors.items) |*ctor| ctor.deinit(self.allocator);
            constructors.deinit(self.allocator);
        }

        const n = self.namedCount(node);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const child = self.namedChild(node, i);
            if (child.id == name_node.id) continue;

            if (std.mem.eql(u8, self.kind(child), "data_constructor")) {
                try constructors.append(
                    self.allocator,
                    try self.lowerDataConstructor(child),
                );
            }
        }

        return .{
            .name = self.text(name_node),
            .constructors = try constructors.toOwnedSlice(self.allocator),
            .span = self.span(node),
        };
    }

    fn lowerDataDeclByChildren(self: *Lowerer, node: ts.TSNode) LowerError!ast.DataDecl {
        const n = self.namedCount(node);
        if (n == 0) return LowerError.MissingField;

        const name = self.text(self.namedChild(node, 0));
        var constructors = std.ArrayListUnmanaged(ast.DataConstructor){};

        errdefer {
            for (constructors.items) |*ctor| ctor.deinit(self.allocator);
            constructors.deinit(self.allocator);
        }

        var i: u32 = 1;
        while (i < n) : (i += 1) {
            const child = self.namedChild(node, i);
            if (std.mem.eql(u8, self.kind(child), "data_constructor")) {
                try constructors.append(
                    self.allocator,
                    try self.lowerDataConstructor(child),
                );
            }
        }

        return .{
            .name = name,
            .constructors = try constructors.toOwnedSlice(self.allocator),
            .span = self.span(node),
        };
    }

    fn lowerDataConstructor(self: *Lowerer, node: ts.TSNode) LowerError!ast.DataConstructor {
        const n = self.namedCount(node);
        if (n == 0) return LowerError.MissingField;

        const name = self.text(self.namedChild(node, 0));

        var args = std.ArrayListUnmanaged(ast.TypeExpr){};
        errdefer {
            for (args.items) |*arg| arg.deinit(self.allocator);
            args.deinit(self.allocator);
        }

        var i: u32 = 1;
        while (i < n) : (i += 1) {
            const child = self.namedChild(node, i);
            if (std.mem.eql(u8, self.kind(child), "ctor_arg_type")) {
                try args.append(
                    self.allocator,
                    try self.lowerType(self.namedChild(child, 0)),
                );
            } else {
                try args.append(
                    self.allocator,
                    try self.lowerType(child),
                );
            }
        }

        return .{
            .name = name,
            .args = try args.toOwnedSlice(self.allocator),
        };
    }

    fn lowerAxiomDecl(self: *Lowerer, node: ts.TSNode) LowerError!ast.AxiomDecl {
        const name_node = field(node, "name") orelse {
            if (self.namedCount(node) == 0) return LowerError.MissingField;
            return LowerError.MissingField;
        };

        const type_node = self.namedChild(
            node,
            self.namedCount(node) - 1,
        );

        return .{
            .name = self.text(name_node),
            .proposition = try self.lowerType(type_node),
            .span = self.span(node),
        };
    }

    fn lowerTheoremDecl(self: *Lowerer, node: ts.TSNode) LowerError!ast.TheoremDecl {
        const name_node = field(node, "name") orelse return LowerError.MissingField;

        const n = self.namedCount(node);
        if (n < 2) return LowerError.MissingField;

        var proposition: ?ast.TypeExpr = null;
        var proof: ?ast.ProofBlock = null;

        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const child = self.namedChild(node, i);
            if (child.id == name_node.id) continue;

            const k = self.kind(child);
            if (std.mem.eql(u8, k, "proof_block")) {
                proof = try self.lowerProofBlock(child);
            } else if (proposition == null) {
                proposition = try self.lowerType(child);
            }
        }

        return .{
            .name = self.text(name_node),
            .proposition = proposition orelse return LowerError.MissingField,
            .proof = proof,
            .span = self.span(node),
        };
    }

    fn lowerProofDecl(self: *Lowerer, node: ts.TSNode) LowerError!ast.ProofDecl {
        const n = self.namedCount(node);
        if (n == 0) return LowerError.MissingField;

        const name = self.text(self.namedChild(node, 0));

        return .{
            .name = name,
            .strategy = null,
            .steps = &.{},
            .span = self.span(node),
        };
    }

    fn lowerProofBlock(self: *Lowerer, node: ts.TSNode) LowerError!ast.ProofBlock {
        var strategy: ?ast.ProofStrategy = null;
        var steps = std.ArrayListUnmanaged(ast.ProofStep){};

        errdefer {
            for (steps.items) |*s| s.deinit(self.allocator);
            steps.deinit(self.allocator);
        }

        const n = self.namedCount(node);
        var i: u32 = 0;

        while (i < n) : (i += 1) {
            const child = self.namedChild(node, i);
            const k = self.kind(child);

            if (std.mem.eql(u8, k, "proof_strategy")) {
                strategy = try self.lowerProofStrategy(child);
            } else if (std.mem.eql(u8, k, "proof_step")) {
                try steps.append(
                    self.allocator,
                    try self.lowerProofStep(child),
                );
            }
        }

        return .{
            .strategy = strategy,
            .steps = try steps.toOwnedSlice(self.allocator),
        };
    }

    fn lowerProofStrategy(self: *Lowerer, node: ts.TSNode) LowerError!ast.ProofStrategy {
        const raw = self.text(node);

        if (std.mem.startsWith(u8, raw, "induction")) {
            var it = std.mem.tokenizeAny(u8, raw, " \t\r\n");
            _ = it.next();
            return .{ .induction = it.next() orelse "" };
        }

        if (std.mem.startsWith(u8, raw, "cases")) {
            var it = std.mem.tokenizeAny(u8, raw, " \t\r\n");
            _ = it.next();
            return .{ .cases = it.next() orelse "" };
        }

        if (std.mem.eql(u8, raw, "contradiction")) return .contradiction;
        if (std.mem.eql(u8, raw, "trivial")) return .trivial;
        if (std.mem.eql(u8, raw, "construction")) return .construction;
        if (std.mem.eql(u8, raw, "information_theory")) return .information_theory;

        return .{ .named = raw };
    }

    fn lowerProofStep(self: *Lowerer, node: ts.TSNode) LowerError!ast.ProofStep {
        const raw = self.text(node);

        if (std.mem.eql(u8, raw, "trivial")) return .trivial;
        if (std.mem.eql(u8, raw, "qed")) return .qed;

        const first = if (self.namedCount(node) > 0)
            self.namedChild(node, 0)
        else
            return LowerError.UnsupportedNode;

        const k = self.kind(first);

        if (std.mem.eql(u8, k, "case")) {
            return .{
                .case_step = .{
                    .pattern = try self.lowerPattern(self.namedChild(node, 1)),
                    .steps = &.{},
                },
            };
        }

        if (std.mem.startsWith(u8, raw, "apply ")) {
            return .{ .apply = try self.lowerExpr(first) };
        }

        if (std.mem.startsWith(u8, raw, "rewrite ")) {
            return .{ .rewrite = try self.lowerExpr(first) };
        }

        return LowerError.UnsupportedNode;
    }

    fn lowerFnDecl(self: *Lowerer, node: ts.TSNode) LowerError!ast.FunctionDecl {
        const name_node = field(node, "name") orelse return LowerError.MissingField;
        const params_node = field(node, "params") orelse return LowerError.MissingField;

        var params = std.ArrayListUnmanaged([]const u8){};
        errdefer params.deinit(self.allocator);

        const pn = self.namedCount(params_node);
        var i: u32 = 0;
        while (i < pn) : (i += 1) {
            const p = self.namedChild(params_node, i);
            if (self.namedCount(p) > 0) {
                try params.append(
                    self.allocator,
                    self.text(self.namedChild(p, 0)),
                );
            } else {
                try params.append(self.allocator, self.text(p));
            }
        }

        const body = try self.lowerLastNamedChild(node);

        return .{
            .name = self.text(name_node),
            .params = try params.toOwnedSlice(self.allocator),
            .body = body,
            .span = self.span(node),
        };
    }

    fn lowerLastNamedChild(self: *Lowerer, node: ts.TSNode) LowerError!ast.Expr {
        const n = self.namedCount(node);
        if (n == 0) return LowerError.MissingField;
        return self.lowerExpr(self.namedChild(node, n - 1));
    }

    fn lowerPattern(self: *Lowerer, node: ts.TSNode) LowerError!ast.Pattern {
        var current = node;
        if (std.mem.eql(u8, self.kind(current), "pattern") and self.namedCount(current) > 0) {
            current = self.namedChild(current, 0);
        }

        const k = self.kind(current);

        if (std.mem.eql(u8, k, "identifier") or
            std.mem.eql(u8, k, "type_name"))
        {
            return .{ .variable = self.text(current) };
        }

        if (std.mem.eql(u8, k, "ctor_pat")) {
            return self.lowerCtorPattern(current);
        }

        if (std.mem.eql(u8, k, "int")) {
            return .{ .int = try std.fmt.parseInt(i64, self.text(current), 0) };
        }

        if (std.mem.eql(u8, k, "float")) {
            return .{ .float = try std.fmt.parseFloat(f64, self.text(current)) };
        }

        if (std.mem.eql(u8, k, "str")) {
            const s = self.text(current);
            return .{
                .string = if (s.len >= 2) s[1 .. s.len - 1] else s,
            };
        }

        if (std.mem.eql(u8, k, "bool_lit")) {
            return .{ .boolean = std.mem.eql(u8, self.text(current), "true") };
        }

        if (std.mem.eql(u8, k, "_")) {
            return .wildcard;
        }

        return LowerError.UnsupportedNode;
    }

    fn lowerCtorPattern(self: *Lowerer, node: ts.TSNode) LowerError!ast.Pattern {
        const n = self.namedCount(node);
        if (n == 0) return LowerError.MissingField;

        const name = self.text(self.namedChild(node, 0));

        var args = std.ArrayListUnmanaged(ast.Pattern){};
        errdefer {
            for (args.items) |*a| a.deinit(self.allocator);
            args.deinit(self.allocator);
        }

        var i: u32 = 1;
        while (i < n) : (i += 1) {
            try args.append(
                self.allocator,
                try self.lowerPattern(self.namedChild(node, i)),
            );
        }

        return .{
            .constructor = .{
                .name = name,
                .args = try args.toOwnedSlice(self.allocator),
            },
        };
    }

    fn lowerExpr(self: *Lowerer, node: ts.TSNode) LowerError!ast.Expr {
        const k = self.kind(node);

        if (std.mem.eql(u8, k, "identifier") or
            std.mem.eql(u8, k, "type_name"))
        {
            return .{ .identifier = self.text(node) };
        }

        if (std.mem.eql(u8, k, "int")) {
            return .{
                .int = try std.fmt.parseInt(i64, self.text(node), 0),
            };
        }

        if (std.mem.eql(u8, k, "float")) {
            return .{
                .float = try std.fmt.parseFloat(f64, self.text(node)),
            };
        }

        if (std.mem.eql(u8, k, "str")) {
            const s = self.text(node);
            return .{
                .string = if (s.len >= 2) s[1 .. s.len - 1] else s,
            };
        }

        if (std.mem.eql(u8, k, "bool_lit")) {
            return .{
                .boolean = std.mem.eql(u8, self.text(node), "true"),
            };
        }

        if (std.mem.eql(u8, k, "paren_expr")) {
            if (self.namedCount(node) == 0) return LowerError.MissingField;

            const inner = try self.lowerExpr(self.namedChild(node, 0));
            const ptr = try self.allocator.create(ast.Expr);
            ptr.* = inner;
            return .{ .parenthesized = ptr };
        }

        if (std.mem.eql(u8, k, "binary")) {
            return self.lowerBinary(node);
        }

        if (std.mem.eql(u8, k, "call") or
            std.mem.eql(u8, k, "app_expr"))
        {
            return self.lowerCallLike(node);
        }

        return LowerError.UnsupportedNode;
    }

    fn lowerBinary(self: *Lowerer, node: ts.TSNode) LowerError!ast.Expr {
        const lhs_node = ts.ts_node_child(node, 0);
        const op_node = ts.ts_node_child(node, 1);
        const rhs_node = ts.ts_node_child(node, 2);

        const lhs = try self.lowerExpr(lhs_node);
        const rhs = try self.lowerExpr(rhs_node);

        const lp = try self.allocator.create(ast.Expr);
        errdefer self.allocator.destroy(lp);
        lp.* = lhs;

        const rp = try self.allocator.create(ast.Expr);
        errdefer self.allocator.destroy(rp);
        rp.* = rhs;

        return .{
            .binary = .{
                .op = self.text(op_node),
                .lhs = lp,
                .rhs = rp,
            },
        };
    }

    fn lowerCallLike(self: *Lowerer, node: ts.TSNode) LowerError!ast.Expr {
        const n = self.namedCount(node);
        if (n == 0) return LowerError.MissingField;

        var children = std.ArrayListUnmanaged(ast.Expr){};
        errdefer {
            for (children.items) |*x| x.deinit(self.allocator);
            children.deinit(self.allocator);
        }

        var i: u32 = 0;
        while (i < n) : (i += 1) {
            try children.append(
                self.allocator,
                try self.lowerExpr(self.namedChild(node, i)),
            );
        }

        return .{
            .application = try children.toOwnedSlice(self.allocator),
        };
    }

    fn lowerType(self: *Lowerer, node: ts.TSNode) LowerError!ast.TypeExpr {
        const k = self.kind(node);

        if (std.mem.eql(u8, k, "type_ident") or
            std.mem.eql(u8, k, "prim_type") or
            std.mem.eql(u8, k, "type_name"))
        {
            return .{
                .named = self.text(node),
            };
        }

        if (std.mem.eql(u8, k, "identifier")) {
            return .{
                .named = self.text(node),
            };
        }

        if (std.mem.eql(u8, k, "generic_type") or
            std.mem.eql(u8, k, "applied_type"))
        {
            const n = self.namedCount(node);
            if (n == 0) return LowerError.MissingField;

            const name = self.text(self.namedChild(node, 0));
            var args = std.ArrayListUnmanaged(ast.TypeExpr){};

            errdefer {
                for (args.items) |*x| x.deinit(self.allocator);
                args.deinit(self.allocator);
            }

            var i: u32 = 1;
            while (i < n) : (i += 1) {
                try args.append(
                    self.allocator,
                    try self.lowerType(self.namedChild(node, i)),
                );
            }

            if (std.mem.eql(u8, k, "generic_type")) {
                return .{
                    .generic = .{
                        .name = name,
                        .args = try args.toOwnedSlice(self.allocator),
                    },
                };
            }

            return .{
                .applied = .{
                    .name = name,
                    .args = try args.toOwnedSlice(self.allocator),
                },
            };
        }

        if (std.mem.eql(u8, k, "arrow_type")) {
            const from = try self.lowerType(self.namedChild(node, 0));
            const to = try self.lowerType(self.namedChild(node, 1));

            const fp = try self.allocator.create(ast.TypeExpr);
            fp.* = from;

            const tp = try self.allocator.create(ast.TypeExpr);
            tp.* = to;

            return .{
                .arrow = .{
                    .from = fp,
                    .to = tp,
                },
            };
        }

        if (std.mem.eql(u8, k, "forall_type")) {
            const n = self.namedCount(node);
            if (n < 2) return LowerError.MissingField;

            var binders = std.ArrayListUnmanaged(ast.Binder){};

            errdefer {
                for (binders.items) |*b| b.deinit(self.allocator);
                binders.deinit(self.allocator);
            }

            var i: u32 = 0;
            while (i + 1 < n) : (i += 2) {
                const name = self.text(self.namedChild(node, i));
                const ty = try self.lowerType(self.namedChild(node, i + 1));
                try binders.append(self.allocator, .{
                    .name = name,
                    .ty = ty,
                });
            }

            const body = try self.lowerType(self.namedChild(node, n - 1));
            const body_ptr = try self.allocator.create(ast.TypeExpr);
            body_ptr.* = body;

            return .{
                .forall = .{
                    .binders = try binders.toOwnedSlice(self.allocator),
                    .body = body_ptr,
                },
            };
        }

        return LowerError.UnsupportedNode;
    }
};

// ─────────────────────────────────────────────────────────────
// Intégration Tree-sitter
// ─────────────────────────────────────────────────────────────

pub fn lowerSource(
    allocator: Allocator,
    source: []const u8,
) LowerError!ast.Ast {
    const parser = ts.ts_parser_new();
    defer ts.ts_parser_delete(parser);

    _ = ts.ts_parser_set_language(
        parser,
        platform.tree_sitter_heaven(),
    );

    const tree = ts.ts_parser_parse_string(
        parser,
        null,
        source.ptr,
        @intCast(source.len),
    );
    defer ts.ts_tree_delete(tree);

    const root = ts.ts_tree_root_node(tree);

    var lowerer = Lowerer.init(allocator, source);
    return lowerer.lower(root);
}
