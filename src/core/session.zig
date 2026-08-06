const std = @import("std");
const Allocator = std.mem.Allocator;
const ProofEnv = @import("proof").ProofEnv;
const platform = @import("platform");

const SESSION_FILE = ".heaven_session.json";

/// Sauvegarde ProofEnv dans .heaven_session.json
pub fn save(proofs: *const ProofEnv, allocator: Allocator) !void {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);
    const w = buf.writer(allocator);

    try w.writeAll("{\n  \"axioms\": [\n");
    for (proofs.axioms.items, 0..) |ax, i| {
        if (i > 0) try w.writeAll(",\n");
        try std.fmt.format(w, "    {{\"name\": \"{s}\", \"statement\": \"{s}\"}}", .{ ax.name, ax.statement });
    }
    try w.writeAll("\n  ],\n  \"theorems\": [\n");

    var first = true;
    var it = proofs.theorems.iterator();
    while (it.next()) |entry| {
        const thm = entry.value_ptr.*;
        if (!first) try w.writeAll(",\n");
        first = false;
        try std.fmt.format(w, "    {{\"name\": \"{s}\", \"statement\": \"{s}\", \"verified\": {s}}}", .{ thm.name, thm.statement, if (thm.verified) "true" else "false" });
    }
    try w.writeAll("\n  ]\n}\n");

    const file = try platform.fs.cwd().createFile(SESSION_FILE, .{});
    defer file.close();
    try file.writeAll(buf.items);

    platform.debug.print("[SESSION] Sauvegardé → {s}\n", .{SESSION_FILE});
}

/// Charge .heaven_session.json dans ProofEnv
pub fn load(proofs: *ProofEnv, allocator: Allocator) !void {
    const text = platform.fs.cwd().readFileAlloc(allocator, SESSION_FILE, 1024 * 1024) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    defer allocator.free(text);

    // Parser JSON minimaliste — extrait les objets ligne par ligne
    var lines = std.mem.splitScalar(u8, text, '\n');
    var in_axioms = false;
    var in_theorems = false;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t,");
        if (std.mem.indexOf(u8, trimmed, "\"axioms\"") != null) {
            in_axioms = true;
            in_theorems = false;
            continue;
        }
        if (std.mem.indexOf(u8, trimmed, "\"theorems\"") != null) {
            in_theorems = true;
            in_axioms = false;
            continue;
        }
        if (!std.mem.startsWith(u8, trimmed, "{")) continue;

        const name = extractField(trimmed, "name") orelse continue;
        const stmt = extractField(trimmed, "statement") orelse continue;

        const owned_name = try allocator.dupe(u8, name);
        const owned_stmt = try allocator.dupe(u8, stmt);

        if (in_axioms) {
            try proofs.axioms.append(allocator, .{
                .name = owned_name,
                .statement = owned_stmt,
                .lhs = 0,
                .rhs = 0,
                .proof = null,
                .verified = true,
            });
            platform.debug.print("[SESSION] Axiome restauré: {s}\n", .{owned_name});
        } else if (in_theorems) {
            const verified = std.mem.indexOf(u8, trimmed, "\"verified\": true") != null;
            try proofs.theorems.put(allocator, owned_name, .{
                .name = owned_name,
                .statement = owned_stmt,
                .lhs = 0,
                .rhs = 0,
                .proof = null,
                .verified = verified,
            });
            platform.debug.print("[SESSION] Théorème restauré: {s} [{s}]\n", .{ owned_name, if (verified) "prouvé" else "non prouvé" });
        }
    }
}

fn extractField(json_obj: []const u8, field: []const u8) ?[]const u8 {
    var search_buf: [64]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "\"{s}\": \"", .{field}) catch return null;
    const start = (std.mem.indexOf(u8, json_obj, search) orelse return null) + search.len;
    const end = std.mem.indexOfScalarPos(u8, json_obj, start, '"') orelse return null;
    return json_obj[start..end];
}
