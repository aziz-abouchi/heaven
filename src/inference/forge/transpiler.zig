const std = @import("std");
const matrix_lib = @import("matrix_lib");
const platform = @import("platform");

pub const TranspilerError = error{
    OutOfMemory,
    AtomNotFound,
    NotImplemented,
};

pub fn wrapAsProgram(code: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return try std.fmt.allocPrint(allocator,
        \\const std = @import("std");
        \\pub fn main() void {{
        \\    platform.debug.print("RESULT: {s}\\n", .{{"{s}"}});
        \\}}
    , .{code});
}

pub const SurvivalTranspiler = struct {
    allocator: std.mem.Allocator,
    matrix: *matrix_lib.Matrix,

    /// Point d'entrée unique : convertit n'importe quel ID de la Matrix en C
    pub fn transpile(self: *SurvivalTranspiler, node_id: matrix_lib.BobId) TranspilerError![]const u8 {
        const node = self.matrix.nodes.get(node_id) orelse return error.AtomNotFound;

        var output = std.ArrayListUnmanaged(u8){};
        errdefer output.deinit(self.allocator);
        const writer = output.writer(self.allocator);

        switch (node) {
            .Symbol => |s| try output.appendSlice(self.allocator, s),

            .Bind => |b| {
                const target_name = try self.transpile(b.target);
                const value_code = try self.transpile(b.value);
                try writer.print("auto {s} = {s};", .{ target_name, value_code });
            },

            .Lambda => |l| {
                const param = try self.transpile(l.param);
                const body = try self.transpile(l.body);

                try writer.print("({s}) -> {{ return {s}; }}", .{ param, body });
            },

            .Apply => |a| {
                const func_name = try self.transpile(a.function);

                try output.appendSlice(self.allocator, "(");
                try output.appendSlice(self.allocator, func_name);
                try output.appendSlice(self.allocator, ")(");

                for (a.args, 0..) |arg_id, i| {
                    if (i > 0) try output.appendSlice(self.allocator, ", ");
                    try output.appendSlice(self.allocator, try self.transpile(arg_id));
                }

                try output.appendSlice(self.allocator, ")");
            },

            .Aggregate => |agg| {
                // Traduction d'un Σ ou Π en boucle C
                const var_name = try self.transpile(agg.variable);
                const body = try self.transpile(agg.body);
                const op_init = if (agg.op == .Sum) "0" else "1";
                const op_sym = if (agg.op == .Sum) "+" else "*";

                try writer.print(
                    \\({{[ 
                    \\  double res = {s}; 
                    \\  for(int {s}=0; {s}<10; {s}++) {{ res {s}= {s}; }} 
                    \\  res; 
                    \\}})
                , .{ op_init, var_name, var_name, var_name, op_sym, body });
            },
            .NativeCode => |nc| {
                var current_working_code = try self.allocator.dupe(u8, nc.code);
                errdefer self.allocator.free(current_working_code);

                const replacements = .{
                    .{ "pub fn isReservedKeyword(name: []const u8) bool", "bool isReservedKeyword(const char* name)" },
                    .{ "fn isReservedKeyword(name: []const u8) bool", "bool isReservedKeyword(const char* name)" },
                    .{ "for (keywords) |k|", "for (int i=0; i<11; i++) {" },
                    .{ "if (std.mem.eql(u8, name, k)) return true;", "if (0 == strcmp(name, keywords[i])) return 1; }" },
                    .{ "const keywords = [_][]const u8", "const char* keywords[11] =" },
                    .{ "pub fn ", "bool " },
                    .{ ": []const u8", "" },
                    .{ ") bool {", ") {" },
                    .{ "return true;", "return 1;" },
                    .{ "return false;", "return 0;" },
                };

                inline for (replacements) |rep| {
                    const occurrences = std.mem.count(u8, current_working_code, rep[0]);
                    if (occurrences > 0) {
                        // On calcule la différence de taille en entier signé
                        const diff: isize = @as(isize, @intCast(rep[1].len)) - @as(isize, @intCast(rep[0].len));
                        // On calcule la nouvelle taille totale
                        const new_size = @as(usize, @intCast(@as(isize, @intCast(current_working_code.len)) + (@as(isize, @intCast(occurrences)) * diff)));

                        const new_buffer = try self.allocator.alloc(u8, new_size);
                        _ = std.mem.replace(u8, current_working_code, rep[0], rep[1], new_buffer);
                        self.allocator.free(current_working_code);
                        current_working_code = new_buffer;
                    }
                }

                // platform.debug.print("DEBUG C CODE:\n{s}\n", .{current_working_code});
                try output.appendSlice(self.allocator, current_working_code);
                self.allocator.free(current_working_code);
            },
            .Relation => |r| {
                // Les relations deviennent des appels de prédicats en C
                const pred = try self.transpile(r.predicate);
                try writer.print("{s}_check(", .{pred});
                for (r.args, 0..) |arg_id, i| {
                    if (i > 0) try output.appendSlice(self.allocator, ", ");
                    try output.appendSlice(self.allocator, try self.transpile(arg_id));
                }
                try output.appendSlice(self.allocator, ")");
            },

            else => try output.appendSlice(self.allocator, "/* atome_inconnu */"),
        }

        return output.toOwnedSlice(self.allocator);
    }

    /// Enveloppe le code généré dans une fonction exécutable par l'AutoFab
    pub fn generateRunnableC(self: *SurvivalTranspiler, node_id: matrix_lib.BobId) ![]const u8 {
        const logic = try self.transpile(node_id);
        return std.fmt.allocPrint(self.allocator,
            \\#include <stdio.h>
            \\#include <stdbool.h>
            \\#include <string.h>
            \\
            \\extern void notify_bob(const char* msg);
            \\
            \\// --- Injection du code généré ---
            \\{s}
            \\// --------------------------------
            \\
            \\void run() {{
            \\    if (isReservedKeyword("fn")) {{
            \\        notify_bob("Succes : 'fn' est reconnu.");
            \\    }} else {{
            \\        notify_bob("Echec de reconnaissance.");
            \\    }}
            \\}}
        , .{logic});
    }

    /// Remplace récursivement un ID par sa forme canonique (simplifiée)
    pub fn simplify(self: *SurvivalTranspiler, id: matrix_lib.BobId) matrix_lib.BobId {
        platform.dbg("[inference forge SIMPLIFY] kb.rules.len = {d}\n", .{self.kb.rules.items.len});
        return self.matrix.findCanonical(id);
    }

    /// Exemple de règle de saturation : x + 0 => x
    pub fn applyBasicMathRules(self: *SurvivalTranspiler, node_id: matrix_lib.BobId) void {
        const node = self.matrix.nodes.get(node_id) orelse return;

        if (node == .Apply) {
            const func_node = self.matrix.nodes.get(node.Apply.function) orelse return;
            if (func_node == .Symbol and std.mem.eql(u8, func_node.Symbol, "+")) {
                // Si on a (+ x 0), on unifie le noeud avec x
                // (Logique à étendre avec ton moteur de pattern matching)
            }
        }
    }
};
