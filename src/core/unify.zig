const std = @import("std");
const matrix_lib = @import("matrix_lib");
const BobId = matrix_lib.BobId;
const BobNode = matrix_lib.BobNode;

pub const Substitution = struct {
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

/// Normalise un BobId en alternant Matrix.findCanonical et Substitution.lookup jusqu'au point fixe.
pub fn resolve(matrix: *matrix_lib.Matrix, subst: *const Substitution, id: BobId) BobId {
    var curr = id;
    while (true) {
        const canonical = matrix.findCanonical(curr);
        const looked_up = subst.lookup(canonical);
        if (looked_up == curr) break;
        curr = looked_up;
    }
    return curr;
}

/// Vérifie si la variable `var_id` apparaît dans la structure du nœud désigné par `target_id`.
fn occursCheck(matrix: *matrix_lib.Matrix, subst: *const Substitution, var_id: BobId, target_id: BobId) bool {
    const norm_target = resolve(matrix, subst, target_id);
    if (var_id == norm_target) return true;

    const node = matrix.nodes.get(norm_target) orelse return false;
    return switch (node) {
        .HCall => |call| {
            if (occursCheck(matrix, subst, var_id, call.callee)) return true;
            for (call.args) |arg| {
                if (occursCheck(matrix, subst, var_id, arg)) return true;
            }
            return false;
        },
        else => false,
    };
}

pub fn unify(matrix: *matrix_lib.Matrix, subst: *Substitution, a_id: BobId, b_id: BobId) !bool {
    // 1. Normalisation au point fixe
    const a = resolve(matrix, subst, a_id);
    const b = resolve(matrix, subst, b_id);

    if (a == b) return true;

    const node_a = matrix.nodes.get(a) orelse return false;
    const node_b = matrix.nodes.get(b) orelse return false;

    const var_a = isVariable(node_a);
    const var_b = isVariable(node_b);

    // 2. Gestion des variables logiques avec Occurs Check
    if (var_a and var_b) {
        try subst.bind(a, b);
        return true;
    }
    if (var_a) {
        if (occursCheck(matrix, subst, a, b)) return false;
        try subst.bind(a, b);
        return true;
    }
    if (var_b) {
        if (occursCheck(matrix, subst, b, a)) return false;
        try subst.bind(b, a);
        return true;
    }

    // 3. E-Unification : comparaison structurelle récursive
    const structurally_equal = switch (node_a) {
        .Symbol => |s| node_b == .Symbol and std.mem.eql(u8, s, node_b.Symbol),
        .HIntLit => |i| node_b == .HIntLit and i == node_b.HIntLit,
        .HCall => |call_a| blk: {
            if (node_b != .HCall) break :blk false;
            const call_b = node_b.HCall;
            if (!try unify(matrix, subst, call_a.callee, call_b.callee)) break :blk false;
            if (call_a.args.len != call_b.args.len) break :blk false;
            for (call_a.args, 0..) |arg_a, i| {
                if (!try unify(matrix, subst, arg_a, call_b.args[i])) break :blk false;
            }
            break :blk true;
        },
        else => false,
    };

    if (structurally_equal) {
        matrix.fuseNodes(a, b);
        return true;
    }

    return false;
}

fn isVariable(node: BobNode) bool {
    return switch (node) {
        .Hole => true,
        .Symbol => |s| s.len > 0 and std.ascii.isUpper(s[0]),
        else => false,
    };
}
