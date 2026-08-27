const std = @import("std");
const platform = @import("platform");
const matrix_lib = @import("../../core/matrix.zig");

pub const CScanner = struct {
    allocator: std.mem.Allocator,
    matrix: *matrix_lib.Matrix,

    pub fn absorbHeader(self: *CScanner, path: []const u8) !void {
        const file = try platform.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        var lines = std.mem.split(u8, content, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "//") or std.mem.startsWith(u8, trimmed, "#")) continue;

            // Détection basique de fonction : "type nom("
            if (std.mem.indexOf(u8, trimmed, "(")) |idx| {
                const before_bracket = trimmed[0..idx];
                var parts = std.mem.tokenize(u8, before_bracket, " \t");
                var name: []const u8 = "";
                while (parts.next()) |p| name = p; // Le dernier mot avant '(' est le nom

                if (name.len > 0) {
                    try self.registerSymbol(name);
                }
            }
        }
    }

    fn registerSymbol(self: *CScanner, name: []const u8) !void {
        const node = matrix_lib.BobNode{
            .ExternLink = .{
                .lib_path = "native",
                .symbol_name = try self.allocator.dupe(u8, name),
            },
        };
        _ = try self.matrix.addNode(node);
        // platform.dbg("[ABSORB-C] {s} injecté dans la Matrix.\n", .{name});
    }
};
