//! Commandes WASM : compile et bench via wasmtime.
//!
//! `compile-wasm <src.hvn> -o <bin.wat>` : parse + MIR + emitWat,
//! ecrit un fichier WAT. On reste en WAT : wasmtime accepte le
//! texte directement, pas besoin de wat2wasm.

const std = @import("std");
const expr = @import("expr");
const parse = @import("parse");
const heaven_expr = @import("heaven_expr");
const engine_expr = @import("engine_expr");
const mir = @import("mir");
const mir_wat = @import("mir_wat");
const platform = @import("platform");

const Store = expr.Store;
const MirFunction = mir.MirFunction;
const Reg = mir.Reg;

fn compileRoot(
    alloc: std.mem.Allocator,
    store: *Store,
    engine: *engine_expr.Engine,
    body: expr.Id,
) !MirFunction {
    var mf = MirFunction.initWithStore(alloc, store);
    errdefer mf.deinit();
    mf.engine = engine;
    try mf.precompileUserFns();
    const entry = try mf.newBlock();
    var locals = std.AutoHashMap(u32, Reg).init(alloc);
    defer locals.deinit();
    const result = try mf.compileExpr(store, body, entry, locals);
    if (mf.blocks.items[entry].terminator == .fallthrough) {
        mf.blocks.items[entry].terminator = .{ .ret = result };
    }
    return mf;
}

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

fn parseLastExpr(
    alloc: std.mem.Allocator,
    heaven: *heaven_expr.Heaven,
    source: []const u8,
) !expr.Id {
    var parser = parse.Parser.init(heaven.store, &heaven.engine, &heaven.env, alloc);
    defer parser.deinit();

    var last: ?expr.Id = null;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (isSkippable(line)) continue;
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (isDefinition(trimmed)) {
            const msg = heaven.eval(trimmed) catch |e| {
                platform.debug.print(
                    "[compile-wasm] warn: definition ignoree ({s}): {s}\n",
                    .{ @errorName(e), trimmed[0..@min(trimmed.len, 60)] },
                );
                continue;
            };
            alloc.free(msg);
            continue;
        }
        const parsed = try parser.parseSExpr(trimmed);
        last = try heaven.store.lowerRec(parsed);
    }
    return last orelse error.NoExpression;
}

pub fn runCompileWasm(
    alloc: std.mem.Allocator,
    src_path: []const u8,
    out_path: []const u8,
) !void {
    const source = try std.fs.cwd().readFileAlloc(alloc, src_path, 16 * 1024 * 1024);
    defer alloc.free(source);

    var heaven = heaven_expr.Heaven.init(alloc) catch return error.HeavenInit;
    defer {
        heaven.deinit();
        alloc.destroy(heaven);
    }

    const body = try parseLastExpr(alloc, heaven, source);
    var mf = try compileRoot(alloc, heaven.store, &heaven.engine, body);
    defer mf.deinit();

    const wat = try mir_wat.emitWat(alloc, &mf);
    defer alloc.free(wat);

    try std.fs.cwd().writeFile(.{ .sub_path = out_path, .data = wat });
    platform.debug.print("[COMPILE-WASM] {s} -> {s}\n", .{ src_path, out_path });
}

/// Stats agregees sur N runs (meme structure que qbe_cmd).
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
    for (samples) |s| sum += s;
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
        "[BENCH-WASM] {s} ({s}, {d} runs)\n" ++
            "  min    : {d:.3} ms\n" ++
            "  median : {d:.3} ms\n" ++
            "  mean   : {d:.3} ms\n" ++
            "  max    : {d:.3} ms\n",
        .{ label, kind, s.iterations, ms(s.min_ns), ms(s.median_ns), ms(s.mean_ns), ms(s.max_ns) },
    );
}

/// Compile puis execute le WAT N fois via `wasmtime run --invoke main`.
pub fn runBenchWasm(
    alloc: std.mem.Allocator,
    src_path: []const u8,
    iterations: u32,
    loop_count: u32,
) !void {
    const n: u32 = if (iterations == 0) 100 else iterations;
    const m: u32 = if (loop_count == 0) 1 else loop_count;

    var tmp_dir = try std.fs.cwd().makeOpenPath(".zig-wasm-tmp", .{});
    defer tmp_dir.close();

    // 1. Compiler en WAT dans tmp_dir/prog.wat
    {
        const source = try std.fs.cwd().readFileAlloc(alloc, src_path, 16 * 1024 * 1024);
        defer alloc.free(source);

        var heaven = heaven_expr.Heaven.init(alloc) catch return error.HeavenInit;
        defer {
            heaven.deinit();
            alloc.destroy(heaven);
        }
        const body = try parseLastExpr(alloc, heaven, source);
        var mf = try compileRoot(alloc, heaven.store, &heaven.engine, body);
        defer mf.deinit();
        const wat = try mir_wat.emitWatLoop(alloc, &mf, m);
        defer alloc.free(wat);
        try tmp_dir.writeFile(.{ .sub_path = "prog.wat", .data = wat });
    }

    // 2. Verifier que wasmtime est dispo
    const wat_path = try std.fs.cwd().realpathAlloc(alloc, ".zig-wasm-tmp/prog.wat");
    defer alloc.free(wat_path);
    std.fs.accessAbsolute(wat_path, .{}) catch return error.WatNotFound;

    // 3. Mesurer N executions
    var wall_samples = try alloc.alloc(u64, n);
    defer alloc.free(wall_samples);
    var cpu_samples = try alloc.alloc(u64, n);
    defer alloc.free(cpu_samples);

    // Snapshot energie / temperature avant
    const energy_before = platform.profiler.readEnergyUj();
    const temp_start = platform.profiler.readTempMc(0) orelse 0;

    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const ru0 = platform.profiler.getChildrenUsage();

        const t0 = std.time.nanoTimestamp();
        // WASM n'a pas de stack native qui grandit : la valeur par
        // defaut (~64 KB) fait stack overflow sur les recursions
        // profondes. On alloue 64 MB (largement suffisant pour 1M
        // frames). Idealement, mir_wat ferait du TCO (recursion tail
        // -> boucle WASM) et ce flag deviendrait inutile.
        var child = std.process.Child.init(
            &.{ "wasmtime", "run", "-W", "max-wasm-stack=67108864", "--invoke", "main", wat_path },
            alloc,
        );
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        try child.spawn();
        _ = try child.wait();
        const t1 = std.time.nanoTimestamp();

        const ru1 = platform.profiler.getChildrenUsage();

        wall_samples[i] = @intCast(t1 - t0);
        const delta_s: i64 = @intCast(ru1.utime.sec + ru1.stime.sec
            - ru0.utime.sec - ru0.stime.sec);
        const delta_us: i64 = @intCast(ru1.utime.usec + ru1.stime.usec
            - ru0.utime.usec - ru0.stime.usec);
        const delta_ns: i64 = delta_s * std.time.ns_per_s + delta_us * std.time.ns_per_us;
        cpu_samples[i] = if (delta_ns > 0) @intCast(delta_ns) else 0;
    }

    const temp_end = platform.profiler.readTempMc(0) orelse 0;

    platform.debug.print(
        "[BENCH-WASM] {s} : {d} spawns x {d} iterations internes = {d} total\n",
        .{ src_path, n, m, @as(u64, n) * @as(u64, m) },
    );
    const sw = computeStats(wall_samples);
    printStats("wall", src_path, sw);
    const sc = computeStats(cpu_samples);
    printStats("cpu", src_path, sc);

    // Energy
    if (energy_before) |e0| {
        if (platform.profiler.readEnergyUj()) |e1| {
            if (e1 > e0) {
                const per_run_uj: f64 = @as(f64, @floatFromInt(e1 - e0)) / @as(f64, @floatFromInt(n));
                platform.debug.print(
                    "[BENCH-WASM] energy total : {d} uJ  ({d:.1} uJ/run)\n",
                    .{ e1 - e0, per_run_uj },
                );
            }
        }
    } else {
        platform.debug.print(
            "[BENCH-WASM] energy : indisponible (RAPL inaccessible)\n",
            .{},
        );
    }
    platform.debug.print(
        "[BENCH-WASM] temp debut : {d:.1} C, fin : {d:.1} C (delta {d:.1} C)\n",
        .{
            @as(f64, @floatFromInt(temp_start)) / 1000.0,
            @as(f64, @floatFromInt(temp_end)) / 1000.0,
            @as(f64, @floatFromInt(temp_end - temp_start)) / 1000.0,
        },
    );
}
