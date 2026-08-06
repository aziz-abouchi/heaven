//! Helpers de preuve pour Heaven
//! Fonctions utilitaires extraites de commands.zig et heaven_expr.zig

const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const proof_core = @import("proof_core");

pub const ProofHelpers = struct {
    store: *Store,
    allocator: Allocator,

    pub fn init(store: *Store, allocator: Allocator) ProofHelpers {
        return .{ .store = store, .allocator = allocator };
    }

    /// Extrait les arguments lhs/rhs d'un terme Eq<lhs, rhs>
    pub fn extractEqArgs(self: *ProofHelpers, id: Id) ?struct { lhs: Id, rhs: Id } {
        return extractEqArgsFromStore(self.store, id);
    }

    /// Copie récursive d'un Id d'un store source vers un store destination
    pub fn copyId(src: *Store, dst: *Store, id: Id) !Id {
        return copyIdBetweenStores(src, dst, id);
    }

    /// Parse un bloc de preuve textuel en ProofTerm
    pub fn parseProofBlock(allocator: Allocator, text: []const u8) ?*const proof_core.ProofTerm {
        if (std.mem.indexOf(u8, text, "qed") != null) {
            const pt = allocator.create(proof_core.ProofTerm) catch return null;
            if (std.mem.indexOf(u8, text, "refl") != null) {
                pt.* = .{ .refl = 0 };
            } else if (std.mem.indexOf(u8, text, "apply") != null) {
                pt.* = .{ .by_eval = .{ .lhs = 0, .rhs = 0 } };
            } else {
                pt.* = .{ .qed = {} };
            }
            return pt;
        }
        return null;
    }

    /// Construit une opération binaire avec simplifications algébriques basiques
    pub fn mkBinop(self: *ProofHelpers, op: []const u8, a: Id, b: Id) !Id {
        if (a >= self.store.len() or b >= self.store.len()) return self.store.int(0);
        const na = self.store.get(a);
        const nb = self.store.get(b);
        const is_a_zero = na.tag == .lit and self.store.lits.items[na.aux].eql(.{ .int = 0 });
        const is_b_zero = nb.tag == .lit and self.store.lits.items[nb.aux].eql(.{ .int = 0 });
        const is_a_one = na.tag == .lit and self.store.lits.items[na.aux].eql(.{ .int = 1 });
        const is_b_one = nb.tag == .lit and self.store.lits.items[nb.aux].eql(.{ .int = 1 });

        if (std.mem.eql(u8, op, "+")) {
            if (is_a_zero) return b;
            if (is_b_zero) return a;
            if (na.tag == .lit and nb.tag == .lit) {
                const la = self.store.lits.items[na.aux];
                const lb = self.store.lits.items[nb.aux];
                switch (la) {
                    .int => |va| switch (lb) {
                        .int => |vb| return self.store.int(std.math.add(i64, va, vb) catch return error.Overflow),
                        else => {},
                    },
                    else => {},
                }
            }
        } else if (std.mem.eql(u8, op, "-")) {
            if (is_b_zero) return a;
            if (na.tag == .lit and nb.tag == .lit) {
                const la = self.store.lits.items[na.aux];
                const lb = self.store.lits.items[nb.aux];
                switch (la) {
                    .int => |va| switch (lb) {
                        .int => |vb| return self.store.int(std.math.sub(i64, va, vb) catch return error.Overflow),
                        else => {},
                    },
                    else => {},
                }
            }
        } else if (std.mem.eql(u8, op, "*")) {
            if (is_a_zero or is_b_zero) return self.store.int(0);
            if (is_a_one) return b;
            if (is_b_one) return a;
            if (na.tag == .lit and nb.tag == .lit) {
                const la = self.store.lits.items[na.aux];
                const lb = self.store.lits.items[nb.aux];
                switch (la) {
                    .int => |va| switch (lb) {
                        .int => |vb| return self.store.int(std.math.mul(i64, va, vb) catch return error.Overflow),
                        else => {},
                    },
                    else => {},
                }
            }
        } else if (std.mem.eql(u8, op, "/")) {
            if (is_a_zero) return self.store.int(0);
            if (is_b_one) return a;
        } else if (std.mem.eql(u8, op, "^")) {
            if (is_b_zero) return self.store.int(1);
            if (is_b_one) return a;
        }
        return self.store.binop(op, a, b);
    }
};

// ─── Fonctions standalone (sans self) ───

/// Version standalone de extractEqArgs
pub fn extractEqArgsFromStore(store: *Store, id: Id) ?struct { lhs: Id, rhs: Id } {
    const node = store.get(id);
    const pool = store.pool.items;

    if (node.tag == .source_file) {
        const children = node.span_a.slice(pool);
        if (children.len == 0) return null;
        return extractEqArgsFromStore(store, children[0]);
    }
    if (node.tag == .bind) return extractEqArgsFromStore(store, node.aux);
    if (node.tag != .apply) return null;

    const func_node = store.get(node.payload);
    if (func_node.tag != .sym) return null;
    const name = store.interner.resolve(func_node.payload);
    const args = node.span_a.slice(pool);

    if (std.mem.eql(u8, name, "Eq") and args.len == 2) return .{ .lhs = args[0], .rhs = args[1] };
    if (std.mem.eql(u8, name, "forall") and args.len >= 1) return extractEqArgsFromStore(store, args[args.len - 1]);
    if (std.mem.eql(u8, name, "->") and args.len == 2) return extractEqArgsFromStore(store, args[1]);
    return null;
}

/// Version standalone de copyId
pub fn copyIdBetweenStores(src: *Store, dst: *Store, id: Id) !Id {
    const node = src.get(id);
    const pool = src.pool.items;
    switch (node.tag) {
        .sym => return dst.sym(src.interner.resolve(node.payload)),
        .lit => return dst.lit(src.lits.items[node.aux]),
        .apply => {
            const func = try copyIdBetweenStores(src, dst, node.payload);
            var args: std.ArrayListUnmanaged(Id) = .{};
            defer args.deinit(dst.allocator);
            for (node.span_a.slice(pool)) |arg| try args.append(dst.allocator, try copyIdBetweenStores(src, dst, arg));
            return dst.apply(func, args.items);
        },
        .bind => {
            const val = try copyIdBetweenStores(src, dst, node.aux);
            return dst.bind(src.interner.resolve(node.payload), val);
        },
        else => return dst.sym("<unsupported>"),
    }
}
