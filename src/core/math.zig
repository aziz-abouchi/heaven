//! Mathématiques symboliques pour Heaven
//! Extrait de heaven_expr.zig pour modularité
//! Contient : derive, integrate, solve, expand, plot

const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const engine_expr = @import("engine_expr");
const Engine = engine_expr.Engine;
const matrix_bridge_mod = @import("matrix_bridge");
const parse_mod = @import("parse");
const platform = @import("platform");

fn getIntFromId(store: *Store, id: Id) ?i64 {
    if (id >= store.len()) return null;
    const node = store.get(id);
    if (node.tag == .lit) {
        const lit = store.lits.items[node.aux];
        if (lit == .int) return lit.int;
    }
    return null;
}

pub const Math = struct {
    store: *Store,
    engine: *Engine,
    bridge: *matrix_bridge_mod.MatrixBridge,
    parser: *parse_mod.Parser,
    allocator: Allocator,

    pub fn init(store: *Store, engine: *Engine, bridge: *matrix_bridge_mod.MatrixBridge, parser: *parse_mod.Parser, allocator: Allocator) Math {
        return .{ .store = store, .engine = engine, .bridge = bridge, .parser = parser, .allocator = allocator };
    }

    pub fn deinit(self: *Math) void {
        _ = self;
        // Si Math alloue des ressources, libérez-les ici
    }

    // ─── Dérivation ───

    pub fn derive(self: *Math, expr_str: []const u8, variable: []const u8) ![]u8 {
        const id = try self.bridge.importExpr(expr_str);
        const var_id = try self.store.sym(variable);
        const result = try self.deriveExpr(id, var_id);
        const str = try expr.toStringInfix(self.store, result, self.allocator);
        return str;
    }

    fn deriveExpr(self: *Math, expr_id: Id, variable: Id) !Id {
        const node = self.store.get(expr_id);
        switch (node.tag) {
            .lit => return self.store.int(0),
            .sym => {
                if (std.mem.eql(u8, self.store.interner.resolve(node.payload), self.store.interner.resolve(variable))) {
                    return self.store.int(1);
                }
                return self.store.int(0);
            },
            .apply => {
                const p = self.store.pool.items;
                const args = node.span_a.slice(p);
                if (args.len < 1) return self.store.int(0);
                const op_node = self.store.get(node.payload);
                if (op_node.tag != .sym) return self.store.int(0);
                const op = self.store.interner.resolve(op_node.payload);
                if (std.mem.eql(u8, op, "+")) {
                    if (args.len != 2) return self.store.int(0);
                    const d1 = try self.deriveExpr(args[0], variable);
                    const d2 = try self.deriveExpr(args[1], variable);
                    return self.store.binop("+", d1, d2);
                }
                if (std.mem.eql(u8, op, "-")) {
                    if (args.len != 2) return self.store.int(0);
                    const d1 = try self.deriveExpr(args[0], variable);
                    const d2 = try self.deriveExpr(args[1], variable);
                    return self.store.binop("-", d1, d2);
                }
                if (std.mem.eql(u8, op, "*")) {
                    if (args.len != 2) return self.store.int(0);
                    // (f*g)' = f'g + fg'
                    const f = args[0];
                    const g = args[1];
                    const df = try self.deriveExpr(f, variable);
                    const dg = try self.deriveExpr(g, variable);
                    const fg = try self.store.binop("*", df, g);
                    const fdg = try self.store.binop("*", f, dg);
                    return self.store.binop("+", fg, fdg);
                }
                if (std.mem.eql(u8, op, "^")) {
                    if (args.len != 2) return self.store.int(0);
                    // (f^g)' = f^g * (g' * ln(f) + g * f'/f)
                    // Version simplifiée pour g constant
                    const base = args[0];
                    const exp = args[1];
                    const exp_node = self.store.get(exp);
                    if (exp_node.tag == .lit) {
                        const lit = self.store.lits.items[exp_node.aux];
                        if (lit == .int) {
                            const n = lit.int;
                            if (n == 0) return self.store.int(0);
                            const d_base = try self.deriveExpr(base, variable);
                            const exp_minus = try self.store.int(n - 1);
                            const base_pow = try self.store.binop("^", base, exp_minus);
                            const mul = try self.store.binop("*", d_base, base_pow);
                            return self.store.binop("*", try self.store.int(n), mul);
                        }
                    }
                    return self.store.int(0);
                }
                return self.store.int(0);
            },
            else => return self.store.int(0),
        }
    }

    fn normalizeUnicode(self: *Math, input: []const u8) ![]u8 {
        var buf = try self.allocator.alloc(u8, input.len * 2);
        var pos: usize = 0;
        var i: usize = 0;
        while (i < input.len and pos < buf.len - 4) {
            if (i + 1 < input.len and input[i] == 0xc2) {
                const c2 = input[i + 1];
                if (c2 == 0xb2) {
                    buf[pos] = '^';
                    buf[pos + 1] = '2';
                    pos += 2;
                    i += 2;
                    continue;
                }
                if (c2 == 0xb3) {
                    buf[pos] = '^';
                    buf[pos + 1] = '3';
                    pos += 2;
                    i += 2;
                    continue;
                }
                if (c2 == 0xb9) {
                    buf[pos] = '^';
                    buf[pos + 1] = '1';
                    pos += 2;
                    i += 2;
                    continue;
                }
                if (c2 == 0xb0) {
                    buf[pos] = '^';
                    buf[pos + 1] = '0';
                    pos += 2;
                    i += 2;
                    continue;
                }
            }
            if (i + 2 < input.len and input[i] == 0xe2 and input[i + 1] == 0x81) {
                const c3 = input[i + 2];
                if (c3 == 0xb0) {
                    buf[pos] = '^';
                    buf[pos + 1] = '0';
                    pos += 2;
                    i += 3;
                    continue;
                }
                if (c3 >= 0xb4 and c3 <= 0xb9) {
                    buf[pos] = '^';
                    buf[pos + 1] = '0' + (c3 - 0xb0);
                    pos += 2;
                    i += 3;
                    continue;
                }
            }
            buf[pos] = input[i];
            pos += 1;
            i += 1;
        }
        return self.allocator.realloc(buf, pos);
    }

    /// Convertit un AST (Id) en notation infix normalisée pour deriveStr
    fn idToInfix(self: *Math, id: Id) ![]u8 {
        const node = self.store.get(id);
        const pool = self.store.pool.items;
        switch (node.tag) {
            .lit => {
                const lit = self.store.lits.items[node.aux];
                switch (lit) {
                    .int => |v| return std.fmt.allocPrint(self.allocator, "{d}", .{v}),
                    .float => |v| return std.fmt.allocPrint(self.allocator, "{d}", .{v}),
                    else => return self.allocator.dupe(u8, "0"),
                }
            },
            .sym => return self.allocator.dupe(u8, self.store.interner.resolve(node.payload)),
            .apply => {
                const func_node = self.store.get(node.payload);
                if (func_node.tag != .sym) return self.allocator.dupe(u8, "?");
                const op = self.store.interner.resolve(func_node.payload);
                const args = node.span_a.slice(pool);
                if (args.len == 2) {
                    const lhs = try self.idToInfix(args[0]);
                    defer self.allocator.free(lhs);
                    const rhs = try self.idToInfix(args[1]);
                    defer self.allocator.free(rhs);
                    // Mapper les noms internes vers infix
                    const infix_op = blk: {
                        if (std.mem.eql(u8, op, "add") or std.mem.eql(u8, op, "+")) break :blk "+";
                        if (std.mem.eql(u8, op, "sub") or std.mem.eql(u8, op, "-")) break :blk "-";
                        if (std.mem.eql(u8, op, "mul") or std.mem.eql(u8, op, "*")) break :blk "*";
                        if (std.mem.eql(u8, op, "div") or std.mem.eql(u8, op, "/")) break :blk "/";
                        if (std.mem.eql(u8, op, "pow") or std.mem.eql(u8, op, "^")) break :blk "^";
                        break :blk op;
                    };
                    return std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{ lhs, infix_op, rhs });
                }
                if (args.len == 1) {
                    const arg = try self.idToInfix(args[0]);
                    defer self.allocator.free(arg);
                    return std.fmt.allocPrint(self.allocator, "{s}({s})", .{ op, arg });
                }
                return self.allocator.dupe(u8, "?");
            },
            else => return self.allocator.dupe(u8, "?"),
        }
    }

    pub fn deriveStr(self: *Math, input: []const u8, v: []const u8) ![]u8 {
        const trimmed = std.mem.trim(u8, input, " ");
        if (trimmed.len == 0) return self.allocator.dupe(u8, "0");

        // Constante numérique
        if (std.fmt.parseInt(i64, trimmed, 10)) |_| {
            return self.allocator.dupe(u8, "0");
        } else |_| {}

        // Variable ou symbole simple
        var all_alpha = true;
        for (trimmed) |ch| {
            if (!std.ascii.isAlphabetic(ch) and ch != '_') {
                all_alpha = false;
                break;
            }
        }
        if (all_alpha and trimmed.len > 0) {
            if (std.mem.eql(u8, trimmed, v)) return self.allocator.dupe(u8, "1");
            return self.allocator.dupe(u8, "0");
        }

        // Parenthèses
        if (trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')') {
            return self.deriveStr(trimmed[1 .. trimmed.len - 1], v);
        }

        // Trouver opérateur principal
        var depth: i32 = 0;
        var last_add: ?usize = null;
        var last_add_op: u8 = '+';
        var last_mul: ?usize = null;
        var last_div: ?usize = null;
        var last_pow: ?usize = null;
        for (trimmed, 0..) |ch, idx| {
            switch (ch) {
                '(' => depth += 1,
                ')' => depth -= 1,
                '+' => if (depth == 0 and idx > 0) {
                    last_add = idx;
                    last_add_op = '+';
                },
                '-' => if (depth == 0 and idx > 0 and trimmed[idx - 1] != '(' and trimmed[idx - 1] != ',') {
                    last_add = idx;
                    last_add_op = '-';
                },
                '*' => if (depth == 0 and idx > 0) {
                    last_mul = idx;
                },
                '/' => if (depth == 0 and idx > 0) {
                    last_div = idx;
                },
                '^' => if (depth == 0 and idx > 0) {
                    last_pow = idx;
                },
                else => {},
            }
        }

        // + ou -
        if (last_add) |idx| {
            const lhs = std.mem.trim(u8, trimmed[0..idx], " ");
            const rhs = std.mem.trim(u8, trimmed[idx + 1 ..], " ");
            const dl = try self.deriveStr(lhs, v);
            defer self.allocator.free(dl);
            const dr = try self.deriveStr(rhs, v);
            defer self.allocator.free(dr);
            if (std.mem.eql(u8, dl, "0") and std.mem.eql(u8, dr, "0")) return self.allocator.dupe(u8, "0");
            if (std.mem.eql(u8, dl, "0")) {
                if (last_add_op == '-') return std.fmt.allocPrint(self.allocator, "0 - {s}", .{dr});
                return self.allocator.dupe(u8, dr);
            }
            if (std.mem.eql(u8, dr, "0")) return self.allocator.dupe(u8, dl);
            return std.fmt.allocPrint(self.allocator, "{s} {c} {s}", .{ dl, last_add_op, dr });
        }

        // *
        if (last_mul) |idx| {
            const lhs = std.mem.trim(u8, trimmed[0..idx], " ");
            const rhs = std.mem.trim(u8, trimmed[idx + 1 ..], " ");
            const dl = try self.deriveStr(lhs, v);
            defer self.allocator.free(dl);
            const dr = try self.deriveStr(rhs, v);
            defer self.allocator.free(dr);
            const dl_zero = std.mem.eql(u8, dl, "0");
            const dr_zero = std.mem.eql(u8, dr, "0");
            const dl_one = std.mem.eql(u8, dl, "1");
            const dr_one = std.mem.eql(u8, dr, "1");
            if (dl_zero and dr_zero) return self.allocator.dupe(u8, "0");
            if (dl_zero) {
                if (dr_one) return self.allocator.dupe(u8, lhs);
                return std.fmt.allocPrint(self.allocator, "{s} * {s}", .{ lhs, dr });
            }
            if (dr_zero) {
                if (dl_one) return self.allocator.dupe(u8, rhs);
                return std.fmt.allocPrint(self.allocator, "{s} * {s}", .{ dl, rhs });
            }
            var left: []u8 = undefined;
            if (dl_one) {
                left = try self.allocator.dupe(u8, rhs);
            } else {
                left = try std.fmt.allocPrint(self.allocator, "{s} * {s}", .{ dl, rhs });
            }
            defer self.allocator.free(left);
            var right: []u8 = undefined;
            if (dr_one) {
                right = try self.allocator.dupe(u8, lhs);
            } else {
                right = try std.fmt.allocPrint(self.allocator, "{s} * {s}", .{ lhs, dr });
            }
            defer self.allocator.free(right);
            return std.fmt.allocPrint(self.allocator, "{s} + {s}", .{ left, right });
        }

        // /
        if (last_div) |idx| {
            const lhs = std.mem.trim(u8, trimmed[0..idx], " ");
            const rhs = std.mem.trim(u8, trimmed[idx + 1 ..], " ");
            const dl = try self.deriveStr(lhs, v);
            defer self.allocator.free(dl);
            const dr = try self.deriveStr(rhs, v);
            defer self.allocator.free(dr);
            if (std.mem.eql(u8, dr, "0")) {
                if (std.mem.eql(u8, dl, "0")) return self.allocator.dupe(u8, "0");
                return std.fmt.allocPrint(self.allocator, "({s}) / {s}", .{ dl, rhs });
            }
            return std.fmt.allocPrint(self.allocator, "(({s}) * {s} - ({s}) * ({s})) / ({s}) ^ 2", .{ dl, rhs, lhs, dr, rhs });
        }

        // ^
        if (last_pow) |idx| {
            const base = std.mem.trim(u8, trimmed[0..idx], " ");
            const exp_str = std.mem.trim(u8, trimmed[idx + 1 ..], " ");
            if (std.fmt.parseInt(i64, exp_str, 10)) |n| {
                if (std.mem.eql(u8, base, v)) {
                    if (n == 2) return std.fmt.allocPrint(self.allocator, "{d} * {s}", .{ n, base });
                    return std.fmt.allocPrint(self.allocator, "{d} * {s} ^ {d}", .{ n, base, n - 1 });
                }
            } else |_| {}
            return self.allocator.dupe(u8, "0");
        }

        return self.allocator.dupe(u8, "0");
    }

    // ─── Intégration ───

    pub fn integrate(self: *Math, expr_str: []const u8, variable: []const u8) ![]u8 {
        const id = try self.bridge.importExpr(expr_str);
        const var_id = try self.store.sym(variable);
        const result = try self.integrateExpr(id, var_id);
        const str = try expr.toStringInfix(self.store, result, self.allocator);
        return try std.fmt.allocPrint(self.allocator, "{s} + C", .{str});
    }

    fn integrateExpr(self: *Math, expr_id: Id, variable: Id) !Id {
        const node = self.store.get(expr_id);
        switch (node.tag) {
            .lit => {
                const lit = self.store.lits.items[node.aux];
                if (lit == .int) {
                    // ∫ a dx = a*x
                    const x = try self.store.sym(self.store.interner.resolve(variable));
                    return self.store.binop("*", expr_id, x);
                }
                return self.store.int(0);
            },
            .sym => {
                const var_node = self.store.get(variable);
                const var_sym = var_node.payload; // Le Sym du nœud
                if (std.mem.eql(u8, self.store.interner.resolve(node.payload), self.store.interner.resolve(var_sym))) {
                    // ∫ x dx = x^2/2
                    const two = try self.store.int(2);
                    const x_sq = try self.store.binop("^", expr_id, two);
                    return self.store.binop("/", x_sq, two);
                }
                return self.store.binop("*", expr_id, try self.store.sym(self.store.interner.resolve(var_sym)));
            },
            .apply => {
                const p = self.store.pool.items;
                const args = node.span_a.slice(p);
                if (args.len < 1) return self.store.int(0);
                const op_node = self.store.get(node.payload);
                if (op_node.tag != .sym) return self.store.int(0);
                const op = self.store.interner.resolve(op_node.payload);
                if (std.mem.eql(u8, op, "+")) {
                    var result: Id = 0;
                    for (args) |arg| {
                        const integ = try self.integrateExpr(arg, variable);
                        if (result == 0) {
                            result = integ;
                        } else result = try self.store.binop("+", result, integ);
                    }
                    return result;
                }
                if (std.mem.eql(u8, op, "-")) {
                    if (args.len != 2) return self.store.int(0);
                    const in1 = try self.integrateExpr(args[0], variable);
                    const in2 = try self.integrateExpr(args[1], variable);
                    return self.store.binop("-", in1, in2);
                }
                if (std.mem.eql(u8, op, "*")) {
                    // Version simplifiée : si un facteur est constant, on l'intègre avec l'autre
                    // Sinon, on retourne 0.
                    if (args.len != 2) return self.store.int(0);
                    const a_node = self.store.get(args[0]);
                    const b_node = self.store.get(args[1]);
                    if (a_node.tag == .lit and b_node.tag == .lit) {
                        return self.store.binop("*", args[0], args[1]);
                    }
                    // Si a est constant
                    if (a_node.tag == .lit) {
                        const integ_b = try self.integrateExpr(args[1], variable);
                        return self.store.binop("*", args[0], integ_b);
                    }
                    if (b_node.tag == .lit) {
                        const integ_a = try self.integrateExpr(args[0], variable);
                        return self.store.binop("*", integ_a, args[1]);
                    }
                    // Cas x^n
                    if (a_node.tag == .sym) {
                        const name_a = self.store.interner.resolve(a_node.payload);
                        if (std.mem.eql(u8, name_a, self.store.interner.resolve(variable))) {
                            // ∫ x * f(x) dx
                        }
                    }
                    return self.store.int(0);
                }
                if (std.mem.eql(u8, op, "^")) {
                    if (args.len != 2) return self.store.int(0);
                    const base = args[0];
                    const exp = args[1];
                    const exp_node = self.store.get(exp);
                    if (exp_node.tag == .lit) {
                        const lit = self.store.lits.items[exp_node.aux];
                        if (lit == .int) {
                            const n = lit.int;
                            if (n == -1) {
                                // ∫ x^{-1} dx = ln(x)
                                return self.store.sym("ln");
                            }
                            const new_n = try self.store.int(n + 1);
                            const new_pow = try self.store.binop("^", base, new_n);
                            return self.store.binop("/", new_pow, new_n);
                        }
                    }
                    return self.store.int(0);
                }
                return self.store.int(0);
            },
            else => return self.store.int(0),
        }
    }

    // ─── Résolution d'équations ───

    pub fn solve(self: *Math, input: []const u8, varname: []const u8) ![]u8 {
        const id = blk: {
            if (self.parser.parseSExpr(input)) |parsed| break :blk parsed else |_| {}
            break :blk try self.bridge.importExpr(input);
        };
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(self.allocator);
        var a: i64 = 0;
        var b: i64 = 0;
        var constant: i64 = 0;
        self.collectCoeffs(id, varname, &a, &b, &constant);
        if (a == 0 and b == 0) {
            if (constant == 0) {
                try buf.appendSlice(self.allocator, "tout x (identite)");
            } else {
                try buf.appendSlice(self.allocator, "aucune solution");
            }
        } else if (a == 0) {
            const num = -constant;
            const den = b;
            if (@rem(num, den) == 0) {
                var tmp: [64]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{s} = {d}", .{ varname, @divTrunc(num, den) }) catch "?";
                try buf.appendSlice(self.allocator, s);
            } else {
                var tmp: [64]u8 = undefined;
                const s = std.fmt.bufPrint(&tmp, "{s} = {d}/{d}", .{ varname, num, den }) catch "?";
                try buf.appendSlice(self.allocator, s);
            }
        } else {
            const disc = b * b - 4 * a * constant;
            if (disc < 0) {
                try buf.appendSlice(self.allocator, "aucune solution reelle (discriminant < 0)");
            } else if (disc == 0) {
                const num = -b;
                const den = 2 * a;
                var tmp: [64]u8 = undefined;
                if (@rem(num, den) == 0) {
                    const s = std.fmt.bufPrint(&tmp, "{s} = {d} (racine double)", .{ varname, @divTrunc(num, den) }) catch "?";
                    try buf.appendSlice(self.allocator, s);
                } else {
                    const s = std.fmt.bufPrint(&tmp, "{s} = {d}/{d} (racine double)", .{ varname, num, den }) catch "?";
                    try buf.appendSlice(self.allocator, s);
                }
            } else {
                const sqrt_disc = intSqrt(disc);
                var tmp: [128]u8 = undefined;
                if (sqrt_disc * sqrt_disc == disc) {
                    const x1_num = -b + sqrt_disc;
                    const x2_num = -b - sqrt_disc;
                    const den = 2 * a;
                    if (@rem(x1_num, den) == 0 and @rem(x2_num, den) == 0) {
                        const s = std.fmt.bufPrint(&tmp, "{s} = {d}  ou  {s} = {d}", .{ varname, @divTrunc(x1_num, den), varname, @divTrunc(x2_num, den) }) catch "?";
                        try buf.appendSlice(self.allocator, s);
                    } else {
                        const s = std.fmt.bufPrint(&tmp, "{s} = ({d}+sqrt({d}))/{d}  ou  {s} = ({d}-sqrt({d}))/{d}", .{ varname, -b, disc, den, varname, -b, disc, den }) catch "?";
                        try buf.appendSlice(self.allocator, s);
                    }
                } else {
                    const s = std.fmt.bufPrint(&tmp, "{s} = ({d}+sqrt({d}))/{d}  ou  {s} = ({d}-sqrt({d}))/{d}", .{ varname, -b, disc, 2 * a, varname, -b, disc, 2 * a }) catch "?";
                    try buf.appendSlice(self.allocator, s);
                }
            }
        }
        return buf.toOwnedSlice(self.allocator);
    }

    fn collectCoeffs(self: *Math, id: Id, v: []const u8, a: *i64, b: *i64, c: *i64) void {
        if (id >= self.store.len()) return;
        const node = self.store.get(id);
        switch (node.tag) {
            .lit => {
                const l = self.store.lits.items[node.aux];
                switch (l) {
                    .int => |val| c.* += val,
                    else => {},
                }
            },
            .sym => {
                const name = self.store.interner.resolve(node.payload);
                if (std.mem.eql(u8, name, v)) b.* += 1;
            },
            .apply => {
                const func_node = self.store.get(node.payload);
                if (func_node.tag != .sym) return;
                const op = self.store.interner.resolve(func_node.payload);
                const args = node.span_a.slice(self.store.pool.items);
                if (args.len != 2) return;
                if (std.mem.eql(u8, op, "+")) {
                    self.collectCoeffs(args[0], v, a, b, c);
                    self.collectCoeffs(args[1], v, a, b, c);
                } else if (std.mem.eql(u8, op, "-")) {
                    self.collectCoeffs(args[0], v, a, b, c);
                    var a2: i64 = 0;
                    var b2: i64 = 0;
                    var c2: i64 = 0;
                    self.collectCoeffs(args[1], v, &a2, &b2, &c2);
                    a.* -= a2;
                    b.* -= b2;
                    c.* -= c2;
                } else if (std.mem.eql(u8, op, "*")) {
                    const n0 = self.store.get(args[0]);
                    const n1 = self.store.get(args[1]);
                    if (n0.tag == .lit and n1.tag == .sym) {
                        const k = self.store.lits.items[n0.aux];
                        const name = self.store.interner.resolve(n1.payload);
                        if (std.mem.eql(u8, name, v)) {
                            switch (k) {
                                .int => |val| b.* += val,
                                else => {},
                            }
                        } else {
                            switch (k) {
                                .int => |val| c.* += val,
                                else => {},
                            }
                        }
                    } else if (n1.tag == .lit and n0.tag == .sym) {
                        const k = self.store.lits.items[n1.aux];
                        const name = self.store.interner.resolve(n0.payload);
                        if (std.mem.eql(u8, name, v)) {
                            switch (k) {
                                .int => |val| b.* += val,
                                else => {},
                            }
                        }
                    } else if (n0.tag == .lit) {
                        const k = self.store.lits.items[n0.aux];
                        var sa: i64 = 0;
                        var sb: i64 = 0;
                        var sc: i64 = 0;
                        self.collectCoeffs(args[1], v, &sa, &sb, &sc);
                        switch (k) {
                            .int => |val| {
                                a.* += sa * val;
                                b.* += sb * val;
                                c.* += sc * val;
                            },
                            else => {},
                        }
                    }
                } else if (std.mem.eql(u8, op, "^")) {
                    const base = self.store.get(args[0]);
                    const exp_node = self.store.get(args[1]);
                    if (base.tag == .sym and exp_node.tag == .lit) {
                        const name = self.store.interner.resolve(base.payload);
                        if (std.mem.eql(u8, name, v)) {
                            const e = self.store.lits.items[exp_node.aux];
                            switch (e) {
                                .int => |val| {
                                    if (val == 2) a.* += 1 else if (val == 1) b.* += 1 else if (val == 0) c.* += 1;
                                },
                                else => {},
                            }
                        }
                    }
                }
            },
            else => {},
        }
    }

    fn intSqrt(n: i64) i64 {
        if (n <= 0) return 0;
        var x: i64 = 1;
        while (x * x <= n) : (x += 1) {}
        return x - 1;
    }

    // ─── Expansion ───

    pub fn expand(self: *Math, input: []const u8) ![]u8 {
        const id = blk: {
            if (self.parser.parseSExpr(input)) |parsed| break :blk parsed else |_| {}
            break :blk try self.bridge.importExpr(input);
        };
        const expanded = try self.expandExpr(id);
        const simplified = try self.simplifyMath(expanded);
        return expr.toString(self.store, simplified, self.allocator);
    }

    pub fn simplify(self: *Math, input: []const u8) ![]u8 {
        platform.debug.print("[core math SIMPLIFY] kb.rules.len = {d}\n", .{self.kb.rules.items.len});
        const id = try self.bridge.importExpr(input);
        const simplified = try self.simplifyMath(id);
        return expr.toString(self.store, simplified, self.allocator);
    }

    /// Simplification mathématique basique pour expressions développées
    pub fn simplifyMath(self: *Math, id: Id) !Id {
        if (id >= self.store.len()) return id;
        const node = self.store.get(id);
        switch (node.tag) {
            .lit, .sym => return id,
            .apply => {
                const func_node = self.store.get(node.payload);
                if (func_node.tag != .sym) return id;
                const op = self.store.interner.resolve(func_node.payload);
                const p = self.store.pool.items;
                const args = node.span_a.slice(p);
                if (args.len != 2) return id;

                const left = try self.simplifyMath(args[0]);
                const right = try self.simplifyMath(args[1]);

                const li = getIntFromId(self.store, left);
                const ri = getIntFromId(self.store, right);

                platform.debug.print("simplifyMath: op={s}, left={d}, right={d}, li={any}, ri={any}\n", .{ op, left, right, li, ri });

                // Vérification directe de 0 et 1
                const left_is_zero = blk: {
                    if (left >= self.store.len()) break :blk false;
                    const nd = self.store.get(left);
                    if (nd.tag != .lit) break :blk false;
                    if (nd.aux >= self.store.lits.items.len) break :blk false;
                    const lit = self.store.lits.items[nd.aux];
                    break :blk (lit == .int and lit.int == 0);
                };
                const right_is_zero = blk: {
                    if (right >= self.store.len()) break :blk false;
                    const nd = self.store.get(right);
                    if (nd.tag != .lit) break :blk false;
                    if (nd.aux >= self.store.lits.items.len) break :blk false;
                    const lit = self.store.lits.items[nd.aux];
                    break :blk (lit == .int and lit.int == 0);
                };
                const left_is_one = blk: {
                    if (left >= self.store.len()) break :blk false;
                    const nd = self.store.get(left);
                    if (nd.tag != .lit) break :blk false;
                    if (nd.aux >= self.store.lits.items.len) break :blk false;
                    const lit = self.store.lits.items[nd.aux];
                    break :blk (lit == .int and lit.int == 1);
                };
                const right_is_one = blk: {
                    if (right >= self.store.len()) break :blk false;
                    const nd = self.store.get(right);
                    if (nd.tag != .lit) break :blk false;
                    if (nd.aux >= self.store.lits.items.len) break :blk false;
                    const lit = self.store.lits.items[nd.aux];
                    break :blk (lit == .int and lit.int == 1);
                };

                platform.debug.print("simplifyMath: left_is_zero={}, right_is_zero={}, left_is_one={}, right_is_one={}\n", .{ left_is_zero, right_is_zero, left_is_one, right_is_one });

                // Normalisation des opérateurs
                const op_norm = blk: {
                    if (std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "add")) break :blk "+";
                    if (std.mem.eql(u8, op, "-") or std.mem.eql(u8, op, "sub")) break :blk "-";
                    if (std.mem.eql(u8, op, "*") or std.mem.eql(u8, op, "mul")) break :blk "*";
                    if (std.mem.eql(u8, op, "/") or std.mem.eql(u8, op, "div")) break :blk "/";
                    if (std.mem.eql(u8, op, "^") or std.mem.eql(u8, op, "pow")) break :blk "^";
                    break :blk op;
                };

                if (std.mem.eql(u8, op_norm, "+")) {
                    if (left_is_zero) return right;
                    if (right_is_zero) return left;
                    if (li != null and ri != null) return self.store.int(li.? + ri.?);
                    return self.store.binop("+", left, right);
                }

                if (std.mem.eql(u8, op_norm, "*")) {
                    if (left_is_zero or right_is_zero) return self.store.int(0);
                    if (left_is_one) return right;
                    if (right_is_one) return left;
                    if (li != null and ri != null) return self.store.int(li.? * ri.?);
                    return self.store.binop("*", left, right);
                }

                return self.store.binop(op, left, right);
            },
            else => return id,
        }
    }

    fn expandExpr(self: *Math, id: Id) !Id {
        if (id >= self.store.len()) return id;
        const node = self.store.get(id);
        if (node.tag != .apply) return id;
        const func_node = self.store.get(node.payload);
        if (func_node.tag != .sym) return id;
        const op = self.store.interner.resolve(func_node.payload);
        const args = node.span_a.slice(self.store.pool.items);
        if (args.len != 2) return id;
        const a0 = args[0];
        const a1 = args[1];
        if (std.mem.eql(u8, op, "*")) {
            const left = try self.expandExpr(a0);
            const right = try self.expandExpr(a1);
            if (left < self.store.len()) {
                const ln = self.store.get(left);
                if (ln.tag == .apply) {
                    const lf = self.store.get(ln.payload);
                    if (lf.tag == .sym and std.mem.eql(u8, self.store.interner.resolve(lf.payload), "+")) {
                        const la = ln.span_a.slice(self.store.pool.items);
                        if (la.len == 2) {
                            const la0 = la[0];
                            const la1 = la[1];
                            if (right < self.store.len()) {
                                const rn = self.store.get(right);
                                if (rn.tag == .apply) {
                                    const rf = self.store.get(rn.payload);
                                    if (rf.tag == .sym and std.mem.eql(u8, self.store.interner.resolve(rf.payload), "+")) {
                                        const ra = rn.span_a.slice(self.store.pool.items);
                                        if (ra.len == 2) {
                                            const ra0 = ra[0];
                                            const ra1 = ra[1];
                                            const ac = try self.store.binop("*", la0, ra0);
                                            const ad = try self.store.binop("*", la0, ra1);
                                            const bc = try self.store.binop("*", la1, ra0);
                                            const bd = try self.store.binop("*", la1, ra1);
                                            const t1 = try self.store.binop("+", ac, ad);
                                            const t2 = try self.store.binop("+", bc, bd);
                                            return self.store.binop("+", t1, t2);
                                        }
                                    }
                                }
                            }
                            const t1 = try self.store.binop("*", la0, right);
                            const t2 = try self.store.binop("*", la1, right);
                            return self.store.binop("+", t1, t2);
                        }
                    }
                }
            }
            if (right < self.store.len()) {
                const rn = self.store.get(right);
                if (rn.tag == .apply) {
                    const rf = self.store.get(rn.payload);
                    if (rf.tag == .sym and std.mem.eql(u8, self.store.interner.resolve(rf.payload), "+")) {
                        const ra = rn.span_a.slice(self.store.pool.items);
                        if (ra.len == 2) {
                            const ra0 = ra[0];
                            const ra1 = ra[1];
                            const t1 = try self.store.binop("*", left, ra0);
                            const t2 = try self.store.binop("*", left, ra1);
                            return self.store.binop("+", t1, t2);
                        }
                    }
                }
            }
            return self.store.binop("*", left, right);
        }
        if (std.mem.eql(u8, op, "^")) {
            const base_node = self.store.get(a0);
            const exp_node = self.store.get(a1);
            if (exp_node.tag == .lit and base_node.tag == .apply) {
                const e = self.store.lits.items[exp_node.aux];
                switch (e) {
                    .int => |val| {
                        if (val >= 2 and val <= 12) {
                            const bf = self.store.get(base_node.payload);
                            if (bf.tag == .sym and std.mem.eql(u8, self.store.interner.resolve(bf.payload), "+")) {
                                const ba = base_node.span_a.slice(self.store.pool.items);
                                if (ba.len == 2) {
                                    const ba0 = ba[0];
                                    const ba1 = ba[1];
                                    // Développement binomial direct: Σ C(n,k) * a^(n-k) * b^k
                                    const n = @as(usize, @intCast(val));
                                    // Coefficients binomiaux C(n,k)
                                    var coeffs: [13]i64 = undefined;
                                    coeffs[0] = 1;
                                    for (1..n + 1) |k| {
                                        coeffs[k] = @divExact(coeffs[k - 1] * @as(i64, @intCast(n - k + 1)), @as(i64, @intCast(k)));
                                    }
                                    // Construire la somme terme par terme
                                    var result: ?Id = null;
                                    for (0..n + 1) |k| {
                                        const c = coeffs[k];
                                        const exp_a = n - k;
                                        const exp_b = k;
                                        // Construire coeff * a^exp_a * b^exp_b
                                        var term: Id = undefined;
                                        if (exp_a == 0 and exp_b == 0) {
                                            term = try self.store.int(c);
                                        } else if (exp_a == 0) {
                                            const bp = if (exp_b == 1) ba1 else try self.store.binop("^", ba1, try self.store.int(@as(i64, @intCast(exp_b))));
                                            term = if (c == 1) bp else try self.store.binop("*", try self.store.int(c), bp);
                                        } else if (exp_b == 0) {
                                            const ap = if (exp_a == 1) ba0 else try self.store.binop("^", ba0, try self.store.int(@as(i64, @intCast(exp_a))));
                                            term = if (c == 1) ap else try self.store.binop("*", try self.store.int(c), ap);
                                        } else {
                                            const ap = if (exp_a == 1) ba0 else try self.store.binop("^", ba0, try self.store.int(@as(i64, @intCast(exp_a))));
                                            const bp = if (exp_b == 1) ba1 else try self.store.binop("^", ba1, try self.store.int(@as(i64, @intCast(exp_b))));
                                            const ab = try self.store.binop("*", ap, bp);
                                            term = if (c == 1) ab else try self.store.binop("*", try self.store.int(c), ab);
                                        }
                                        result = if (result) |r| try self.store.binop("+", r, term) else term;
                                    }
                                    return result orelse id;
                                }
                            }
                        }
                    },
                    else => {},
                }
            }
        }
        if (std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "-")) {
            const left = try self.expandExpr(a0);
            const right = try self.expandExpr(a1);
            return self.store.binop(op, left, right);
        }
        return id;
    }

    // ─── Plot ASCII ───

    pub fn plot(self: *Math, input: []const u8, varname: []const u8) ![]u8 {
        const id = try self.bridge.importExpr(input);
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(self.allocator);
        const width: usize = 60;
        const height: usize = 20;
        var values: [60]f64 = undefined;
        var min_val: f64 = std.math.floatMax(f64);
        var max_val: f64 = -std.math.floatMax(f64);
        const var_sym = try self.store.interner.intern(varname);
        for (0..width) |i| {
            const x_f: f64 = -10.0 + @as(f64, @floatFromInt(i)) * 20.0 / @as(f64, @floatFromInt(width));
            const x_int: i64 = @intFromFloat(x_f);
            const x_id = try self.store.int(x_int);
            const old_binding = self.engine.env.get(var_sym);
            try self.engine.env.put(var_sym, x_id);
            self.engine.fuel = 200;
            const result = engine_expr.evaluate(self.store, self.engine.env, self.engine, id, 0) catch {
                values[i] = 0;
                if (old_binding) |ob| self.engine.env.put(var_sym, ob) catch {} else {}
                continue;
            };
            if (old_binding) |ob| try self.engine.env.put(var_sym, ob) else {}
            const rn = self.store.get(result);
            if (rn.tag == .lit) {
                const l = self.store.lits.items[rn.aux];
                switch (l) {
                    .int => |v| {
                        values[i] = @floatFromInt(v);
                    },
                    .float => |v| {
                        values[i] = v;
                    },
                    else => {
                        values[i] = 0;
                    },
                }
            } else {
                values[i] = 0;
            }
            if (values[i] < min_val) min_val = values[i];
            if (values[i] > max_val) max_val = values[i];
        }
        if (max_val == min_val) max_val = min_val + 1;
        var grid: [20][60]u8 = undefined;
        for (&grid) |*row| @memset(row, ' ');
        const zero_row_f = (0 - min_val) / (max_val - min_val) * @as(f64, @floatFromInt(height - 1));
        const zero_row: usize = if (zero_row_f >= 0 and zero_row_f < @as(f64, @floatFromInt(height))) height - 1 - @as(usize, @intFromFloat(zero_row_f)) else height;
        if (zero_row < height) {
            for (&grid[zero_row]) |*ch| ch.* = '-';
        }
        for (0..width) |i| {
            const norm = (values[i] - min_val) / (max_val - min_val);
            const row_f = norm * @as(f64, @floatFromInt(height - 1));
            if (row_f >= 0 and row_f < @as(f64, @floatFromInt(height))) {
                const row: usize = height - 1 - @as(usize, @intFromFloat(row_f));
                grid[row][i] = '*';
            }
        }
        var tmp: [64]u8 = undefined;
        const max_s = std.fmt.bufPrint(&tmp, "{d:.0}", .{max_val}) catch "?";
        try buf.appendSlice(self.allocator, max_s);
        try buf.appendSlice(self.allocator, " |\n");
        for (grid) |row| {
            try buf.appendSlice(self.allocator, "     |");
            try buf.appendSlice(self.allocator, &row);
            try buf.append(self.allocator, '\n');
        }
        const min_s = std.fmt.bufPrint(&tmp, "{d:.0}", .{min_val}) catch "?";
        try buf.appendSlice(self.allocator, min_s);
        try buf.appendSlice(self.allocator, " |");
        for (0..width) |_| try buf.append(self.allocator, '_');
        try buf.append(self.allocator, '\n');
        try buf.appendSlice(self.allocator, "      -10");
        for (0..width - 19) |_| try buf.append(self.allocator, ' ');
        try buf.appendSlice(self.allocator, "10\n");
        return buf.toOwnedSlice(self.allocator);
    }
};
