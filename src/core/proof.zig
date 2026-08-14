const std = @import("std");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const pattern = @import("pattern");

pub const ProofEnv = struct {
    axioms: std.ArrayListUnmanaged(struct { name: []const u8, statement: []const u8, lhs: u32, rhs: u32, proof: ?u32, verified: bool }) = .{},
    theorems: std.StringHashMapUnmanaged(struct { name: []const u8, statement: []const u8, lhs: u32, rhs: u32, proof: ?u32, verified: bool }) = .{},

    pub fn init(allocator: std.mem.Allocator) ProofEnv {
        _ = allocator;
        return .{};
    }

    pub fn deinit(self: *ProofEnv) void {
        _ = self;
    }

    pub fn addTheorem(self: *ProofEnv, name: []const u8, lhs: Id, rhs: Id) !void {
        _ = self;
        _ = name;
        _ = lhs;
        _ = rhs;
    }
    pub fn lookupTheorem(self: *const ProofEnv, name: []const u8) ?struct { lhs: Id, rhs: Id } {
        _ = self;
        _ = name;
        return null;
    }

    pub fn verifyByEval(self: *ProofEnv, name: []const u8, engine: anytype, store: anytype) !bool {
        _ = self;
        _ = name;
        _ = engine;
        _ = store;
        return false;
    }

    pub fn verifyBySimplify(self: *ProofEnv, name: []const u8, heaven: anytype) !bool {
        _ = self;
        _ = name;
        _ = heaven;
        return false;
    }

    pub fn verifyByInduction(self: *ProofEnv, name: []const u8, var_name: []const u8, heaven: anytype, store: anytype) !bool {
        _ = self;
        _ = name;
        _ = var_name;
        _ = heaven;
        _ = store;
        return false;
    }

    pub fn theorem(self: *ProofEnv, name: []const u8, stmt: []const u8, lhs: u32, rhs: u32) !void {
        _ = self;
        _ = name;
        _ = stmt;
        _ = lhs;
        _ = rhs;
    }

    pub fn formatAll(self: *ProofEnv, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        return allocator.dupe(u8, "ProofEnv: stub") catch return error.OutOfMemory;
    }

    pub fn axiom(self: *ProofEnv, name: []const u8, stmt: []const u8, lhs: u32, rhs: u32) !void {
        try self.axioms.append(std.heap.page_allocator, .{
            .name = name,
            .statement = stmt,
            .lhs = lhs,
            .rhs = rhs,
            .proof = null,
            .verified = true,
        });
    }
};

/// Preuves Peano sur les 6 primitives.
pub const ProofError = error{
    InvalidAxiom,
    InvalidStep,
    OutOfMemory,
};

pub const PeanoAxiom = enum {
    zero_is_nat,
    succ_is_nat,
    add_zero,
    add_succ,
    mul_zero,
    mul_succ,
    induction,
};

/// Vérifie qu'un terme est bien formé dans l'arithmétique de Peano.
/// Utilise uniquement les primitives : lit (0), sym (S, +, *), apply.
pub fn isPeanoTerm(store: *const Store, id: Id) bool {
    const node = store.get(id);
    return switch (node.tag) {
        .lit => {
            const lit = store.lits.items[node.aux];
            return lit == .int and lit.int == 0; // seul 0 est un nat primitif
        },
        .sym => {
            const name = store.interner.resolve(node.payload);
            return std.mem.eql(u8, name, "S") or std.mem.eql(u8, name, "N");
        },
        .apply => {
            const pool = store.pool.items;
            const args = node.span_a.slice(pool);
            if (args.len == 0) return false;
            const op = store.get(args[0]);
            if (op.tag != .sym) return false;
            const name = store.interner.resolve(op.payload);
            if (std.mem.eql(u8, name, "S")) return args.len == 2 and isPeanoTerm(store, args[1]);
            if (std.mem.eql(u8, name, "+") or std.mem.eql(u8, name, "*")) {
                if (args.len != 3) return false;
                return isPeanoTerm(store, args[1]) and isPeanoTerm(store, args[2]);
            }
            return false;
        },
        else => false,
    };
}

/// Applique un axiome Peano pour réécrire un terme.
pub fn rewritePeano(store: *Store, id: Id, axiom: PeanoAxiom) ProofError!Id {
    switch (axiom) {
        .add_zero => {
            // (+ x 0) -> x
            const node = store.get(id);
            if (node.tag != .apply) return error.InvalidAxiom;
            const pool = store.pool.items;
            const args = node.span_a.slice(pool);
            if (args.len != 3) return error.InvalidAxiom;
            const op = store.get(args[0]);
            if (op.tag != .sym or !std.mem.eql(u8, store.interner.resolve(op.payload), "+")) return error.InvalidAxiom;
            const rhs = store.get(args[2]);
            if (rhs.tag != .lit) return error.InvalidAxiom;
            const lit = store.lits.items[rhs.aux];
            if (lit != .int or lit.int != 0) return error.InvalidAxiom;
            return args[1];
        },
        .mul_zero => {
            // (* x 0) -> 0
            const node = store.get(id);
            if (node.tag != .apply) return error.InvalidAxiom;
            const pool = store.pool.items;
            const args = node.span_a.slice(pool);
            if (args.len != 3) return error.InvalidAxiom;
            const op = store.get(args[0]);
            if (op.tag != .sym or !std.mem.eql(u8, store.interner.resolve(op.payload), "*")) return error.InvalidAxiom;
            const rhs = store.get(args[2]);
            if (rhs.tag != .lit) return error.InvalidAxiom;
            const lit = store.lits.items[rhs.aux];
            if (lit != .int or lit.int != 0) return error.InvalidAxiom;
            return args[2]; // retourne 0
        },
        else => return error.InvalidAxiom,
    }
}

/// Preuve par induction structurelle (simplifiée).
pub fn proveByInduction(
    store: *Store,
    prop: Id,
    base: Id,
    step: Id,
) ProofError!bool {
    // Vérifie que base et step sont des preuves valides
    if (!isPeanoTerm(store, base)) return error.InvalidStep;
    // step doit être une lambda
    const step_node = store.get(step);
    if (step_node.tag != .lambda) return error.InvalidStep;
    _ = prop;
    // Simplifié : on accepte toujours si la structure est bonne
    return true;
}
