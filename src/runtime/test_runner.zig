const std = @import("std");
const platform = @import("platform");
const heaven_expr_mod = @import("heaven_expr");

fn cpuNs(usage: anytype) u64 {
    return @as(u64, @intCast(usage.utime.sec + usage.stime.sec)) * std.time.ns_per_s +
        @as(u64, @intCast(usage.utime.usec + usage.stime.usec)) * std.time.ns_per_us;
}

fn isSkippable(stmt: []const u8) bool {
    const t = std.mem.trim(u8, stmt, " \t\r\n");
    if (t.len == 0) return true;
    if (t[0] == '#') return true;
    if (std.mem.startsWith(u8, t, ";;")) return true;
    if (std.mem.startsWith(u8, t, "--")) return true;
    if (std.mem.startsWith(u8, t, "//")) return true;
    return false;
}

fn displayName(stmt: []const u8) []const u8 {
    var it = std.mem.splitScalar(u8, stmt, '\n');
    while (it.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len == 0) continue;
        if (t[0] == '#') continue;
        if (std.mem.startsWith(u8, t, ";;") or
            std.mem.startsWith(u8, t, "--") or
            std.mem.startsWith(u8, t, "//")) continue;
        return if (t.len > 60) t[0..60] else t;
    }
    return "stmt";
}

/// Découpe en statements. Fin = '\n' à brace_depth 0, hors string.
/// Multi-ligne via `{ ... }` (les accolades sont équilibrées dans le statement).
fn splitStatements(
    allocator: std.mem.Allocator,
    content: []const u8,
    out: *std.ArrayListUnmanaged([]const u8),
) !void {
    var start: usize = 0;
    var brace_depth: usize = 0;
    var in_str = false;
    var i: usize = 0;
    while (i <= content.len) : (i += 1) {
        const at_eof = (i == content.len);
        const c: u8 = if (at_eof) '\n' else content[i];
        if (in_str) {
            if (c == '"') in_str = false;
            continue;
        }
        switch (c) {
            '"' => in_str = true,
            '{' => brace_depth += 1,
            '}' => if (brace_depth > 0) {
                brace_depth -= 1;
            },
            '\n' => if (brace_depth == 0) {
                try out.append(allocator, content[start..i]);
                start = i + 1;
            },
            else => {},
        }
    }
}

/// Retourne true si au moins un test a échoué.
pub fn runTestFile(allocator: std.mem.Allocator, path: []const u8) !bool {
    var heaven = heaven_expr_mod.Heaven.init(allocator) catch @panic("Failed to init Heaven");
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const file = try platform.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    const file_content = try allocator.alloc(u8, stat.size);
    defer allocator.free(file_content);
    _ = try file.readAll(file_content);

    const use_color = if (platform.target.is_windows) false else platform.posix.isatty(platform.posix.STDOUT_FILENO);
    const C_GREEN = if (use_color) "\x1b[32m" else "";
    const C_RED = if (use_color) "\x1b[31m" else "";
    const C_DIM = if (use_color) "\x1b[2m" else "";
    const C_BOLD = if (use_color) "\x1b[1m" else "";
    const C_RESET = if (use_color) "\x1b[0m" else "";

    platform.debug.print("── Running tests from {s} ──\n\n", .{path});

    var passed: usize = 0;
    var failed: usize = 0;
    var neutral: usize = 0;
    var total_wall_ns: u64 = 0;
    var total_cpu_ns: u64 = 0;

    var statements: std.ArrayListUnmanaged([]const u8) = .{};
    defer statements.deinit(allocator);
    try splitStatements(allocator, file_content, &statements);

    for (statements.items) |stmt| {
        if (isSkippable(stmt)) continue;
        const name = displayName(stmt);
        const payload = std.mem.trim(u8, stmt, " \t\r\n");

        const ru0 = platform.profiler.getResourceUsage();
        const w0 = std.time.nanoTimestamp();

        const result_opt = heaven.eval(payload) catch |err| {
            const w1 = std.time.nanoTimestamp();
            const ru1 = platform.profiler.getResourceUsage();
            const wall_ns: u64 = @intCast(w1 - w0);
            const cpu0 = cpuNs(ru0);
            const cpu1 = cpuNs(ru1);
            const cpu_ns = if (cpu1 >= cpu0) cpu1 - cpu0 else 0;
            total_wall_ns += wall_ns;
            total_cpu_ns += cpu_ns;
            platform.debug.print("{s}✗{s} {s} {s}({d:.2}ms, cpu {d:.2}ms){s}\n  {s}error:{s} {}\n", .{
                C_RED,                                          C_RESET,                                       name,    C_DIM,
                @as(f64, @floatFromInt(wall_ns)) / 1_000_000.0, @as(f64, @floatFromInt(cpu_ns)) / 1_000_000.0, C_RESET, C_RED,
                C_RESET,                                        err,
            });
            failed += 1;
            continue;
        };

        const w1 = std.time.nanoTimestamp();
        const ru1 = platform.profiler.getResourceUsage();
        const wall_ns: u64 = @intCast(w1 - w0);
        const cpu0 = cpuNs(ru0);
        const cpu1 = cpuNs(ru1);
        const cpu_ns = if (cpu1 >= cpu0) cpu1 - cpu0 else 0;
        total_wall_ns += wall_ns;
        total_cpu_ns += cpu_ns;

        const timing = try std.fmt.allocPrint(allocator, "{s}({d:.2}ms, cpu {d:.2}ms){s}", .{
            C_DIM,
            @as(f64, @floatFromInt(wall_ns)) / 1_000_000.0,
            @as(f64, @floatFromInt(cpu_ns)) / 1_000_000.0,
            C_RESET,
        });
        defer allocator.free(timing);

        const result = result_opt;
        defer allocator.free(result);

        const is_fail = std.mem.indexOf(u8, result, "✗") != null;
        const is_pass = !is_fail and
            (std.mem.startsWith(u8, result, "✓") or
                std.mem.indexOf(u8, result, ": ✓") != null);

        if (is_fail) {
            platform.debug.print("{s}✗{s} {s} → {s} {s}\n", .{ C_RED, C_RESET, name, result, timing });
            failed += 1;
        } else if (is_pass) {
            platform.debug.print("{s}✓{s} {s} → {s} {s}\n", .{ C_GREEN, C_RESET, name, result, timing });
            passed += 1;
        } else {
            platform.debug.print("· {s} → {s} {s}\n", .{ name, result, timing });
            neutral += 1;
        }
    }

    const total = passed + failed;
    const final_usage = platform.profiler.getResourceUsage();
    const rss_kb: u64 = if (platform.target.is_darwin)
        final_usage.maxrss / 1024
    else
        final_usage.maxrss;

    platform.debug.print("\n── Tests finished ──\n", .{});
    platform.debug.print("{s}  ✓ {d} passed{s}\n", .{ C_GREEN, passed, C_RESET });
    if (failed > 0)
        platform.debug.print("{s}  ✗ {d} failed{s}\n", .{ C_RED, failed, C_RESET });
    platform.debug.print("  ·  {d} neutral\n", .{neutral});
    platform.debug.print("{s}  ─────────────{s}\n", .{ C_BOLD, C_RESET });
    platform.debug.print("{s}  Total: {d} / {d}{s}\n", .{ C_BOLD, passed, total, C_RESET });

    const n_meas = passed + failed + neutral;
    const avg_wall_ms: f64 = if (n_meas > 0)
        @as(f64, @floatFromInt(total_wall_ns)) / 1_000_000.0 / @as(f64, @floatFromInt(n_meas))
    else
        0.0;
    const avg_cpu_ms: f64 = if (n_meas > 0)
        @as(f64, @floatFromInt(total_cpu_ns)) / 1_000_000.0 / @as(f64, @floatFromInt(n_meas))
    else
        0.0;

    platform.debug.print("\n{s}  ── Performance ──{s}\n", .{ C_BOLD, C_RESET });
    platform.debug.print("  {s}wall time:{s} {d:>8.2} ms  {s}(avg {d:.2} ms / test){s}\n", .{
        C_DIM,                                                C_RESET,
        @as(f64, @floatFromInt(total_wall_ns)) / 1_000_000.0, C_DIM,
        avg_wall_ms,                                          C_RESET,
    });
    platform.debug.print("  {s}cpu time:{s}  {d:>8.2} ms  {s}(avg {d:.2} ms / test){s}\n", .{
        C_DIM,                                               C_RESET,
        @as(f64, @floatFromInt(total_cpu_ns)) / 1_000_000.0, C_DIM,
        avg_cpu_ms,                                          C_RESET,
    });
    platform.debug.print("  {s}peak mem:{s}  {d:>8} KB\n", .{ C_DIM, C_RESET, rss_kb });

    return failed > 0;
}

/// Parcourt tous les *.hvn d'un dossier et lance leur suite.
/// Retourne true si au moins un fichier a échoué.
pub fn runTestDir(allocator: std.mem.Allocator, dir_path: []const u8) !bool {
    var dir = try platform.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    var any_failed = false;
    var files: usize = 0;

    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".hvn")) continue;
        const full_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
        defer allocator.free(full_path);
        const failed = runTestFile(allocator, full_path) catch |err| {
            platform.debug.print("✗ {s}: {}\n", .{ full_path, err });
            any_failed = true;
            continue;
        };
        if (failed) any_failed = true;
        files += 1;
    }

    if (files == 0) {
        platform.debug.print("(aucun fichier .hvn dans {s})\n", .{dir_path});
    }
    return any_failed;
}
