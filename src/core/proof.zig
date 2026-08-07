const std = @import("std");
const expr = @import("expr");
const canon = @import("canon");
const Store = expr.Store;
const Id = expr.Id;
const Lit = expr.Lit;
const platform = @import("platform");
const pattern_mod = @import("pattern");
const Allocator = std.mem.Allocator;

// ═══════════════════════════════════════════════════════════════════════════════
// HEAVEN PROOF SYSTEM
//
// Le système de preuve ne manipule que les 6 primitives.
// Les extensions doivent être lowered avant d'entrer dans le pipeline de preuve.
// ═══════════════════════════════════════════════════════════════════════════════

pub const ProofError = error{
    InvalidTheorem,
    ProofFailed,
    UnknownProofStrategy,
    NoProofFound,
    OutOfMemory,
    ExtensionNotLowered,
};

pub const ProofStrategy = enum {
    peano_induction,
    peano_equality,
    canon_equality,
    structural_equality,
    eval_equality,
};

pub const ProofResult = struct {
    theorem_id: u32,
    strategy: ProofStrategy,
    success: bool,
    message: []const u8,
};

pub const Theorem = struct {
    id: u32,
    name: []const u8,
    statement: Id,
    proof: ?ProofResult,
};

pub const ProofEngine = struct {
    store: *Store,
    allocator: Allocator,
    theorems: std.ArrayListUnmanaged(Theorem) = .{},
    next_theorem_id: u32 = 1,

    pub fn init(store: *Store, allocator: Allocator) ProofEngine {
        return .{ .store = store, .allocator = allocator };
    }

    pub fn deinit(self: *ProofEngine) void {
        for (self.theorems.items) |th| {
            self.allocator.free(th.name);
        }
        self.theorems.deinit(self.allocator);
    }

    pub fn declare(self: *ProofEngine, name: []const u8, statement: Id) !u32 {
        const id = self.next_theorem_id;
        self.next_theorem_id += 1;
        const name_copy = try self.allocator.dupe(u8, name);
        try self.theorems.append(self.allocator, .{
            .id = id,
            .name = name_copy,
            .statement = statement,
            .proof = null,
        });
        return id;
    }

    pub fn prove(self: *ProofEngine, theorem_id: u32, strategy: ProofStrategy) !ProofResult {
        const theorem = self.getTheorem(theorem_id) orelse return error.InvalidTheorem;
        const statement = theorem.statement;
        const result = try self.verifyByStrategy(statement, strategy);
        const result_copy = try self.allocator.dupe(u8, result.message);
        const proof_result = ProofResult{
            .theorem_id = theorem_id,
            .strategy = strategy,
            .success = result.success,
            .message = result_copy,
        };
        for (self.theorems.items) |*th| {
            if (th.id == theorem_id) {
                th.proof = proof_result;
                break;
            }
        }
        return proof_result;
    }

    pub fn getTheorem(self: *ProofEngine, id: u32) ?*Theorem {
        for (self.theorems.items) |*th| {
            if (th.id == id) return th;
        }
        return null;
    }

    pub fn listTheorems(self: *ProofEngine) []const Theorem {
        return self.theorems.items;
    }

    fn verifyByStrategy(self: *ProofEngine, statement: Id, strategy: ProofStrategy) !ProofResult {
        return switch (strategy) {
            .peano_induction => self.verifyByInduction(statement),
            .peano_equality => self.verifyPeanoEquality(statement),
            .canon_equality => self.verifyCanonEquality(statement),
            .structural_equality => self.verifyStructuralEquality(statement),
            .eval_equality => self.verifyByEval(statement),
        };
    }

    fn verifyByInduction(self: *ProofEngine, statement: Id) !ProofResult {
        const node = self.store.get(statement);
        if (node.tag != .apply) {
            return ProofResult{
                .theorem_id = 0,
                .strategy = .peano_induction,
                .success = false,
                .message = try self.allocator.dupe(u8, "Statement is not an equality"),
            };
        }
        const func = self.store.get(node.payload);
        if (func.tag != .sym or !std.mem.eql(u8, self.store.interner.resolve(func.payload), "=")) {
            return ProofResult{
                .theorem_id = 0,
                .strategy = .peano_induction,
                .success = false,
                .message = try self.allocator.dupe(u8, "Statement is not an equality"),
            };
        }
        const args = node.span_a.slice(self.store.pool.items);
        if (args.len != 2) {
            return ProofResult{
                .theorem_id = 0,
                .strategy = .peano_induction,
                .success = false,
                .message = try self.allocator.dupe(u8, "Equality must have exactly 2 arguments"),
            };
        }
        const lhs = self.normalizePeano(args[0]);
        const rhs = self.normalizePeano(args[1]);
        const success = self.check_eq(lhs, rhs);
        return ProofResult{
            .theorem_id = 0,
            .strategy = .peano_induction,
            .success = success,
            .message = if (success)
                try self.allocator.dupe(u8, "Proven by Peano induction")
            else
                try self.allocator.dupe(u8, "Peano induction failed"),
        };
    }

    fn normalizePeano(self: *ProofEngine, id: Id) Id {
        if (id >= self.store.len()) return id;
        const node = self.store.get(id);
        const prim = node.tag.asPrimitive();
        if (prim == null) return id;

        switch (prim.?) {
            .sym => {
                const name = self.store.interner.resolve(node.payload);
                if (std.mem.eql(u8, name, "zero")) {
                    return self.store.int(0) catch id;
                }
                return id;
            },
            .apply => {
                const func_id = node.payload;
                const func_node = self.store.get(func_id);
                if (func_node.tag != .sym) return id;
                const fname = self.store.interner.resolve(func_node.payload);
                const args = node.span_a.slice(self.store.pool.items);

                if (std.mem.eql(u8, fname, "succ") and args.len == 1) {
                    const inner = self.normalizePeano(args[0]);
                    const inner_node = self.store.get(inner);
                    if (inner_node.tag == .lit) {
                        const lit = self.store.lits.items[inner_node.aux];
                        switch (lit) {
                            .int => |v| return self.store.int(v + 1) catch id,
                            else => {},
                        }
                    }
                    return id;
                }

                if (std.mem.eql(u8, fname, "add") and args.len == 2) {
                    const a = self.normalizePeano(args[0]);
                    const b = self.normalizePeano(args[1]);
                    const an = self.store.get(a);
                    const bn = self.store.get(b);
                    if (an.tag == .lit and bn.tag == .lit) {
                        const al = self.store.lits.items[an.aux];
                        const bl = self.store.lits.items[bn.aux];
                        switch (al) {
                            .int => |av| switch (bl) {
                                .int => |bv| return self.store.int(av + bv) catch id,
                                else => {},
                            },
                            else => {},
                        }
                    }
                    return id;
                }

                if (std.mem.eql(u8, fname, "mul") and args.len == 2) {
                    const a = self.normalizePeano(args[0]);
                    const b = self.normalizePeano(args[1]);
                    const an = self.store.get(a);
                    const bn = self.store.get(b);
                    if (an.tag == .lit and bn.tag == .lit) {
                        const al = self.store.lits.items[an.aux];
                        const bl = self.store.lits.items[bn.aux];
                        switch (al) {
                            .int => |av| switch (bl) {
                                .int => |bv| return self.store.int(av * bv) catch id,
                                else => {},
                            },
                            else => {},
                        }
                    }
                    return id;
                }

                return id;
            },
            else => return id,
        }
    }

    fn check_eq(self: *ProofEngine, a: Id, b: Id) bool {
        if (a == b) return true;
        const ln = self.store.get(a);
        const rn = self.store.get(b);
        if (ln.tag != rn.tag) return false;

        const prim_l = ln.tag.asPrimitive();
        const prim_r = rn.tag.asPrimitive();
        if (prim_l == null or prim_r == null) return false;

        return switch (prim_l.?) {
            .sym => ln.payload == rn.payload,
            .lit => {
                const ll = self.store.lits.items[ln.aux];
                const rl = self.store.lits.items[rn.aux];
                return ll.eql(rl);
            },
            .apply => {
                if (!self.check_eq(ln.payload, rn.payload)) return false;
                const la = ln.span_a.slice(self.store.pool.items);
                const ra = rn.span_a.slice(self.store.pool.items);
                if (la.len != ra.len) return false;
                for (la, ra) |l, r| {
                    if (!self.check_eq(l, r)) return false;
                }
                return true;
            },
            .bind => self.check_eq(ln.aux, rn.aux),
            .lambda => {
                if (ln.payload != rn.payload) return false;
                const la = ln.span_a.slice(self.store.pool.items);
                const ra = rn.span_a.slice(self.store.pool.items);
                if (la.len != ra.len) return false;
                for (la, ra) |l, r| {
                    if (!self.check_eq(l, r)) return false;
                }
                return true;
            },
            .relation => {
                if (ln.payload != rn.payload) return false;
                const la = ln.span_a.slice(self.store.pool.items);
                const ra = rn.span_a.slice(self.store.pool.items);
                if (la.len != ra.len) return false;
                for (la, ra) |l, r| {
                    if (!self.check_eq(l, r)) return false;
                }
                const lb = ln.span_b.slice(self.store.pool.items);
                const rb = rn.span_b.slice(self.store.pool.items);
                if (lb.len != rb.len) return false;
                for (lb, rb) |l, r| {
                    if (!self.check_eq(l, r)) return false;
                }
                return true;
            },
        };
    }

    fn verifyPeanoEquality(self: *ProofEngine, statement: Id) !ProofResult {
        const node = self.store.get(statement);
        if (node.tag != .apply) {
            return ProofResult{
                .theorem_id = 0,
                .strategy = .peano_equality,
                .success = false,
                .message = try self.allocator.dupe(u8, "Not an equality"),
            };
        }
        const func = self.store.get(node.payload);
        if (func.tag != .sym or !std.mem.eql(u8, self.store.interner.resolve(func.payload), "=")) {
            return ProofResult{
                .theorem_id = 0,
                .strategy = .peano_equality,
                .success = false,
                .message = try self.allocator.dupe(u8, "Not an equality"),
            };
        }
        const args = node.span_a.slice(self.store.pool.items);
        if (args.len != 2) {
            return ProofResult{
                .theorem_id = 0,
                .strategy = .peano_equality,
                .success = false,
                .message = try self.allocator.dupe(u8, "Arity mismatch"),
            };
        }
        const lhs = self.normalizePeano(args[0]);
        const rhs = self.normalizePeano(args[1]);
        const success = self.check_eq(lhs, rhs);
        return ProofResult{
            .theorem_id = 0,
            .strategy = .peano_equality,
            .success = success,
            .message = if (success)
                try self.allocator.dupe(u8, "Peano equality verified")
            else
                try self.allocator.dupe(u8, "Peano equality failed"),
        };
    }

    fn verifyCanonEquality(self: *ProofEngine, statement: Id) !ProofResult {
        const node = self.store.get(statement);
        if (node.tag != .apply) {
            return ProofResult{
                .theorem_id = 0,
                .strategy = .canon_equality,
                .success = false,
                .message = try self.allocator.dupe(u8, "Not an equality"),
            };
        }
        const func = self.store.get(node.payload);
        if (func.tag != .sym or !std.mem.eql(u8, self.store.interner.resolve(func.payload), "=")) {
            return ProofResult{
                .theorem_id = 0,
                .strategy = .canon_equality,
                .success = false,
                .message = try self.allocator.dupe(u8, "Not an equality"),
            };
        }
        const args = node.span_a.slice(self.store.pool.items);
        if (args.len != 2) {
            return ProofResult{
                .theorem_id = 0,
                .strategy = .canon_equality,
                .success = false,
                .message = try self.allocator.dupe(u8, "Arity mismatch"),
            };
        }
        const c1 = try canon.canonicalize(self.store, self.allocator, args[0]);
        const c2 = try canon.canonicalize(self.store, self.allocator, args[1]);
        const success = canon.exprEqual(self.store, c1, c2);
        return ProofResult{
            .theorem_id = 0,
            .strategy = .canon_equality,
            .success = success,
            .message = if (success)
                try self.allocator.dupe(u8, "Canonical equality verified")
            else
                try self.allocator.dupe(u8, "Canonical equality failed"),
        };
    }

    fn verifyStructuralEquality(self: *ProofEngine, statement: Id) !ProofResult {
        const node = self.store.get(statement);
        if (node.tag != .apply) {
            return ProofResult{
                .theorem_id = 0,
                .strategy = .structural_equality,
                .success = false,
                .message = try self.allocator.dupe(u8, "Not an equality"),
            };
        }
        const func = self.store.get(node.payload);
        if (func.tag != .sym or !std.mem.eql(u8, self.store.interner.resolve(func.payload), "=")) {
            return ProofResult{
                .theorem_id = 0,
                .strategy = .structural_equality,
                .success = false,
                .message = try self.allocator.dupe(u8, "Not an equality"),
            };
        }
        const args = node.span_a.slice(self.store.pool.items);
        if (args.len != 2) {
            return ProofResult{
                .theorem_id = 0,
                .strategy = .structural_equality,
                .success = false,
                .message = try self.allocator.dupe(u8, "Arity mismatch"),
            };
        }
        const success = pattern_mod.exprStructuralEq(self.store, args[0], args[1]);
        return ProofResult{
            .theorem_id = 0,
            .strategy = .structural_equality,
            .success = success,
            .message = if (success)
                try self.allocator.dupe(u8, "Structural equality verified")
            else
                try self.allocator.dupe(u8, "Structural equality failed"),
        };
    }

    fn verifyByEval(self: *ProofEngine, statement: Id) !ProofResult {
        const node = self.store.get(statement);
        if (node.tag != .apply) {
            return ProofResult{
                .theorem_id = 0,
                .strategy = .eval_equality,
                .success = false,
                .message = try self.allocator.dupe(u8, "Not an equality"),
            };
        }
        const func = self.store.get(node.payload);
        if (func.tag != .sym or !std.mem.eql(u8, self.store.interner.resolve(func.payload), "=")) {
            return ProofResult{
                .theorem_id = 0,
                .strategy = .eval_equality,
                .success = false,
                .message = try self.allocator.dupe(u8, "Not an equality"),
            };
        }
        const args = node.span_a.slice(self.store.pool.items);
        if (args.len != 2) {
            return ProofResult{
                .theorem_id = 0,
                .strategy = .eval_equality,
                .success = false,
                .message = try self.allocator.dupe(u8, "Arity mismatch"),
            };
        }
        const lhs = args[0];
        const rhs = args[1];
        const lhs_node = self.store.get(lhs);
        const rhs_node = self.store.get(rhs);
        const success = lhs_node.tag == .lit and rhs_node.tag == .lit and
            self.store.lits.items[lhs_node.aux].eql(self.store.lits.items[rhs_node.aux]);
        return ProofResult{
            .theorem_id = 0,
            .strategy = .eval_equality,
            .success = success,
            .message = if (success)
                try self.allocator.dupe(u8, "Eval equality verified")
            else
                try self.allocator.dupe(u8, "Eval equality failed"),
        };
    }
};

// ─── Tests ───

test "proof — Peano equality" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var engine = ProofEngine.init(&store, allocator);
    defer engine.deinit();

    const zero = try store.sym("zero");
    const one = try store.call("succ", &.{zero});
    const two = try store.call("succ", &.{one});
    const lhs = try store.call("add", &.{ one, two });
    const rhs = try store.call("add", &.{ two, one });
    const eq = try store.binop("=", lhs, rhs);

    const result = try engine.verifyByInduction(eq);
    try std.testing.expect(result.success);
}

test "proof — canonical equality" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var engine = ProofEngine.init(&store, allocator);
    defer engine.deinit();

    const x = try store.sym("x");
    const zero = try store.int(0);
    const lhs = try store.binop("+", x, zero);
    const rhs = x;
    const eq = try store.binop("=", lhs, rhs);

    const result = try engine.verifyCanonEquality(eq);
    try std.testing.expect(result.success);
}
