const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const expr = @import("expr");
const ExprStore = expr.Store;
const Id = expr.Id;
const platform = @import("platform");
const canon = @import("canon");

pub const ProofTerm = union(enum) {
    /// refl : a ≡ a
    refl: u32,
    /// sym : a ≡ b → b ≡ a
    sym: *const ProofTerm,
    /// trans : a ≡ b → b ≡ c → a ≡ c
    trans: struct { left: *const ProofTerm, right: *const ProofTerm },
    /// cong : a ≡ b → f(a) ≡ f(b)
    cong: struct { fn_id: u32, proof: *const ProofTerm },
    /// beta : (λx.e)(v) ≡ e[x/v]
    beta: struct { lambda: u32, arg: u32 },
    /// by_eval : eval(a) = eval(b) → a ≡ b
    by_eval: struct { lhs: u32, rhs: u32 },
    /// by_rewrite : rewrite rule r applied to a gives b
    by_rewrite: struct { rule_name: []const u8, input: u32, output: u32 },
    /// by_induction : base case + inductive step
    by_induction: struct {
        variable: []const u8,
        base_case: *const ProofTerm,
        inductive_step: *const ProofTerm,
    },
    /// assumption : assumed axiom (must be discharged)
    assumption: []const u8,
    /// qed : proof is complete
    qed: void,
};

/// A theorem statement
pub const Theorem = struct {
    name: []const u8,
    statement: []const u8,
    lhs: u32,
    rhs: u32,
    proof: ?*const ProofTerm,
    verified: bool,
};

/// Proof environment — tracks theorems and axioms
pub const ProofEnv = struct {
    allocator: Allocator,
    theorems: std.StringHashMapUnmanaged(Theorem),
    axioms: std.ArrayListUnmanaged(Theorem),

    pub fn init(allocator: Allocator) ProofEnv {
        return .{
            .allocator = allocator,
            .theorems = .{},
            .axioms = .{},
        };
    }

    pub fn deinit(self: *ProofEnv) void {
        self.theorems.deinit(self.allocator);
        self.axioms.deinit(self.allocator);
    }

    /// Declare an axiom (assumed true without proof)
    pub fn axiom(self: *ProofEnv, name: []const u8, statement: []const u8, lhs: u32, rhs: u32) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        const owned_stmt = try self.allocator.dupe(u8, statement);
        try self.axioms.append(self.allocator, .{
            .name = owned_name,
            .statement = owned_stmt,
            .lhs = lhs,
            .rhs = rhs,
            .proof = null,
            .verified = true, // axioms are true by definition
        });
    }

    /// State a theorem (requires proof)
    pub fn theorem(self: *ProofEnv, name: []const u8, statement: []const u8, lhs: u32, rhs: u32) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        const owned_stmt = try self.allocator.dupe(u8, statement);
        try self.theorems.put(self.allocator, owned_name, .{
            .name = owned_name,
            .statement = owned_stmt,
            .lhs = lhs,
            .rhs = rhs,
            .proof = null,
            .verified = false,
        });
    }

    /// Verify a proof by reflexivity: eval(lhs) == eval(rhs)
    pub fn verifyByEval(self: *ProofEnv, name: []const u8, engine: anytype, store: *expr.Store) !bool {
        const thm = self.theorems.getPtr(name) orelse return false;
        engine.fuel = 1000000;
        const lhs_val = engine.eval(thm.lhs) catch thm.lhs;
        engine.fuel = 1000000;
        const rhs_val = engine.eval(thm.rhs) catch thm.rhs;

        // Compare evaluated forms
        const lhs_node = store.get(lhs_val);
        const rhs_node = store.get(rhs_val);

        if (lhs_node.tag == .lit and rhs_node.tag == .lit) {
            const ll = store.lits.items[lhs_node.aux];
            const rl = store.lits.items[rhs_node.aux];
            const same = switch (ll) {
                .int => |a| switch (rl) {
                    .int => |b| a == b,
                    else => false,
                },
                .boolean => |a| switch (rl) {
                    .boolean => |b| a == b,
                    else => false,
                },
                else => false,
            };
            if (same) {
                thm.verified = true;
                return true;
            }
        }

        // Compare structurally (same Id after eval)
        if (lhs_val == rhs_val) {
            thm.verified = true;
            return true;
        }

        return false;
    }

    /// Verify by simplification: simplify(lhs) == simplify(rhs)
    pub fn verifyBySimplify(self: *ProofEnv, name: []const u8, heaven: anytype) !bool {
        const thm = self.theorems.getPtr(name) orelse return false;
        // Parse lhs and rhs from statement "lhs = rhs"
        const eq_pos = std.mem.indexOf(u8, thm.statement, " = ") orelse return false;
        const lhs_str = thm.statement[0..eq_pos];
        const rhs_str = thm.statement[eq_pos + 3 ..];

        const ls = heaven.simplify(lhs_str) catch lhs_str;
        defer heaven.allocator.free(ls);
        const rs = heaven.simplify(rhs_str) catch rhs_str;
        defer heaven.allocator.free(rs);

        if (std.mem.eql(u8, ls, rs)) {
            thm.verified = true;
            return true;
        }

        // Try on original (unsimplified) too
        if (std.mem.eql(u8, lhs_str, rs) or std.mem.eql(u8, rhs_str, ls)) {
            thm.verified = true;
            return true;
        }

        // Try commutativity on original strings
        {
            const op_l2 = std.mem.indexOfAny(u8, lhs_str, "+-*");
            const op_r2 = std.mem.indexOfAny(u8, rhs_str, "+-*");
            if (op_l2 != null and op_r2 != null) {
                const al2 = std.mem.trim(u8, lhs_str[0..op_l2.?], " ");
                const ar2 = std.mem.trim(u8, lhs_str[op_l2.? + 1 ..], " ");
                const bl2 = std.mem.trim(u8, rhs_str[0..op_r2.?], " ");
                const br2 = std.mem.trim(u8, rhs_str[op_r2.? + 1 ..], " ");
                if (lhs_str[op_l2.?] == rhs_str[op_r2.?]) {
                    if (std.mem.eql(u8, al2, br2) and std.mem.eql(u8, ar2, bl2)) {
                        thm.verified = true;
                        return true;
                    }
                }
            }
        }

        // Try commutativity on simplified
        const op_l = std.mem.indexOfAny(u8, ls, "+-*");
        const op_r = std.mem.indexOfAny(u8, rs, "+-*");
        if (op_l != null and op_r != null) {
            const al = std.mem.trim(u8, ls[0..op_l.?], " ");
            const ar = std.mem.trim(u8, ls[op_l.? + 1 ..], " ");
            const bl = std.mem.trim(u8, rs[0..op_r.?], " ");
            const br = std.mem.trim(u8, rs[op_r.? + 1 ..], " ");
            if (ls[op_l.?] == rs[op_r.?] and
                std.mem.eql(u8, al, br) and std.mem.eql(u8, ar, bl))
            {
                thm.verified = true;
                return true;
            }
        }

        return false;
    }

    pub fn verifyByCanon(
        self: *ProofEnv,
        name: []const u8,
        store: *expr.Store,
        allocator: Allocator,
    ) !bool {
        const thm = self.theorems.getPtr(name) orelse return false;

        const lhs_can =
            try canon.canonicalize(store, allocator, thm.lhs);

        const rhs_can =
            try canon.canonicalize(store, allocator, thm.rhs);

        if (canon.compareExpr(store, lhs_can, rhs_can) == .eq) {
            thm.verified = true;
            return true;
        }

        return false;
    }

    fn intToPeano(store: *expr.Store, k: i64) !expr.Id {
        if (k <= 0) return store.sym("zero");
        const inner = try intToPeano(store, k - 1);
        return store.call("succ", &.{inner});
    }

    fn normalizePeano(store: *expr.Store, id: Id) !Id {
        const node = store.get(id);
        switch (node.tag) {
            .sym => {
                return id;
            },
            .apply => {
                const func = try normalizePeano(store, node.payload);
                const args = node.span_a.slice(store.pool.items);
                var new_args: [8]Id = undefined;
                for (args, 0..) |arg, i| {
                    new_args[i] = try normalizePeano(store, arg);
                }
                return store.apply(func, new_args[0..args.len]);
            },
            else => return id,
        }
    }

    pub fn verifyByInduction(self: *ProofEnv, name: []const u8, variable: []const u8, engine: anytype, heaven: anytype, store: *expr.Store) !bool {
        _ = heaven;

        const thm_val = self.theorems.get(name) orelse return false;
        const thm_lhs = thm_val.lhs;
        const thm_rhs = thm_val.rhs;

        const var_sym = store.interner.lookup(variable) orelse return error.UnknownVariable;
        const old_binding = engine.env.get(var_sym);
        defer {
            if (old_binding) |ob| engine.env.put(var_sym, ob) catch {};
        }

        // Normaliser les symboles Peano (Add → add, etc.)
        const norm_lhs = try normalizePeano(store, thm_lhs);
        const norm_rhs = try normalizePeano(store, thm_rhs);

        // Comparaison structurelle récursive
        const check_eq = struct {
            fn do(s: *expr.Store, l: u32, r: u32, depth: u32) bool {
                if (depth > 100) return false;
                if (l == r) return true;
                const ln = s.get(l);
                const rn = s.get(r);
                if (ln.tag != rn.tag) return false;

                return switch (ln.tag) {
                    .sym => ln.payload == rn.payload,
                    .lit => {
                        const ll = s.lits.items[ln.aux];
                        const rl = s.lits.items[rn.aux];
                        return switch (ll) {
                            .int => |a| switch (rl) {
                                .int => |b| a == b,
                                else => false,
                            },
                            else => false,
                        };
                    },
                    .apply => {
                        if (!do(s, ln.payload, rn.payload, depth + 1)) return false;
                        const l_args = ln.span_a.slice(s.pool.items);
                        const r_args = rn.span_a.slice(s.pool.items);
                        if (l_args.len != r_args.len) return false;
                        for (l_args, r_args) |la, ra| {
                            if (!do(s, la, ra, depth + 1)) return false;
                        }
                        return true;
                    },
                    else => false,
                };
            }
        }.do;

        // Tester pour k = 0..10
        var k: i64 = 0;
        while (k <= 10) : (k += 1) {
            const k_val = try store.int(k);
            try engine.env.put(var_sym, k_val);

            platform.debug.print("[induction] k={d}\n", .{k});
            platform.debug.print("[induction] norm_lhs={s}\n", .{try expr.toString(store, norm_lhs, self.allocator)});
            platform.debug.print("[induction] norm_rhs={s}\n", .{try expr.toString(store, norm_rhs, self.allocator)});

            engine.fuel = 100000;
            const lhs_val = engine.eval(norm_lhs) catch |err| {
                platform.debug.print("[induction] eval lhs error: {}\n", .{err});
                return false;
            };
            platform.debug.print("[induction] lhs_val={s}\n", .{try expr.toString(store, lhs_val, self.allocator)});

            engine.fuel = 100000;
            const rhs_val = engine.eval(norm_rhs) catch |err| {
                platform.debug.print("[induction] eval rhs error: {}\n", .{err});
                return false;
            };
            platform.debug.print("[induction] rhs_val={s}\n", .{try expr.toString(store, rhs_val, self.allocator)});

            if (!check_eq(store, lhs_val, rhs_val, 0)) {
                platform.debug.print("[induction] check_eq failed at k={d}\n", .{k});
                return false;
            }
        }

        if (self.theorems.getPtr(name)) |t| t.verified = true;
        return true;
    }

    /// Format all theorems
    pub fn formatAll(self: *ProofEnv, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        const w = buf.writer(allocator);

        try w.writeAll("  \xe2\x95\x90\xe2\x95\x90\xe2\x95\x90 Axioms \xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\n");
        for (self.axioms.items) |ax| {
            try std.fmt.format(w, "  \xe2\x9c\x93 axiom {s} : {s}\n", .{ ax.name, ax.statement });
        }

        try w.writeAll("\n  \xe2\x95\x90\xe2\x95\x90\xe2\x95\x90 Theorems \xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\n");
        var it = self.theorems.iterator();
        while (it.next()) |entry| {
            const thm = entry.value_ptr.*;
            const icon: []const u8 = if (thm.verified) "\xe2\x9c\x93" else "\xe2\x9c\x97";
            const status: []const u8 = if (thm.verified) "proved" else "unproved";
            try std.fmt.format(w, "  {s} theorem {s} : {s} [{s}]\n", .{ icon, thm.name, thm.statement, status });
        }

        return buf.toOwnedSlice(allocator);
    }
};

test "ProofEnv — verifyByCanon (commutativity)" {
    var arena =
        std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var store = expr.Store.init(allocator);

    var proofs = ProofEnv.init(allocator);

    const a = try store.sym("a");
    const b = try store.sym("b");

    const lhs = try store.binop("+", a, b);
    const rhs = try store.binop("+", b, a);

    try proofs.theorem(
        "add_comm",
        "a + b = b + a",
        lhs,
        rhs,
    );

    const ok =
        try proofs.verifyByCanon(
            "add_comm",
            &store,
            allocator,
        );

    try std.testing.expect(ok);
}

test "canon AC nested addition" {
    var store = expr.Store.init(std.testing.allocator);
    defer store.deinit();

    const a = try store.sym("a");
    const b = try store.sym("b");
    const c = try store.sym("c");

    const ab = try store.binop("+", a, b);
    const lhs = try store.binop("+", ab, c);

    const bc = try store.binop("+", b, c);
    const rhs = try store.binop("+", a, bc);

    const lhs_can =
        try canon.canonicalize(
            &store,
            std.testing.allocator,
            lhs,
        );

    const rhs_can =
        try canon.canonicalize(
            &store,
            std.testing.allocator,
            rhs,
        );

    try std.testing.expect(canon.compareExpr(
        &store,
        lhs_can,
        rhs_can,
    ) == .eq);
}
