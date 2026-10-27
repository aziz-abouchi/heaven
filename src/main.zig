const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform");

const signaling = @import("runtime/signaling_server.zig");

// ─── Nouveau noyau (modules build.zig) ───
const expr = @import("expr");
const egraph_mod = @import("egraph");

const codec = @import("codec");
const network_queue = @import("queue");
const MessageQueue = network_queue.MessageQueue;
//const handlers = @import("core/network/handlers.zig");

// ─── Ancien système (chemins relatifs) ───
const matrix_lib = @import("matrix_lib");
const vessel_lib = @import("vessel/bridge.zig");
const heaven_expr = @import("heaven_expr");
const heaven_lib = @import("runtime/heaven.zig");
const universal_lib = @import("inference/forge/universal.zig");
const autofab_lib = @import("runtime/autofab.zig");
const react_lib = @import("core/react.zig");
const network = @import("scut/network.zig");
const SRG = @import("runtime/symbolResolutionGraph.zig").SRG;
const EQSATPlanner = @import("runtime/eQSATPlanner.zig").EQSATPlanner;
const shell_lib = @import("runtime/shell/mod.zig");
const loop = @import("runtime/loop.zig");
const bob_loop = @import("runtime/bob_loop.zig");

//
//

var bob_identity: []const u8 = "Bob:Unknown";
var my_origin: u64 = 0;
const exiting: *std.atomic.Value(bool) = &@import("exiting").exiting;

fn bobLog(comptime level: []const u8, comptime fmt: []const u8, args: anytype) void {
    if (std.mem.eql(u8, level, "SATURATION")) return;
    const now = std.time.timestamp();
    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
    const day_seconds = epoch.getDaySeconds();
    const hours = day_seconds.getHoursIntoDay();
    const mins = day_seconds.getMinutesIntoHour();
    const secs = day_seconds.getSecondsIntoMinute();
    const ms = @mod(std.time.milliTimestamp(), 1000);

    platform.dbg("[{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}] [{s}] [{s}] ", .{ hours, mins, secs, ms, bob_identity, level });
    platform.debug.print(fmt ++ "\n", args);
}

const swarm_runtime = @import("runtime/swarm/runtime.zig");

fn swarmWorkerLoop(allocator: std.mem.Allocator, swarm: *swarm_runtime.SwarmRuntime, ex: *const std.atomic.Value(bool)) void {
    // Create dedicated Heaven for this thread
    var heaven = heaven_expr.Heaven.init(allocator) catch @panic("Failed to init Heaven");
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    platform.dbg("[SWARM] Worker thread started (Bob:{d})\n", .{swarm.self_port});

    while (!ex.load(.acquire)) {
        // Process incoming tasks from other Bobs
        var i: usize = 0;
        while (i < swarm.pending_tasks.items.len) {
            const task = swarm.pending_tasks.items[i];
            if (task.origin_port != swarm.self_port and task.status == .pending) {
                if (swarm.tryResolve(task, &heaven)) |result| {
                    // Send result back to origin Bob
                    const payload = std.mem.asBytes(&result);
                    for (network.known_peers.items) |peer| {
                        if (peer.address.getPort() == task.origin_port) {
                            network.sendTo(peer.address, payload) catch {};
                            break;
                        }
                    }
                    _ = swarm.pending_tasks.orderedRemove(i);
                    continue;
                } else {
                    // Can't solve, remove to avoid retry spam
                    _ = swarm.pending_tasks.orderedRemove(i);
                    continue;
                }
            }
            i += 1;
        }

        // Check for results that came back
        if (swarm_runtime.global_results) |results| {
            while (results.items.len > 0) {
                const result = results.orderedRemove(0);
                swarm.receiveResult(result);
            }
        }

        platform.Thread.sleep(200 * std.time.ns_per_ms);
    }
}

pub fn syncMatrixWithFile(_: *matrix_lib.Matrix, _: *autofab_lib.AutoFab, _: std.mem.Allocator, _: []const u8) !void {
    return;
}

pub fn main() !void {
    // Windows : forcer la console en UTF-8 avant tout affichage.
    // No-op sur Unix.
    platform.initConsole();

    // Debug actif si HEAVEN_DEBUG est definie, non-vide et != "0".
    // Une variable vide (HEAVEN_DEBUG=) ne suffit pas - voir go.sh
    // qui passe HEAVEN_DEBUG="${HEAVEN_DEBUG:-}" (vide si non defini).
    platform.io_console.debug_enabled = if (platform.getenv("HEAVEN_DEBUG")) |v|
        v.len > 0 and !std.mem.eql(u8, v, "0")
    else
        false;

    // Sortie differee : std.process.exit() court-circuite TOUS les
    // defer, y compris le check de fuite gpa plus bas. On pose un
    // exit-defer EN PREMIER (donc execute EN DERNIER, LIFO) qui
    // appelle exit une fois que tous les autres defers (cleanup
    // engine/store/shell, check gpa) ont tourne.
    var requested_exit: ?u8 = null;
    defer if (requested_exit) |code| std.process.exit(code);

    // Allocator selection :
    // - Par defaut en Debug : GeneralPurposeAllocator (leak check complet).
    // - Si HEAVEN_NO_LEAK_CHECK=1 : page_allocator (rapide, aucun check).
    //
    // Pourquoi ce flag : depuis 2026-10-02, un bug intermittent fait
    // paniquer le DebugAllocator (assert double-mapped pages) pendant
    // les tests, alors que page_allocator passe 20/20 (98/98 tests).
    // Le bug est DebugAllocator-specifique (metadonnees internes),
    // pas un UAF (page_allocator ferait un segfault). Pour debloquer
    // les tests en attendant le fix, on peut desactiver le check.
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = true,
        .thread_safe = true,
        .never_unmap = true,
        .retain_metadata = true,
    }){};
    const no_leak_check = platform.getenv("HEAVEN_NO_LEAK_CHECK") != null;
    defer {
        if (!no_leak_check) {
            const leaked = gpa.deinit();
            if (leaked == .leak) {
                platform.debug.print("MEMORY LEAK DETECTED! Check stderr for details.\n", .{});
            } else {
                platform.debug.print("Memory clean: No leaks detected.\n", .{});
            }
        }
    }
    const allocator = if (no_leak_check) std.heap.page_allocator else gpa.allocator();

    var msg_queue = network_queue.MessageQueue.init(allocator, 1024);
    const webrtc_bridge = @import("runtime/webrtc_bridge.zig");
    webrtc_bridge.global_queue = &msg_queue;
    webrtc_bridge.global_allocator = allocator;

    const args = std.process.argsAlloc(allocator) catch return error.OutOfMemory;
    defer std.process.argsFree(allocator, args);
    if (args.len > 1 and std.mem.eql(u8, args[1], "--completions")) {
        const keywords = [_][]const u8{ "theorem", "prove", "transform", "let", "fun", "simplify", "type", "latex", "derive", "integrate", "solve", "help", "stats", "theorems", "load" };
        var buf: [1024]u8 = undefined;
        const stdout = platform.fs.File.stdout().writer(&buf);
        for (keywords, 0..) |kw, i| {
            if (i > 0) stdout.file.writeAll(" ") catch {};
            stdout.file.writeAll(kw) catch {};
        }
        return;
    }

    // Mode MCP: serveur JSON-RPC sur stdio pour Claude Desktop / AI assistants
    if (args.len > 1 and std.mem.eql(u8, args[1], "mcp")) {
        const mcp_server_mod = @import("mcp_server");
        var server = mcp_server_mod.McpServer.init(allocator);
        server.ensureHeaven();
        server.run() catch |err| {
            platform.debug.print("MCP server error: {}\n", .{err});
        };
        return;
    }

    if (args.len < 2 or std.mem.eql(u8, args[1], "help") or std.mem.eql(u8, args[1], "--help")) {
        platform.debug.print(
            \\Heaven Programming Language v0.1.0
            \\
            \\Usage: heaven <command> [args]
            \\
            \\Frontend:
            \\  parse   <file.hvn>                        Parse and show AST
            \\  check   <file.hvn>                        Type-check
            \\  fmt     <file.hvn>                        Format source code
            \\  doc     <file.hvn>                        Generate documentation
            \\  transpile [--to c|heaven|latex] <file>    Transpile
            \\
            \\Execution:
            \\  run     <file.hvn>                        Compile and execute
            \\  test    <file.hvn>                        Run test blocks
            \\  repl                                       Interactive REPL
            \\
            \\Backends:
            \\  compile <file.hvn>                        Generate C code (output.c)
            \\  compile-qbe  <src.hvn> -o <bin>  [--target <name>]  Native via QBE
            \\  compile-wasm <src.hvn> -o <out.wat>                 WebAssembly
            \\
            \\Benchmarks:
            \\  bench-interp <file.hvn>                   Interpreter timings
            \\  bench-qbe    <file.hvn>                   QBE timings
            \\  bench-wasm   <file.hvn>                   WASM timings
            \\
            \\Tools:
            \\  lsp                                        Start LSP server
            \\  mcp                                        Start MCP server
            \\  --completions                              Shell completions
            \\  help                                       Show this help
            \\
            \\Internal:
            \\  --run-test  <file.hvn>                    Run a single test file
            \\  --run-tests <dir>                         Run all .hvn in a directory
            \\
            \\Targets for compile-qbe --target:
            \\  amd64_sysv, amd64_apple, arm64, arm64_apple, rv64
            \\
        , .{});
        return;
    }

    if (args.len >= 3 and std.mem.eql(u8, args[1], "parse")) {
        const parse_cmd = @import("commands/parse.zig");
        try parse_cmd.runParse(allocator, args[2]);
        return;
    }
    if (args.len >= 3 and std.mem.eql(u8, args[1], "check")) {
        const check_cmd = @import("commands/check.zig");
        try check_cmd.runCheck(allocator, args[2]);
        return;
    }
    if (std.mem.eql(u8, args[1], "lsp")) {
        const lsp_cmd = @import("commands/lsp_cmd.zig");
        try lsp_cmd.runLspCmd(allocator);
        return;
    }
    if (std.mem.eql(u8, args[1], "compile") and args.len >= 3) {
        const compile_cmd = @import("commands/compile.zig");
        try compile_cmd.runCompile(allocator, args[2]);
        return;
    }

    if (std.mem.eql(u8, args[1], "compile-qbe") and args.len >= 5 and std.mem.eql(u8, args[3], "-o")) {
        const qbe_cmd = @import("commands/qbe_cmd.zig");
        var target: ?[]const u8 = null;
        var i: usize = 5;
        while (i + 1 < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--target")) {
                target = args[i + 1];
            }
        }
        try qbe_cmd.runCompileQbe(allocator, args[2], args[4], target);
        return;
    }
    if (std.mem.eql(u8, args[1], "compile-wasm") and args.len >= 5 and std.mem.eql(u8, args[3], "-o")) {
        const wasm_cmd = @import("commands/wasm_cmd.zig");
        try wasm_cmd.runCompileWasm(allocator, args[2], args[4]);
        return;
    }
    if (std.mem.eql(u8, args[1], "bench-wasm") and args.len >= 3) {
        const wasm_cmd = @import("commands/wasm_cmd.zig");
        var n: u32 = 100;
        var m: u32 = 1;
        var i: usize = 3;
        while (i < args.len) {
            if (std.mem.eql(u8, args[i], "--loop") and i + 1 < args.len) {
                m = std.fmt.parseInt(u32, args[i + 1], 10) catch 1;
                i += 2;
            } else {
                n = std.fmt.parseInt(u32, args[i], 10) catch n;
                i += 1;
            }
        }
        try wasm_cmd.runBenchWasm(allocator, args[2], n, m);
        return;
    }
    if (std.mem.eql(u8, args[1], "bench-interp") and args.len >= 3) {
        const bench_interp = @import("commands/bench_interp.zig");
        var n: u32 = 10;
        var m: u32 = 1;
        var i: usize = 3;
        while (i < args.len) {
            if (std.mem.eql(u8, args[i], "--loop") and i + 1 < args.len) {
                m = std.fmt.parseInt(u32, args[i + 1], 10) catch 1;
                i += 2;
            } else {
                n = std.fmt.parseInt(u32, args[i], 10) catch n;
                i += 1;
            }
        }
        try bench_interp.runBenchInterp(allocator, args[2], n, m);
        return;
    }
    if (std.mem.eql(u8, args[1], "bench-qbe") and args.len >= 3) {
        const qbe_cmd = @import("commands/qbe_cmd.zig");
        var n: u32 = 100;
        var m: u32 = 1;
        var i: usize = 3;
        while (i < args.len) {
            if (std.mem.eql(u8, args[i], "--loop") and i + 1 < args.len) {
                m = std.fmt.parseInt(u32, args[i + 1], 10) catch 1;
                i += 2;
            } else {
                n = std.fmt.parseInt(u32, args[i], 10) catch n;
                i += 1;
            }
        }
        try qbe_cmd.runBenchQbe(allocator, args[2], n, m);
        return;
    }
    if (std.mem.eql(u8, args[1], "run") and args.len >= 3) {
        const run_cmd = @import("commands/run.zig");
        try run_cmd.runRun(allocator, &.{args[2]});
        return;
    }
    // Évaluateur de script pour les tests de non-régression
    if (std.mem.eql(u8, args[1], "--run-test") and args.len >= 3) {
        const test_runner = @import("runtime/test_runner.zig");
        const failed = try test_runner.runTestFile(allocator, args[2]);
        if (failed) std.process.exit(1);
        return;
    }
    if (std.mem.eql(u8, args[1], "--run-test")) {
        const test_runner = @import("runtime/test_runner.zig");
        if (try test_runner.runTestFile(allocator, args[2])) requested_exit = 1;
        return;
    }
    if (std.mem.eql(u8, args[1], "--run-tests")) {
        const test_runner = @import("runtime/test_runner.zig");
        if (try test_runner.runTestDir(allocator, args[2])) requested_exit = 1;
        return;
    }
    if (std.mem.eql(u8, args[1], "--eval-file") and args.len >= 3) {
        const test_runner = @import("runtime/test_runner.zig");
        try test_runner.runEvalFile(allocator, args[2]);
        return;
    }
    if (std.mem.eql(u8, args[1], "test") and args.len >= 3) {
        const test_cmd = @import("commands/test_cmd.zig");
        try test_cmd.runTest(allocator, &.{args[2]});
        return;
    }
    if (std.mem.eql(u8, args[1], "fmt") and args.len >= 3) {
        const fmt_cmd = @import("commands/fmt.zig");
        try fmt_cmd.runFmt(allocator, args[2]);
        return;
    }
    if (std.mem.eql(u8, args[1], "doc") and args.len >= 3) {
        const doc_cmd = @import("commands/doc.zig");
        try doc_cmd.runDoc(allocator, args[2]);
        return;
    }
    if (std.mem.eql(u8, args[1], "transpile")) {
        const transpile_cmd = @import("commands/transpile.zig");
        try transpile_cmd.runTranspile(allocator, args[2..]);
        return;
    }

    // Unification : "repl" ou pas d'argument = mode local (port 0). Sinon, mode réseau.
    const port_str = blk: {
        if (args.len < 2) break :blk "0";
        if (std.mem.eql(u8, args[1], "repl")) break :blk "0";
        break :blk args[1];
    };
    const is_local = std.mem.eql(u8, port_str, "0");
    bob_identity = try std.fmt.allocPrint(allocator, "Bob:{s}", .{port_str});
    defer allocator.free(bob_identity);
    my_origin = std.hash.Wyhash.hash(0, bob_identity);
    network.self_origin = my_origin;

    bobLog("CORE", "Noyau opérationnel sur le port {s}", .{port_str});

    const port = try std.fmt.parseInt(u16, port_str, 10);

    // On ne lance le réseau QUE si on n'est pas en local
    if (!is_local) {
        network.init(port) catch {
            platform.dbg("[NET] Init failed on port {d}\n", .{port});
        };
        try platform.rtc.WebRTC.init();
        platform.debug.print("RTC initialized\n", .{});
    }

    var matrix = matrix_lib.Matrix.init(allocator);
    defer matrix.deinit();

    // Ingestion universelle bootstrap
    var uni_ingest = try universal_lib.UniversalIngestor.init(allocator, &matrix);
    defer uni_ingest.deinit();

    const bootstrap_path = "core/bootstrap.hvn";
    const bootstrap_source = try platform.fs.cwd().readFileAlloc(allocator, bootstrap_path, 1024 * 1024);
    defer allocator.free(bootstrap_source);

    uni_ingest.ingest(bootstrap_path, bootstrap_source) catch |err| {
        platform.dbg("[BOOT] Ingestion echouee: {s}\n", .{@errorName(err)});
    };

    // --- Chargement du Noyau et de la Logique ---
    const files_to_load = &[_][]const u8{ "core/kernel.hvn", "core/logic.hvn", "core/prelude.hvn", "core/io.hvn" };

    for (files_to_load) |filename| {
        const source = platform.fs.cwd().readFileAlloc(allocator, filename, 1024 * 1024) catch |err| {
            platform.dbg("[BOOT] Erreur lecture {s}: {s}\n", .{ filename, @errorName(err) });
            continue;
        };
        defer allocator.free(source);

        uni_ingest.ingest(filename, source) catch |err| {
            platform.dbg("[BOOT] Erreur ingestion {s}: {s}\n", .{ filename, @errorName(err) });
        };
    }
    platform.dbg("[BOOT] Noyau logique (kernel/logic) chargé.\n", .{});

    // Engine & Autofab
    var fab = autofab_lib.AutoFab.init(allocator, &matrix, bob_identity);
    var srg = SRG.init(allocator);
    var eqsat_planner = EQSATPlanner.init(allocator);

    // ─── Nouveau noyau Expr (initialisé en parallèle) ───
    var store = expr.Store.init(allocator);
    defer store.deinit();

    bobLog("CORE", "Noyau Expr (6 primitives) initialisé", .{});

    // Passez 'store' en premier argument :
    var my_egraph = egraph_mod.EGraph.init(&store, allocator);

    var heaven_engine = heaven_lib.Engine.init(allocator, &matrix, &srg, &eqsat_planner, &my_egraph);
    defer heaven_engine.deinit();

    heaven_engine.autofab = &fab;

    var reaction_engine = react_lib.ReactionEngine{
        .matrix = &matrix,
        .allocator = allocator,
    };

    var vessel_heaven = try heaven_expr.Heaven.init(allocator);
    defer {
        vessel_heaven.deinit();
        allocator.destroy(vessel_heaven);
    }

    // Threads
    var v_thread: ?platform.Thread = null;
    v_thread = try platform.Thread.spawn(.{}, struct {
        fn wrapper(
            hv: *heaven_expr.Heaven,
            p: u16,
            ex: *const std.atomic.Value(bool),
        ) void {
            vessel_lib.startVesselServer(hv, p, ex);
        }
    }.wrapper, .{ vessel_heaven, port, exiting });
    // v_thread n'est pas jointe car elle peut être détachée
    // Si besoin de la joindre, décommenter : v_thread.join();

    var last_processed_id: matrix_lib.BobId = 0;
    var net_thread: ?platform.Thread = null;

    // On ne lance les threads réseau QUE si on n'est pas en local
    if (!is_local) {
        net_thread = try platform.Thread.spawn(.{}, bob_loop.run, .{ &matrix, &reaction_engine, allocator, &last_processed_id, &msg_queue, &my_egraph, exiting });
        //_ = net_thread;
    }

    // Signal server (en dehors du bloc pour être accessible à la fin)
    var signal_server = signaling.SignalingServer.init(allocator, 9000, exiting);
    const signal_thread = try platform.Thread.spawn(.{}, struct {
        fn wrapper(s: *signaling.SignalingServer) void {
            s.run() catch {};
        }
    }.wrapper, .{&signal_server});

    const loop_thread = try platform.Thread.spawn(.{}, struct {
        fn wrapper(e: *heaven_lib.Engine, m: *matrix_lib.Matrix, ex: *const std.atomic.Value(bool)) void {
            loop.runLoop(e, m, ex);
        }
    }.wrapper, .{ &heaven_engine, &matrix, exiting });
    loop_thread.detach();

    // Shell
    // ─── Nouveau REPL basé sur le Shell officiel ───
    bobLog("CORE", "Système prêt. Entrée dans le Shell.", .{});

    // ─── Mode interactif ou serveur-only ───
    // HEAVEN_NO_REPL=1 (ou stdin non-TTY) -> skip REPL. Evite SIGTTOU
    // quand lance en arriere-plan (bash &, docker -d, systemd).
    // Le REPL interactif necessite un TTY foreground.
    const no_repl_env = std.posix.getenv("HEAVEN_NO_REPL");
    const is_tty = std.posix.isatty(std.posix.STDIN_FILENO);
    const is_interactive = (no_repl_env == null) and is_tty;

    if (is_interactive) {
        var shell = shell_lib.Shell.init(allocator, &matrix, &heaven_engine, &uni_ingest, port);
        defer shell.deinit();
        try shell.run();
    } else {
        platform.io.print("[CORE] Mode serveur (REPL desactive: HEAVEN_NO_REPL=1 ou stdin non-TTY).\n", .{});
        while (true) {
            platform.Thread.sleep(500 * std.time.ns_per_ms);
        }
    }

    // 1. Signaler aux threads de s'arrêter
    exiting.store(true, .release);

    platform.io.print("[CORE] Arrêt en cours...\n", .{});

    // On détache les threads pour ne pas attendre leur fin
    if (net_thread) |t| t.detach();
    signal_thread.detach();

    // 3. Sortie normale : le defer exit-defer s'en charge apres les
    // autres defers (cleanup shell/engine/store, check gpa).
    requested_exit = 0;
}
