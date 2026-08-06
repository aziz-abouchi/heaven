const std = @import("std");
const platform = @import("platform");
const autofab = @import("./runtime/autofab.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // On utilise la fonction que tu as écrite dans autofab.zig
    // Elle contient déjà ton shellcode "OK\n"
    const payload = try autofab.AutoFab.generatePayload(allocator);
    defer allocator.free(payload);

    var file = try platform.fs.cwd().createFile("payload.xob", .{});
    defer file.close();

    try file.writeAll(payload);

    platform.debug.print("Artefact viral 'payload.xob' généré avec succès.\n", .{});
}
