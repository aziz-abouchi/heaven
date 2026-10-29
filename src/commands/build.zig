// build.zig — bundler incrémental multi-fichiers (2026-10-29)
// Résout les imports récursivement, concat dans un fichier self-contained.
// Pas un compilateur natif (compile-qbe/wasm sont cassés, cf. STATUS).
// Usage : heaven build <dir|file> -o <out.hvn>

const std = @import("std");
const platform = @import("platform");

const Visited = std.StringHashMapUnmanaged(void);
const Import = struct { path: []const u8, resolved: ?[]const u8 };

fn readSource(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    const buf = try allocator.alloc(u8, stat.size);
    errdefer allocator.free(buf);
    _ = try file.readAll(buf);
    return buf;
}

// Extrait les "import "X.hvn"" du source (simple scan de lignes)
fn extractImports(allocator: std.mem.Allocator, source: []const u8, list: *std.ArrayListUnmanaged([]const u8)) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, "import ")) continue;
        // import "X.hvn" [as Y]?
        const q1 = std.mem.indexOfScalar(u8, trimmed, '"') orelse continue;
        const rest = trimmed[q1 + 1 ..];
        const q2 = std.mem.indexOfScalar(u8, rest, '"') orelse continue;
        const path = rest[0..q2];
        try list.append(allocator, try allocator.dupe(u8, path));
    }
}

fn resolveImport(allocator: std.mem.Allocator, importer_dir: []const u8, rel: []const u8) ![]const u8 {
    // Si le chemin commence par un préfixe connu (core/, hab/), on l'utilise direct
    if (std.mem.startsWith(u8, rel, "core/") or
        std.mem.startsWith(u8, rel, "hab/") or
        std.mem.startsWith(u8, rel, "examples/") or
        std.mem.startsWith(u8, rel, "tests/"))
    {
        return try allocator.dupe(u8, rel);
    }
    // Sinon, relatif au fichier importeur
    return try std.fs.path.join(allocator, &.{ importer_dir, rel });
}

fn bundleRecursive(
    allocator: std.mem.Allocator,
    path: []const u8,
    visited: *Visited,
    output: *std.ArrayListUnmanaged(u8),
) !void {
    if (visited.contains(path)) return;
    try visited.put(allocator, try allocator.dupe(u8, path), {});

    const source = try readSource(allocator, path);
    defer allocator.free(source);

    const dir = std.fs.path.dirname(path) orelse ".";

    var imports: std.ArrayListUnmanaged([]const u8) = .{};
    defer {
        for (imports.items) |imp| allocator.free(imp);
        imports.deinit(allocator);
    }
    try extractImports(allocator, source, &imports);

    for (imports.items) |imp| {
        const resolved = try resolveImport(allocator, dir, imp);
        defer allocator.free(resolved);
        bundleRecursive(allocator, resolved, visited, output) catch |err| {
            platform.debug.print("[bundle] warning: {s} not found ({})\n", .{ resolved, err });
        };
    }

    // Marqueur de section + contenu (imports supprimés, déjà inclus)
    try output.writer(allocator).print("\n-- ═══ {s} ═══\n", .{path});
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, trimmed, "import ")) continue;
        try output.writer(allocator).print("{s}\n", .{line});
    }
}

fn collectFiles(allocator: std.mem.Allocator, path: []const u8, list: *std.ArrayListUnmanaged([]const u8)) !void {
    // Trim trailing slash (openFile("dir/") réussit sur Linux, bug)
    const trimmed = std.mem.trimRight(u8, path, "/");
    if (trimmed.len == 0) return;

    // Essayer openDir D'ABORD (détection fiable)
    if (std.fs.cwd().openDir(trimmed, .{ .iterate = true })) |dir_handle| {
        var dir = dir_handle;
        defer dir.close();
        var it = dir.iterate();
        while (try it.next()) |entry| {
            const full = try std.fs.path.join(allocator, &.{ trimmed, entry.name });
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".hvn")) {
                try list.append(allocator, full);
            } else if (entry.kind == .directory) {
                collectFiles(allocator, full, list) catch {};
                allocator.free(full);
            } else {
                allocator.free(full);
            }
        }
        return;
    } else |_| {
        // C'est un fichier
        try list.append(allocator, try allocator.dupe(u8, trimmed));
    }
}

pub fn runBuild(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 3) {
        platform.debug.print("Usage: heaven build <dir|file> -o <output.hvn>\n", .{});
        return error.InvalidArgs;
    }
    const input = args[0];
    const output_path = blk: {
        if (args.len >= 3 and std.mem.eql(u8, args[1], "-o")) break :blk args[2];
        return error.InvalidArgs;
    };

    var files: std.ArrayListUnmanaged([]const u8) = .{};
    defer {
        for (files.items) |f| allocator.free(f);
        files.deinit(allocator);
    }
    try collectFiles(allocator, input, &files);
    platform.debug.print("[build] {d} fichier(s) scannés\n", .{files.items.len});

    var visited: Visited = .{};
    defer {
        var it = visited.iterator();
        while (it.next()) |e| allocator.free(e.key_ptr.*);
        visited.deinit(allocator);
    }

    var output: std.ArrayListUnmanaged(u8) = .{};
    defer output.deinit(allocator);
    try output.appendSlice(allocator, "-- bundle généré par heaven build\n");

    for (files.items) |f| {
        bundleRecursive(allocator, f, &visited, &output) catch |err| {
            platform.debug.print("[build] skip {s}: {}\n", .{ f, err });
        };
    }

    // Écrire le bundle
    const out = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer out.close();
    try out.writeAll(output.items);
    platform.debug.print("[build] écrit {s} ({d} octets, {d} fichiers résolus)\n",
        .{ output_path, output.items.len, visited.count() });
}
