const std = @import("std");
const matrix_lib = @import("../../core/matrix.zig");

pub fn unify_nodes(matrix: matrix_lib.Matrix, a: matrix_lib.BobId, b: matrix_lib.BobId) bool {
    return matrix.findCanonical(a) == matrix.findCanonical(b);
}

pub const Type = union(enum) {
    Var: usize, // Variable de type (α, β...)
    Arrow: struct { arg: *const Type, ret: *const Type },
    Constructor: struct { name: []const u8, args: []const *const Type },
    Hole, // Pour inférence partielle
};

pub const Substitution = std.AutoHashMap(usize, *const Type);

// Applique récursivement une substitution à un type
fn apply(sub: *const Substitution, t: *const Type) *const Type {
    return switch (t.*) {
        .Var => |v| sub.get(v) orelse t,
        .Arrow => |a| blk: {
            // Note: Dans un compilateur réel, il faudrait allouer une nouvelle structure ici
            // Pour ce snippet, on retourne le type modifié logiquement
            break :blk t; 
        },
        .Constructor => |c| blk: {
            break :blk t;
        },
        else => t,
    };
}

// Occurs check : empêche α = List α (cycles infinis)
fn occurs(v: usize, t: *const Type) bool {
    return switch (t.*) {
        .Var => |tv| tv == v,
        .Arrow => |a| occurs(v, a.arg) or occurs(v, a.ret),
        .Constructor => |c| blk: {
            for (c.args) |arg| if (occurs(v, arg)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

// Algorithme W : Unification Hindley-Milner
pub fn unify_types(
    t1: *const Type, 
    t2: *const Type, 
    sub: *Substitution,
    counter: *usize
) !void {
    const a = apply(sub, t1);
    const b = apply(sub, t2);

    switch (a.*) {
        .Var => |v| {
            if (b.* == .Var and b.Var == v) return;
            if (occurs(v, b)) return error.OccursCheck;
            try sub.put(v, b);
        },
        .Arrow => |aa| {
            if (b.* != .Arrow) return error.TypeMismatch;
            const bb = b.Arrow;
            try unify_types(aa.arg, bb.arg, sub, counter);
            try unify_types(aa.ret, bb.ret, sub, counter);
        },
        .Constructor => |ac| {
            if (b.* != .Constructor) return error.TypeMismatch;
            const bc = b.Constructor;
            if (!std.mem.eql(u8, ac.name, bc.name)) return error.TypeMismatch;
            if (ac.args.len != bc.args.len) return error.ArityMismatch;
            
            for (ac.args, bc.args) |arg1, arg2| {
                try unify_types(arg1, arg2, sub, counter);
            }
        },
        else => {},
    }
}

// Généralisation pour le polymorphisme (∀)
pub fn generalize(env: *const Substitution, t: *const Type) *const Type {
    // Simplifié : retourne le type généralisé
    return apply(env, t);
}
