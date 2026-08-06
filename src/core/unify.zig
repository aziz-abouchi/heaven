const std = @import("std");
const matrix_lib = @import("matrix_lib");
const BobId = matrix_lib.BobId;

pub const Substitution = struct {
    // Lie un BobId (Variable) à un autre BobId (Valeur ou autre Variable)
    bindings: std.AutoHashMap(BobId, BobId),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Substitution {
        return .{
            .bindings = std.AutoHashMap(BobId, BobId).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Substitution) void {
        self.bindings.deinit();
    }

    pub fn lookup(self: *const Substitution, id: BobId) BobId {
        var curr = id;
        while (self.bindings.get(curr)) |next| {
            if (next == curr) break;
            curr = next;
        }
        return curr;
    }

    pub fn bind(self: *Substitution, var_id: BobId, target_id: BobId) !void {
        try self.bindings.put(var_id, target_id);
    }
};

pub fn unify(matrix: *matrix_lib.Matrix, subst: *Substitution, a_id: BobId, b_id: BobId) !bool {
    // 1. Résolution via Union-Find de la Matrix + Substitution locale
    const a = subst.lookup(matrix.findCanonical(a_id));
    const b = subst.lookup(matrix.findCanonical(b_id));

    if (a == b) return true;

    const node_a = matrix.nodes.get(a) orelse return false;
    const node_b = matrix.nodes.get(b) orelse return false;

    // 2. Gestion des Variables Logiques
    // On considère ici que le nœud "Hole" ou un "Symbol" commençant par '?' est une variable
    if (isVariable(node_a)) {
        try subst.bind(a, b);
        return true;
    }
    if (isVariable(node_b)) {
        try subst.bind(b, a);
        return true;
    }

    // 3. Unification Structurelle (exemple sur HCall ou Relation)
    return switch (node_a) {
        .Symbol => |s| if (node_b == .Symbol) std.mem.eql(u8, s, node_b.Symbol) else false,
        .HIntLit => |i| if (node_b == .HIntLit) i == node_b.HIntLit else false,
        
        .HCall => |call_a| {
            if (node_b != .HCall) return false;
            const call_b = node_b.HCall;
            if (!try unify(matrix, subst, call_a.callee, call_b.callee)) return false;
            if (call_a.args.len != call_b.args.len) return false;
            for (call_a.args, 0..) |arg_a, i| {
                if (!try unify(matrix, subst, arg_a, call_b.args[i])) return false;
            }
            return true;
        },
        
        .Relation => |rel_a| {
            if (node_b != .Relation) return false;
            const rel_b = node_b.Relation;
            if (!try unify(matrix, subst, rel_a.predicate, rel_b.predicate)) return false;
            if (rel_a.args.len != rel_b.args.len) return false;
            for (rel_a.args, 0..) |arg_a, i| {
                if (!try unify(matrix, subst, arg_a, rel_b.args[i])) return false;
            }
            return true;
        },

        else => false, // Par défaut, si les types/valeurs diffèrent
    };
}

fn isVariable(node: matrix_lib.BobNode) bool {
    return switch (node) {
        .Hole => true,
        .Symbol => |s| s.len > 0 and std.ascii.isUpper(s[0]), // Majuscule = Variable (Prolog style)
        else => false,
    };
}
