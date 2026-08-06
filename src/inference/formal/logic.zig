const std = @import("std");
const matrix_lib = @import("../core/matrix.zig");

// Un terme logique peut être une variable, une constante ou une structure
pub const Term = union(enum) {
    Var: usize,
    Const: []const u8,
    Struct: struct { name: []const u8, args: []const Term },
};

// Le moteur de résolution
pub fn resolve(
    goal: Term, 
    kb: *KnowledgeBase, // Base de faits et règles
    solution: *Substitution
) bool {
    // 1. Unifier le goal avec la tête d'une règle ou un fait
    // 2. Si succès, résoudre le corps de la règle (récursion)
    // 3. Backtracking si échec (essayer la règle suivante)
}

pub const LogicEngine = struct {
    /// Tente d'unifier deux symboles (A ≅ B) avec gestion de variables ?X
    pub fn unify(matrix: *matrix_lib.Matrix, pattern: []const u8, target: []const u8) bool {
        if (std.mem.eql(u8, pattern, target)) return true;

        if (std.mem.indexOfScalar(u8, pattern, '?')) |idx| {
            if (target.len < idx) return false;
            if (idx > 0 and !std.mem.eql(u8, pattern[0..idx], target[0..idx])) return false;

            const var_part = pattern[idx..];
            const end_var = std.mem.indexOfAny(u8, var_part, " ,()[]{}") orelse var_part.len;
            const var_name = var_part[0..end_var];

            const val_part = target[idx..];
            const end_val = if (end_var < var_part.len)
                std.mem.indexOfScalar(u8, val_part, var_part[end_var]) orelse val_part.len
            else
                val_part.len;

            const value = val_part[0..end_val];

            var buf: [128]u8 = undefined;
            const bond = std.fmt.bufPrint(&buf, "BOND:{s}={s}", .{ var_name, value }) catch return true;
            _ = matrix.addUniqueSymbol(bond) catch {};

            return true;
        }
        return false;
    }

    /// Vérifie récursivement si un nœud hérite d'un type via la relation "IS"
    /// Changement de signature : node_id passe en u32 pour matcher Matrix
    pub fn isType(matrix: *matrix_lib.Matrix, node_id: u32, type_name: []const u8) bool {
        // Résolution de l'ID canonique (le "vrai" représentant du nœud)
        const root_id = matrix.findCanonicalInternal(node_id);
        const node = matrix.nodes.get(root_id) orelse return false;

        if (node == .Symbol and std.mem.eql(u8, node.Symbol, type_name)) return true;

        var it = matrix.nodes.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == .Edge) {
                const edge = entry.value_ptr.Edge;
                // On vérifie si cette arête appartient au groupe de notre node_id
                if (matrix.findCanonicalInternal(entry.key_ptr.*) == root_id and std.mem.eql(u8, edge.label, "IS")) {
                    if (isType(matrix, edge.target, type_name)) return true;
                }
            }
        }
        return false;
    }

    /// Remplace les variables ?X par leurs valeurs stockées (BONDs)
    pub fn applyBonds(matrix: *matrix_lib.Matrix, action: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        var final_action = try allocator.dupe(u8, action);
        errdefer allocator.free(final_action);

        var it = matrix.nodes.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* != .Symbol) continue;
            const sym = entry.value_ptr.Symbol;
            if (std.mem.startsWith(u8, sym, "BOND:")) {
                const eq_idx = std.mem.indexOf(u8, sym, "=") orelse continue;
                const var_name = sym[5..eq_idx];
                const val = sym[eq_idx + 1 ..];

                if (std.mem.indexOf(u8, final_action, var_name)) |_| {
                    const new_action = try std.mem.replaceOwned(u8, allocator, final_action, var_name, val);
                    allocator.free(final_action);
                    final_action = new_action;
                }
            }
        }
        return final_action;
    }

    /// Fusionne deux matrices (Pushout Morphism)
    pub fn unifyMatrices(target: *matrix_lib.Matrix, source: *matrix_lib.Matrix) !void {
        var it = source.nodes.iterator();
        while (it.next()) |entry| {
            switch (entry.value_ptr.*) {
                .Symbol => |s| {
                    _ = try target.addUniqueSymbol(s);
                },
                .Edge => |e| {
                    try target.addEdge(@truncate(entry.key_ptr.*), @truncate(e.target), e.label);
                },
                .Scalar => |val| {
                    if (!target.nodes.contains(@truncate(entry.key_ptr.*))) {
                        _ = try target.addNode(.{ .Scalar = val });
                    }
                },
                else => {},
            }
        }
    }
};
