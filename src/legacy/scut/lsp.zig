const std = @import("std");
const matrix_lib = @import("../core/matrix.zig");

pub const HeavenLSP = struct {
    matrix: *matrix_lib.Matrix,
    allocator: std.mem.Allocator,

    pub fn handleRequest(self: *HeavenLSP, raw_json: []const u8) !void {
        // Parse du JSON-RPC entrant
        // Si méthode == "textDocument/definition" :
        // 1. Trouver le symbole sous le curseur
        // 2. Chercher dans matrix.nodes
        // 3. Répondre avec le Location JSON
    }

    fn sendResponse(self: *HeavenLSP, id: i32, result: []const u8) !void {
        const header = "Content-Length: ";
        // Formatage standard LSP...
    }
};
