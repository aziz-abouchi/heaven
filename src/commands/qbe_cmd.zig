//! Commandes QBE : compile et bench.
//!
//! `compile-qbe <src.hvn> -o <bin>` : parse le fichier, compile la
//! DERNIERE expression non-vide en MIR puis QBE, produit un binaire
//! natif via qbe + cc.
//!
//! `bench-qbe <src.hvn> [N]` : compile une fois, execute le binaire
//! N fois, affiche les stats (wall, rss, cpu).

const std = @import("std");
const expr = @import("expr");
const parse = @import("parse");
const heaven_expr = @import("heaven_expr");
const engine_expr = @import("engine_expr");
const mir = @import("mir");
const mir_qbe = @import("mir_qbe");
const platform = @import("platform");
const build_options = @import("build_options");

const Store = expr.Store;
const MirFunction = mir.MirFunction;
const Reg = mir.Reg;

/// Compile une expression unique en MirFunction.
/// Pattern identique a compileRoot() dans test_mir_qbe.zig.
fn compileRoot(
    alloc: std.mem.Allocator,
    store: *Store,
    engine: *engine_expr.Engine,
    body: expr.Id,
) !MirFunction {
    var mf = MirFunction.initWithStore(alloc, store);
    errdefer mf.deinit();
    mf.engine = engine;
    // Precompiler les fonctions utilisateur (fn name(args) = body)
    // en fn_defs MIR. Necessaire pour resoudre les call_user (et
    // passer checkCallUsers a l'emission).
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

/// Parse le fichier, renvoie la DERNIERE expression non-vide.
/// On garde une seule expression : le wrapper $main printf le
/// resultat i64, c'est notre "programme" pour ce soir.
/// Detecte une ligne de definition (fn, let, data, theorem) qui doit
/// etre evaluee pour peupler engine.fns / engine.macros / etc., plutot
/// que compilee directement en MIR.
fn isDefinition(trimmed: []const u8) bool {
    if (std.mem.startsWith(u8, trimmed, "fn ")) return true;
    if (std.mem.startsWith(u8, trimmed, "let ")) return true;
    if (std.mem.startsWith(u8, trimmed, "data ")) return true;
    if (std.mem.startsWith(u8, trimmed, "theorem ")) return true;
    if (std.mem.startsWith(u8, trimmed, "actor ")) return true;
    // Pattern `name(args) = body` ou `name(args) := body` : definition
    // de fonction sans prefixe `fn`.
    const eq_idx = std.mem.indexOfScalar(u8, trimmed, '=') orelse return false;
    const paren_idx = std.mem.indexOfScalar(u8, trimmed, '(') orelse return false;
    if (paren_idx > eq_idx) return false;
    // Exclure les comparaisons (== , <= , >= , !=)
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

        // Les definitions sont EVALUEES (pour peupler engine.fns) puis
        // ignorees pour la compilation MIR. eval() retourne un message
        // alloue qu'il faut liberer.
        if (isDefinition(trimmed)) {
            const msg = heaven.eval(trimmed) catch |e| {
                platform.debug.print(
                    "[compile-qbe] warn: definition ignoree ({s}): {s}\n",
                    .{ @errorName(e), trimmed[0..@min(trimmed.len, 60)] },
                );
                continue;
            };
            alloc.free(msg);
            continue;
        }

        // Expression : parse + lower. La derniere gagne (le programme
        // compile est l'unique expression resultat).
        const parsed = try parser.parseSExpr(trimmed);
        last = try heaven.store.lowerRec(parsed);
    }
    return last orelse error.NoExpression;
}

/// Compile `<src_path>` en binaire natif `<out_path>`.
pub fn runCompileQbe(
    alloc: std.mem.Allocator,
    src_path: []const u8,
    out_path: []const u8,
) !void {
    // 1. Lire le source
    const source = try std.fs.cwd().readFileAlloc(alloc, src_path, 16 * 1024 * 1024);
    defer alloc.free(source);

    // 2. Init Heaven + parse
    var heaven = heaven_expr.Heaven.init(alloc) catch return error.HeavenInit;
    defer {
        heaven.deinit();
        alloc.destroy(heaven);
    }

    const body = try parseLastExpr(alloc, heaven, source);

    // 3. MIR
    var mf = try compileRoot(alloc, heaven.store, &heaven.engine, body);
    defer mf.deinit();

    // 4. QBE IL
    const ssa = try mir_qbe.emitQbe(alloc, &mf);
    defer alloc.free(ssa);

    // 5. Ecrire dans un repertoire temporaire
    const qbe_path = build_options.qbe_path;
    std.fs.accessAbsolute(qbe_path, .{}) catch {
        platform.debug.print(
            "[COMPILE-QBE] QBE introuvable: {s}. Lance `bash build.sh`.\n",
            .{qbe_path},
        );
        return error.QbeNotFound;
    };

    var tmp_dir = try std.fs.cwd().makeOpenPath(".zig-qbe-tmp", .{});
    defer tmp_dir.close();

    try tmp_dir.writeFile(.{ .sub_path = "prog.ssa", .data = ssa });

    // 6. qbe -> prog.s
    try runChild(alloc, &.{ qbe_path, "-o", "prog.s", "prog.ssa" }, tmp_dir);

    // 7. cc -> prog
    try runChild(alloc, &.{ "cc", "-no-pie", "prog.s", "-o", "prog" }, tmp_dir);

    // 8. Copier prog vers out_path, puis rendre executable
    const bin = try tmp_dir.readFileAlloc(alloc, "prog", 32 * 1024 * 1024);
    defer alloc.free(bin);
    try std.fs.cwd().writeFile(.{ .sub_path = out_path, .data = bin });
    // Le bit executable n'est pas conserve par writeFile.
    const out_file = try std.fs.cwd().openFile(out_path, .{});
    defer out_file.close();
    try out_file.chmod(0o755);

    platform.debug.print("[COMPILE-QBE] {s} -> {s}\n", .{ src_path, out_path });
}

fn runChild(alloc: std.mem.Allocator, argv: []const []const u8, cwd: std.fs.Dir) !void {
    var child = std.process.Child.init(argv, alloc);
    child.cwd_dir = cwd;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();
    const stdout_data = child.stdout.?.readToEndAlloc(alloc, 1024 * 1024) catch "";
    defer alloc.free(stdout_data);
    const stderr_data = child.stderr.?.readToEndAlloc(alloc, 1024 * 1024) catch "";
    defer alloc.free(stderr_data);
    const term = try child.wait();
    if (term != .Exited or term.Exited != 0) {
        platform.debug.print("[COMPILE-QBE] `{s}` stderr:\n{s}\n", .{ argv[0], stderr_data });
        return error.ChildFailed;
    }
}

/// Stats agregees sur N runs.
const BenchStats = struct {
    min_ns: u64,
    max_ns: u64,
    median_ns: u64,
    mean_ns: u64,
    iterations: u32,
};

/// Stats supplementaires : energie, temperature, RSS pic.
const ExtraStats = struct {
    energy_uj: u64 = 0,
    temp_start_mc: i64 = 0,
    temp_end_mc: i64 = 0,
    rss_peak_kb: u64 = 0,
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
        "[BENCH-QBE] {s} ({s}, {d} runs)\n" ++
            "  min    : {d:.3} ms\n" ++
            "  median : {d:.3} ms\n" ++
            "  mean   : {d:.3} ms\n" ++
            "  max    : {d:.3} ms\n",
        .{ label, kind, s.iterations, ms(s.min_ns), ms(s.median_ns), ms(s.mean_ns), ms(s.max_ns) },
    );
}

/// Compile puis execute le binaire N fois. Mesure le wall time
/// par run, affiche min/median/mean/max.
pub fn runBenchQbe(
    alloc: std.mem.Allocator,
    src_path: []const u8,
    iterations: u32,
    loop_count: u32,
) !void {
    const n: u32 = if (iterations == 0) 100 else iterations;
    const m: u32 = if (loop_count == 0) 1 else loop_count;

    // Repertoire temporaire pour le binaire.
    var tmp_dir = try std.fs.cwd().makeOpenPath(".zig-qbe-tmp", .{});
    defer tmp_dir.close();

    // 1. Compiler dans tmp_dir/prog-bench
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
        const ssa = try mir_qbe.emitQbeLoop(alloc, &mf, m);
        defer alloc.free(ssa);
        try tmp_dir.writeFile(.{ .sub_path = "prog-bench.ssa", .data = ssa });

        const qbe_path = build_options.qbe_path;
        std.fs.accessAbsolute(qbe_path, .{}) catch return error.QbeNotFound;
        try runChild(alloc, &.{ qbe_path, "-o", "prog-bench.s", "prog-bench.ssa" }, tmp_dir);
        try runChild(alloc, &.{ "cc", "-no-pie", "prog-bench.s", "-o", "prog-bench" }, tmp_dir);
    }

    // 2. Mesurer N executions (wall time + CPU time via RUSAGE_CHILDREN)
    var wall_samples = try alloc.alloc(u64, n);
    defer alloc.free(wall_samples);
    var cpu_samples = try alloc.alloc(u64, n);
    defer alloc.free(cpu_samples);


    var extra: ExtraStats = .{};
    extra.temp_start_mc = platform.profiler.readTempMc(0) orelse 0;
    const energy_before = platform.profiler.readEnergyUj();

    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const ru0 = platform.profiler.getChildrenUsage();

        const t0 = std.time.nanoTimestamp();
        var child = std.process.Child.init(&.{"./prog-bench"}, alloc);
        child.cwd_dir = tmp_dir;
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

        const rss = @as(u64, @intCast(ru1.maxrss));
        if (rss > extra.rss_peak_kb) extra.rss_peak_kb = rss;
    }

    extra.temp_end_mc = platform.profiler.readTempMc(0) orelse 0;
    if (energy_before) |e0| {
        if (platform.profiler.readEnergyUj()) |e1| {
            if (e1 > e0) extra.energy_uj = e1 - e0;
        }
    }

    const total_inner: u64 = @as(u64, n) * @as(u64, m);
    platform.debug.print(
        "[BENCH-QBE] {s} : {d} spawns x {d} iterations internes = {d} total\n",
        .{ src_path, n, m, total_inner },
    );
    const sw = computeStats(wall_samples);
    printStats("wall", src_path, sw);
    const sc = computeStats(cpu_samples);
    printStats("cpu", src_path, sc);
    printExtra(extra, n, energy_before != null);
}

fn printExtra(e: ExtraStats, n: u32, energy_available: bool) void {
    const per_run_uj: f64 = if (n > 0)
        @as(f64, @floatFromInt(e.energy_uj)) / @as(f64, @floatFromInt(n))
    else
        0;
    platform.debug.print(
        "[BENCH-QBE] extras\n" ++
            "  rss pic       : {d} KB\n",
        .{e.rss_peak_kb},
    );
    if (energy_available) {
        platform.debug.print(
            "  energy total  : {d} uJ  ({d:.1} uJ/run)\n",
            .{ e.energy_uj, per_run_uj },
        );
    } else {
        platform.debug.print(
            "  energy        : indisponible (RAPL inaccessible)\n" ++
                "                  activer avec : sudo chmod +r /sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj\n",
            .{},
        );
    }
    platform.debug.print(
        "  temp debut    : {d:.1} C\n" ++
            "  temp fin      : {d:.1} C  (delta {d:.1} C)\n",
        .{
            @as(f64, @floatFromInt(e.temp_start_mc)) / 1000.0,
            @as(f64, @floatFromInt(e.temp_end_mc)) / 1000.0,
            @as(f64, @floatFromInt(e.temp_end_mc - e.temp_start_mc)) / 1000.0,
        },
    );
}
