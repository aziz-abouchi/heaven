const std = @import("std");
const platform = @import("platform");
const matrix_lib = @import("../../core/matrix.zig");

pub const GrammarBridge = struct {
    matrix: *matrix_lib.Matrix,
    allocator: std.mem.Allocator,

    pub fn injectTreeSitter(self: *GrammarBridge, lang: []const u8, json_path: []const u8) !void {
        const file = try platform.fs.cwd().readFileAlloc(self.allocator, json_path, 1024 * 1024);
        defer self.allocator.free(file);

        var parser = std.json.Parser.init(self.allocator, .copy_strings);
        defer parser.deinit();
        var tree = try parser.parse(file);
        defer tree.deinit();

        // On parcourt les types de nœuds définis par Tree-sitter
        for (tree.root.Array.items) |node_type| {
            const type_name = node_type.Object.get("type").?.String;

            // Création de l'identifiant de spécification unique
            const spec_key = try std.fmt.allocPrint(self.allocator, "SPEC_{s}_{s}", .{ lang, type_name });
            defer self.allocator.free(spec_key);

            const kid = try self.matrix.addUniqueSymbol(spec_key);

            // Si le nœud a des champs (children/fields), on les lie comme des trous potentiels
            if (node_type.Object.get("fields")) |fields| {
                var f_it = fields.Object.iterator();
                while (f_it.next()) |field| {
                    const fid = try self.matrix.addUniqueSymbol(field.key_ptr.*);
                    try self.matrix.addEdge(kid, fid, "HAS_FIELD");
                }
            }
        }
    }
};
