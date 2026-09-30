//! bench-interp : evaluate une expression N fois avec M iterations
//! internes, mesure wall/cpu/energy/temp.
//!
//! Meme interface que bench-qbe / bench-wasm, mais l'evaluation se
//! fait in-process via heaven.eval (pas de binaire, pas de spawn).

const std = @import("std");
const heaven_expr = @import("heaven_expr");
const platform = @import("platform");

fn isSkippable(line: []const u8) bool {
    const t = std.mem.trim(u8, line, " \t\r");
    if (t.len == 0) return true;
    if (t[0] == '#') return true;
    if (std.mem.startsWith(u8, t, ";;")) return true;
    if (std.mem.startsWith(u8, t, "--")) return true;
    if (std.mem.startsWith(u8, t, "//")) return true;
    return false;
}

fn isDefinition(trimmed: []const u8) bool {
    if (std.mem.startsWith(u8, trimmed, "fn ")) return true;
    if (std.mem.startsWith(u8, trimmed, "let ")) return true;
    if (std.mem.startsWith(u8, trimmed, "data ")) return true;
    if (std.mem.startsWith(u8, trimmed, "theorem ")) return true;
    if (std.mem.startsWith(u8, trimmed, "actor ")) return true;
    const eq_idx = std.mem.indexOfScalar(u8, trimmed, '=') orelse return false;
    const paren_idx = std.mem.indexOfScalar(u8, trimmed, '(') orelse return false;
    if (paren_idx > eq_idx) return false;
    if (eq_idx + 1 < trimmed.len and trimmed[eq_idx + 1] == '=') return false;
    return true;
}

fn cpuNsFrom(ru: platform.profiler.ResourceUsage) u64 {
    const u = @as(u64, @intCast(ru.utime.sec)) * std.time.ns_per_s
        + @as(u64, @intCast(ru.utime.usec)) * std.time.ns_per_us;
    const s = @as(u64, @intCast(ru.stime.sec)) * std.time.ns_per_s
        + @as(u64, @intCast(ru.stime.usec)) * std.time.ns_per_us;
    return u + s;
}

const BenchStats = struct {
    min_ns: u64,
    max_ns: u64,
    median_ns: u64,
    mean_ns: u64,
    iterations: u32,
};

fn computeStats(samples: []u64) BenchStats {
    std.mem.sort(u64, samples, {}, std.sort.asc(u64));
    var sum: u128 = 0;
    for (samples) |x| sum += x;
    const n: u64 = @intCast(samples.len);
    return .{
        .min_ns = samples[0],
        .max_ns = samples[samples.len - 1],
        .median_ns = samples[samples.len / 2],
        .mean_ns = @intCast(sum / n),
        .iterations = @intCast(samples.len),
    };
}

fn printStats(kind: []const u8, label: []const u8, s: BenchStats) void {
    const ms = struct {
        fn f(ns: u64) f64 {
            return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
        }
    }.f;
    platform.debug.print(
        "[BENCH-INTERP] {s} ({s}, {d} runs)\n" ++
            "  min    : {d:.3} ms\n" ++
            "  median : {d:.3} ms\n" ++
            "  mean   : {d:.3} ms\n" ++
            "  max    : {d:.3} ms\n",
        .{ label, kind, s.iterations, ms(s.min_ns), ms(s.median_ns), ms(s.mean_ns), ms(s.max_ns) },
    );
}

pub fn runBenchInterp(
    alloc: std.mem.Allocator,
    src_path: []const u8,
    iterations: u32,
    loop_count: u32,
) !void {
    const n: u32 = if (iterations == 0) 10 else iterations;
    const m: u32 = if (loop_count == 0) 1 else loop_count;

    const source = try std.fs.cwd().readFileAlloc(alloc, src_path, 16 * 1024 * 1024);
    defer alloc.free(source);

    var heaven = heaven_expr.Heaven.init(alloc) catch return error.HeavenInit;
    defer {
        heaven.deinit();
        alloc.destroy(heaven);
    }

    // 1. Eval des definitions (peuple engine.fns), on garde la
    // derniere expression non-definition comme cible.
    var last_expr: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (isSkippable(trimmed)) continue;
        if (isDefinition(trimmed)) {
            const msg = heaven.eval(trimmed) catch |e| {
                platform.debug.print(
                    "[bench-interp] warn: definition ignoree ({s}): {s}\n",
                    .{ @errorName(e), trimmed[0..@min(trimmed.len, 60)] },
                );
                continue;
            };
            alloc.free(msg);
            continue;
        }
        last_expr = trimmed;
    }
    const expr = last_expr orelse return error.NoExpression;

    // 2. Warmup (1 run)
    {
        const msg = try heaven.eval(expr);
        alloc.free(msg);
    }

    // 3. Mesure
    var wall_samples = try alloc.alloc(u64, n);
    defer alloc.free(wall_samples);
    var cpu_samples = try alloc.alloc(u64, n);
    defer alloc.free(cpu_samples);

    const energy_before = platform.profiler.readEnergyUj();
    const temp_start = platform.profiler.readTempMc(0) orelse 0;

    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const ru0 = platform.profiler.getResourceUsage();
        const t0 = std.time.nanoTimestamp();
        var k: u32 = 0;
        while (k < m) : (k += 1) {
            const msg = try heaven.eval(expr);
            alloc.free(msg);
        }
        const t1 = std.time.nanoTimestamp();
        const ru1 = platform.profiler.getResourceUsage();
        wall_samples[i] = @intCast(t1 - t0);
        const c0 = cpuNsFrom(ru0);
        const c1 = cpuNsFrom(ru1);
        cpu_samples[i] = if (c1 >= c0) c1 - c0 else 0;
    }

    const temp_end = platform.profiler.readTempMc(0) orelse 0;

    // 4. Rapport
    platform.debug.print(
        "[BENCH-INTERP] {s} : {d} runs x {d} iterations internes = {d} total\n",
        .{ src_path, n, m, @as(u64, n) * @as(u64, m) },
    );
    printStats("wall", src_path, computeStats(wall_samples));
    printStats("cpu", src_path, computeStats(cpu_samples));

    if (energy_before) |e0| {
        if (platform.profiler.readEnergyUj()) |e1| {
            if (e1 > e0) {
                const per_run_uj: f64 = @as(f64, @floatFromInt(e1 - e0)) / @as(f64, @floatFromInt(n));
                platform.debug.print(
                    "[BENCH-INTERP] energy total : {d} uJ  ({d:.1} uJ/run)\n",
                    .{ e1 - e0, per_run_uj },
                );
            }
        }
    } else {
        platform.debug.print("[BENCH-INTERP] energy : indisponible\n", .{});
    }
    platform.debug.print(
        "[BENCH-INTERP] temp debut : {d:.1} C, fin : {d:.1} C (delta {d:.1} C)\n",
        .{
            @as(f64, @floatFromInt(temp_start)) / 1000.0,
            @as(f64, @floatFromInt(temp_end)) / 1000.0,
            @as(f64, @floatFromInt(temp_end - temp_start)) / 1000.0,
        },
    );
}
