const std = @import("std");
const Allocator = std.mem.Allocator;
const ProofEnv = @import("proof").ProofEnv;
const proof_status = @import("proof_status");
const Status = proof_status.Status;
const platform = @import("platform");

const SESSION_FILE = ".heaven_session.json";

/// Sauvegarde ProofEnv dans .heaven_session.json
pub fn save(proofs: *const ProofEnv, allocator: Allocator) !void {
    return saveTo(proofs, allocator, SESSION_FILE);
}

fn saveTo(proofs: *const ProofEnv, allocator: Allocator, path: []const u8) !void {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);
    const w = buf.writer(allocator);

    try w.writeAll("{\n  \"axioms\": [\n");
    for (proofs.axioms.items, 0..) |ax, i| {
        if (i > 0) try w.writeAll(",\n");
        try std.fmt.format(w, "    {{\"name\": \"{s}\", \"statement\": \"{s}\", \"status\": \"{s}\"}}", .{ ax.name, ax.statement, @tagName(ax.status) });
    }
    try w.writeAll("\n  ],\n  \"theorems\": [\n");

    var first = true;
    var it = proofs.theorems.iterator();
    while (it.next()) |entry| {
        const thm = entry.value_ptr.*;
        if (!first) try w.writeAll(",\n");
        first = false;
        try std.fmt.format(w, "    {{\"name\": \"{s}\", \"statement\": \"{s}\", \"verified\": {s}, \"status\": \"{s}\"}}", .{ thm.name, thm.statement, if (proof_status.isProved(thm.status)) "true" else "false", @tagName(thm.status) });
    }
    try w.writeAll("\n  ]\n}\n");

    const file = try platform.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(buf.items);

    // platform.dbg("[SESSION] Sauvegardé → {s}\n", .{SESSION_FILE});
}

/// Charge .heaven_session.json dans ProofEnv
pub fn load(proofs: *ProofEnv, allocator: Allocator) !void {
    return loadFrom(proofs, allocator, SESSION_FILE);
}

fn loadFrom(proofs: *ProofEnv, allocator: Allocator, path: []const u8) !void {
    const text = platform.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch |err| {
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
                .status = .axiom,
            });
            // platform.dbg("[SESSION] Axiome restauré: {s}\n", .{owned_name});
        } else if (in_theorems) {
            const status: Status = blk: {
                if (extractField(trimmed, "status")) |raw| {
                    break :blk parseStatus(raw) orelse .legacy_unclassified;
                }
                if (std.mem.indexOf(u8, trimmed, "\"verified\": true") != null) {
                    break :blk .legacy_unclassified;
                }
                break :blk .proposed;
            };
            try proofs.theorems.put(allocator, owned_name, .{
                .name = owned_name,
                .statement = owned_stmt,
                .lhs = 0,
                .rhs = 0,
                .proof = null,
                .status = status,
            });
            // platform.dbg("[SESSION] Théorème restauré: {s} [{s}]\n", .{ owned_name, if (verified) "prouvé" else "non prouvé" });
        }
    }
}

fn parseStatus(s: []const u8) ?Status {
    if (std.mem.eql(u8, s, "proposed")) return .proposed;
    if (std.mem.eql(u8, s, "solved")) return .solved;
    if (std.mem.eql(u8, s, "axiom")) return .axiom;
    if (std.mem.eql(u8, s, "canonically_equivalent")) return .canonically_equivalent;
    if (std.mem.eql(u8, s, "trusted")) return .trusted;
    if (std.mem.eql(u8, s, "kernel_certified")) return .kernel_certified;
    if (std.mem.eql(u8, s, "legacy_unclassified")) return .legacy_unclassified;
    return null;
}

fn extractField(json_obj: []const u8, field: []const u8) ?[]const u8 {
    var search_buf: [64]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "\"{s}\": \"", .{field}) catch return null;
    const start = (std.mem.indexOf(u8, json_obj, search) orelse return null) + search.len;
    const end = std.mem.indexOfScalarPos(u8, json_obj, start, '"') orelse return null;
    return json_obj[start..end];
}

// --- B3 migration tests (2026-11-16) ---

const TEST_SESSION_PATH = "/tmp/.heaven_session_b3_test.json";

fn writeTestSessionFile(content: []const u8) !void {
    const file = try std.fs.cwd().createFile(TEST_SESSION_PATH, .{});
    defer file.close();
    try file.writeAll(content);
}

fn cleanupTestSession() void {
    std.fs.cwd().deleteFile(TEST_SESSION_PATH) catch {};
}

test "save_load_roundtrip_theorem" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var proofs1 = ProofEnv.init(alloc);
    try proofs1.theorems.put(alloc, "t1", .{
        .name = "t1",
        .statement = "x + 0 = x",
        .lhs = 0,
        .rhs = 0,
        .proof = null,
        .status = .kernel_certified,
    });
    try saveTo(&proofs1, alloc, TEST_SESSION_PATH);
    defer cleanupTestSession();

    var proofs2 = ProofEnv.init(alloc);
    try loadFrom(&proofs2, alloc, TEST_SESSION_PATH);

    const thm = proofs2.theorems.get("t1") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(Status.kernel_certified, thm.status);
    try std.testing.expect(proof_status.isProved(thm.status));
}

test "load_legacy_verified_true_maps_to_legacy_unclassified" {
    try writeTestSessionFile(
        "{\n  \"axioms\": [],\n  \"theorems\": [\n    {\"name\": \"x\", \"statement\": \"s\", \"verified\": true}\n  ]\n}\n"
    );
    defer cleanupTestSession();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var proofs = ProofEnv.init(alloc);
    try loadFrom(&proofs, alloc, TEST_SESSION_PATH);
    const thm = proofs.theorems.get("x") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(Status.legacy_unclassified, thm.status);
    try std.testing.expect(!proof_status.isProved(thm.status));
}

test "load_legacy_verified_false_maps_to_proposed" {
    try writeTestSessionFile(
        "{\n  \"axioms\": [],\n  \"theorems\": [\n    {\"name\": \"x\", \"statement\": \"s\", \"verified\": false}\n  ]\n}\n"
    );
    defer cleanupTestSession();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var proofs = ProofEnv.init(alloc);
    try loadFrom(&proofs, alloc, TEST_SESSION_PATH);
    const thm = proofs.theorems.get("x") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(Status.proposed, thm.status);
    try std.testing.expect(!proof_status.isProved(thm.status));
}

test "load_new_status_kernel_certified" {
    try writeTestSessionFile(
        "{\n  \"axioms\": [],\n  \"theorems\": [\n    {\"name\": \"x\", \"statement\": \"s\", \"verified\": true, \"status\": \"kernel_certified\"}\n  ]\n}\n"
    );
    defer cleanupTestSession();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var proofs = ProofEnv.init(alloc);
    try loadFrom(&proofs, alloc, TEST_SESSION_PATH);
    const thm = proofs.theorems.get("x") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(Status.kernel_certified, thm.status);
    try std.testing.expect(proof_status.isProved(thm.status));
}

test "load_unknown_status_falls_back_to_legacy_unclassified" {
    try writeTestSessionFile(
        "{\n  \"axioms\": [],\n  \"theorems\": [\n    {\"name\": \"x\", \"statement\": \"s\", \"verified\": true, \"status\": \"garbage_xyz\"}\n  ]\n}\n"
    );
    defer cleanupTestSession();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var proofs = ProofEnv.init(alloc);
    try loadFrom(&proofs, alloc, TEST_SESSION_PATH);
    const thm = proofs.theorems.get("x") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(Status.legacy_unclassified, thm.status);
    try std.testing.expect(!proof_status.isProved(thm.status));
}

