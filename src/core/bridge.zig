const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const platform = @import("platform");
pub const Matrix = platform.shell_parser_types.Matrix;
pub const NodeKind = platform.shell_parser_types.NodeKind;

pub const Bridge = struct {
    store: *Store,
    allocator: Allocator,

    pub fn init(store: *Store, allocator: Allocator) Bridge {
        return .{ .store = store, .allocator = allocator };
    }

    const Error = Allocator.Error;

    pub fn translateOne(self: *Bridge, node: *const Matrix) Error!Id {
        return switch (node.kind) {
            .identifier, .operator => self.trIdent(node),
            .integer_literal => self.trInt(node),
            .float_literal => self.trFloat(node),
            .string_literal => self.trStr(node),
            .boolean_literal => self.trBool(node),
            .hole_lit => self.trHole(node),
            .bind_decl => self.trBind(node),
            .fn_decl => self.trFn(node),
            .sig_decl => self.trSig(node),
            .eq_decl => self.trEq(node),
            .fact_decl => self.trFact(node),
            .rule_decl => self.trFact(node),
            .query_decl => self.trFact(node),
            .prove_decl => self.trProve(node),
            .apply_expr => self.trApply(node),
            .binary_expr => self.trBinary(node),
            .unary_expr => self.trUnary(node),
            .lambda_expr => self.trLambda(node),
            .if_expr => self.trIf(node),
            .sum_expr => self.trAgg(node, "\xCE\xA3"),
            .prod_expr => self.trAgg(node, "\xCE\xA0"),
            else => self.store.hole(0),
        };
    }

    fn trIdent(self: *Bridge, node: *const Matrix) Error!Id {
        return self.store.sym(node.text orelse "?");
    }

    fn trInt(self: *Bridge, node: *const Matrix) Error!Id {
        const text = node.text orelse return self.store.int(0);
        const val = std.fmt.parseInt(i64, text, 10) catch 0;
        return self.store.int(val);
    }

    fn trFloat(self: *Bridge, node: *const Matrix) Error!Id {
        const text = node.text orelse return self.store.float(0);
        const val = std.fmt.parseFloat(f64, text) catch 0;
        return self.store.float(val);
    }

    fn trStr(self: *Bridge, node: *const Matrix) Error!Id {
        const text = node.text orelse return self.store.lit(.{ .str = 0 });
        const content = if (text.len >= 2) text[1 .. text.len - 1] else text;
        const s = try self.store.interner.intern(content);
        return self.store.lit(.{ .str = s });
    }

    fn trBool(self: *Bridge, node: *const Matrix) Error!Id {
        const text = node.text orelse return self.store.boolean(false);
        return self.store.boolean(std.mem.eql(u8, text, "true"));
    }

    fn trHole(self: *Bridge, node: *const Matrix) Error!Id {
        const text = node.text orelse return self.store.hole(0);
        if (text.len > 1 and text[0] == '_') {
            const idx = std.fmt.parseInt(u32, text[1..], 10) catch 0;
            return self.store.hole(idx);
        }
        return self.store.hole(0);
    }

    fn trBind(self: *Bridge, node: *const Matrix) Error!Id {
        const name_node = node.child(0) orelse return self.store.hole(0);
        const val_node = node.child(1) orelse return self.store.hole(0);
        const name = name_node.text orelse "?";
        const val = try self.translateOne(val_node);
        return self.store.bind(name, val);
    }

    fn trFn(self: *Bridge, node: *const Matrix) Error!Id {
        const name_node = node.child(0) orelse return self.store.hole(0);
        const name = name_node.text orelse "?";
        var params: std.ArrayListUnmanaged([]const u8) = .{};
        defer params.deinit(self.allocator);
        if (node.find(.param_list)) |plist| {
            for (plist.children) |*p| {
                if (p.text) |t| try params.append(self.allocator, t);
            }
        }
        const body_idx: usize = if (node.childCount() > 2) 2 else 1;
        const body_node = node.child(body_idx) orelse return self.store.hole(0);
        const body = try self.translateOne(body_node);
        const lam = try self.store.lambda(params.items, body);
        return self.store.bind(name, lam);
    }

    /// sig_decl: "fib : Int -> Int" or "fib : ℕ → ℕ"
    /// tree-sitter: [name] ":" [type]
    fn trSig(self: *Bridge, node: *const Matrix) Error!Id {
        // Find the name (first identifier child)
        var name: []const u8 = "?";
        var type_text: []const u8 = "?";
        var found_colon = false;
        for (node.children) |*child| {
            if (!found_colon) {
                if (child.kind == .identifier) {
                    name = child.text orelse "?";
                } else if (child.text != null and std.mem.eql(u8, child.text.?, ":")) {
                    found_colon = true;
                }
            } else {
                // Everything after ":" is the type
                if (child.text) |t| {
                    type_text = t;
                    break;
                }
            }
        }
        // Store as: sig(name, type_string)
        const name_id = try self.store.sym(name);
        const type_id = try self.store.sym(type_text);
        return self.store.relation("sig", &.{ name_id, type_id }, &.{});
    }
    /// eq_decl: "fib 0 = 0" or "fib n = fib (n-1) + fib (n-2)" or "double x ≔ add x x"
    /// tree-sitter: [name] [pattern]* ("=" | "≔" | "≡") [expr]
    fn trEq(self: *Bridge, node: *const Matrix) Error!Id {
        var name: []const u8 = "?";
        var patterns = std.ArrayListUnmanaged(Id){};
        defer patterns.deinit(self.allocator);
        var body: ?Id = null;
        var past_eq = false;

        for (node.children) |*child| {
            // Skip annotations, pub, total keywords
            if (child.text) |t| {
                if (std.mem.eql(u8, t, "pub") or std.mem.eql(u8, t, "total")) continue;
                if (std.mem.eql(u8, t, "=") or std.mem.eql(u8, t, "\xe2\x89\x94") or std.mem.eql(u8, t, "\xe2\x89\xa1")) {
                    past_eq = true;
                    continue;
                }
            }

            if (!past_eq) {
                // Before "=" — name and patterns
                if (child.kind == .identifier and std.mem.eql(u8, name, "?")) {
                    name = child.text orelse "?";
                } else if (child.kind == .identifier) {
                    // Pattern variable
                    try patterns.append(self.allocator, try self.store.sym(child.text orelse "_"));
                } else if (child.kind == .integer_literal) {
                    // Pattern literal
                    try patterns.append(self.allocator, try self.trInt(child));
                } else if (child.kind == .pattern) {
                    // Complex pattern
                    try patterns.append(self.allocator, try self.translateOne(child));
                } else {
                    // Other atoms as patterns
                    try patterns.append(self.allocator, try self.translateOne(child));
                }
            } else {
                // After "=" — body expression
                if (body == null) {
                    body = try self.translateOne(child);
                }
            }
        }

        const body_id = body orelse try self.store.unitLit();

        // If no patterns → simple binding: name = body
        if (patterns.items.len == 0) {
            return self.store.bind(name, body_id);
        }

        // With patterns → function clause: clause(name, [patterns], body)
        // Store as: clause(name, pat1, pat2, ..., body)
        var clause_args = std.ArrayListUnmanaged(Id){};
        defer clause_args.deinit(self.allocator);
        try clause_args.append(self.allocator, try self.store.sym(name));
        for (patterns.items) |p| {
            try clause_args.append(self.allocator, p);
        }
        try clause_args.append(self.allocator, body_id);
        return self.store.call("clause", clause_args.items);
    }

    fn trFact(self: *Bridge, node: *const Matrix) Error!Id {
        const head_node = node.child(0) orelse return self.store.hole(0);
        const head = head_node.text orelse "?";
        var args: std.ArrayListUnmanaged(Id) = .{};
        defer args.deinit(self.allocator);
        if (node.find(.arg_list)) |alist| {
            for (alist.children) |*a| {
                try args.append(self.allocator, try self.translateOne(a));
            }
        } else if (node.children.len > 1) {
            for (node.children[1..]) |*a| {
                try args.append(self.allocator, try self.translateOne(a));
            }
        }
        return self.store.relation(head, args.items, &.{});
    }

    fn trProve(self: *Bridge, node: *const Matrix) Error!Id {
        const lhs_node = node.child(0) orelse return self.store.hole(0);
        const rhs_node = node.child(1) orelse return self.store.hole(0);
        const lhs = try self.translateOne(lhs_node);
        const rhs = try self.translateOne(rhs_node);
        return self.store.relation("\xE2\x89\xA1", &.{ lhs, rhs }, &.{});
    }

    fn trApply(self: *Bridge, node: *const Matrix) Error!Id {
        const func_node = node.child(0) orelse return self.store.hole(0);
        const func_id = try self.translateOne(func_node);
        var args: std.ArrayListUnmanaged(Id) = .{};
        defer args.deinit(self.allocator);
        for (node.children[1..]) |*c| {
            if (c.kind == .arg_list) {
                for (c.children) |*a| try args.append(self.allocator, try self.translateOne(a));
            } else {
                try args.append(self.allocator, try self.translateOne(c));
            }
        }
        return self.store.apply(func_id, args.items);
    }

    fn trBinary(self: *Bridge, node: *const Matrix) Error!Id {
        if (node.childCount() < 3) return self.store.hole(0);
        const lhs = try self.translateOne(node.child(0).?);
        const op = node.child(1).?.text orelse "?";
        const rhs = try self.translateOne(node.child(2).?);
        return self.store.binop(op, lhs, rhs);
    }

    fn trUnary(self: *Bridge, node: *const Matrix) Error!Id {
        const op_node = node.child(0) orelse return self.store.hole(0);
        const op = op_node.text orelse "?";
        const operand = try self.translateOne(node.child(1) orelse return self.store.hole(0));
        const op_id = try self.store.sym(op);
        return self.store.apply(op_id, &.{operand});
    }

    fn trLambda(self: *Bridge, node: *const Matrix) Error!Id {
        var params: std.ArrayListUnmanaged([]const u8) = .{};
        defer params.deinit(self.allocator);
        if (node.find(.param_list)) |plist| {
            for (plist.children) |*p| {
                if (p.text) |t| try params.append(self.allocator, t);
            }
        }
        const body_node = node.child(node.childCount() - 1) orelse return self.store.hole(0);
        const body = try self.translateOne(body_node);
        return self.store.lambda(params.items, body);
    }

    fn trIf(self: *Bridge, node: *const Matrix) Error!Id {
        const cond = try self.translateOne(node.child(0) orelse return self.store.hole(0));
        const then_br = try self.translateOne(node.child(1) orelse return self.store.hole(0));
        const else_br = if (node.child(2)) |e| try self.translateOne(e) else try self.store.unitLit();
        return self.store.call("if", &.{ cond, then_br, else_br });
    }

    fn trAgg(self: *Bridge, node: *const Matrix, op: []const u8) Error!Id {
        if (node.childCount() < 4) return self.store.hole(0);
        const variable = node.child(0).?.text orelse "i";
        const lo = try self.translateOne(node.child(1).?);
        const hi = try self.translateOne(node.child(2).?);
        const body = try self.translateOne(node.child(3).?);
        return self.store.aggregate(op, variable, lo, hi, body);
    }
};

// ═══════════════════════════════════════════════════ // Tests // ═══════════════════════════════════════════════════

test "bridge — bind" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const tree = Matrix{
        .kind = .bind_decl,
        .text = null,
        .children = &.{
            .{ .kind = .identifier, .text = "x", .children = &.{} },
            .{ .kind = .integer_literal, .text = "42", .children = &.{} },
        },
    };

    var bridge = Bridge.init(&store, allocator);
    const id = try bridge.translateOne(&tree);
    const s = try expr.toString(&store, id, allocator);
    defer allocator.free(s);
    try std.testing.expectEqualStrings("x := 42", s);
}
