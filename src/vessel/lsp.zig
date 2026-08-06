const std = @import("std");
const matrix_lib = @import("../core/matrix.zig");

pub const LSPHeader = struct {
    content_length: usize,
};

pub fn startLSPServer(matrix: *matrix_lib.Matrix, port: u16) !void {
    const address = std.net.Address.parseIp4("127.0.0.1", port) catch return;
    var server = try address.listen(.{ .reuse_address = true });

    platform.debug.print("[LSP] Serveur Heaven-LSP actif sur port {d}\n", .{port});

    while (true) {
        const conn = try server.accept();
        // Ici, on lirait le flux JSON-RPC et on interrogerait la Matrix
        // Ex: "Où est défini l'Atome 13 ?" -> Matrix répond "Ligne 42 de bootstrap.hvn"
        conn.stream.close();
    }
}
