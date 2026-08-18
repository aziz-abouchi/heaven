const std = @import("std");
const platform = @import("platform");

const signaling = @import("runtime/signaling_server.zig");

// ─── Nouveau noyau (modules build.zig) ───
const expr = @import("expr");
const bridge_expr = @import("bridge_expr");
const kanren_expr = @import("kanren_expr");
const egraph_mod = @import("egraph");
const codegen_expr_c = @import("codegen_expr_c");
const codegen_expr_latex = @import("codegen_expr_latex");
const engine_expr = @import("engine_expr");

const codec = @import("codec");
const network_queue = @import("queue");
const MessageQueue = network_queue.MessageQueue;
//const handlers = @import("core/network/handlers.zig");

// ─── Ancien système (chemins relatifs) ───
const matrix_lib = @import("matrix_lib");
const vessel_lib = @import("vessel/bridge.zig");
const heaven_lib = @import("runtime/heaven.zig");
const transpiler_lib = @import("inference/forge/transpiler.zig");
const universal_lib = @import("inference/forge/universal.zig");
const autofab_lib = @import("runtime/autofab.zig");
const react_lib = @import("core/react.zig");
const network = @import("scut/network.zig");
const protocol = @import("protocol");
const dispatch = @import("core/dispatch.zig");
const task_lib = @import("task");
const SRG = @import("runtime/symbolResolutionGraph.zig").SRG;
const EQSATPlanner = @import("runtime/eQSATPlanner.zig").EQSATPlanner;
const shell_lib = @import("runtime/shell/mod.zig");
const loop = @import("runtime/loop.zig");

//
const commands_mod = @import("commands");
const matrix_bridge_mod = @import("matrix_bridge");
const transform_mod = @import("transform");
const skill_lib = @import("skill");
const proof_core = @import("proof_core");
const agent_mod = @import("agent");
const parse_mod = @import("parse");
const math_mod = @import("math");
//

var bob_identity: []const u8 = "Bob:Unknown";
var my_origin: u64 = 0;
var exiting = std.atomic.Value(bool).init(false);

fn bobLog(comptime level: []const u8, comptime fmt: []const u8, args: anytype) void {
    if (std.mem.eql(u8, level, "SATURATION")) return;
    const now = std.time.timestamp();
    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
    const day_seconds = epoch.getDaySeconds();
    const hours = day_seconds.getHoursIntoDay();
    const mins = day_seconds.getMinutesIntoHour();
    const secs = day_seconds.getSecondsIntoMinute();
    const ms = @mod(std.time.milliTimestamp(), 1000);

    platform.debug.print("[{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}] [{s}] [{s}] ", .{ hours, mins, secs, ms, bob_identity, level });
    platform.debug.print(fmt ++ "\n", args);
}

const swarm_runtime = @import("runtime/swarm/runtime.zig");
const swarm_proto = @import("scut/swarm/protocol_swarm.zig");
const heaven_expr_mod = @import("heaven_expr");

fn swarmWorkerLoop(allocator: std.mem.Allocator, swarm: *swarm_runtime.SwarmRuntime, ex: *const std.atomic.Value(bool)) void {
    // Create dedicated Heaven for this thread
    var heaven = heaven_expr_mod.Heaven.init(allocator);

    platform.debug.print("[SWARM] Worker thread started (Bob:{d})\n", .{swarm.self_port});

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
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = true, // active toutes les vérifications
        .thread_safe = true, // support multi-thread
        .never_unmap = true, // garde la mémoire mappée
        .retain_metadata = true, // conserve les métadonnées après libération (aide au débogage)
    }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            platform.debug.print("⚠️ MEMORY LEAK DETECTED! Check stderr for details.\n", .{});
        } else {
            platform.debug.print("Memory clean: No leaks detected.\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var msg_queue = network_queue.MessageQueue.init(allocator, 1024);

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
            \\Commands:
            \\  parse   <file.hvn>    Parse and show AST
            \\  check   <file.hvn>    Type-check
            \\  compile <file.hvn>    Generate C code (output.c)
            \\  run     <file.hvn>    Compile and execute
            \\  test    <file.hvn>    Run test blocks
            \\  fmt     <file.hvn>    Format source code
            \\  doc     <file.hvn>    Generate documentation
            \\  lsp                   Start LSP server
            \\  repl                  Interactive REPL
            \\  transpile [--to c|heaven|latex] <file>  Transpile
            \\  help                  Show this help
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
    if (std.mem.eql(u8, args[1], "run") and args.len >= 3) {
        const run_cmd = @import("commands/run.zig");
        try run_cmd.runRun(allocator, args[2]);
        return;
    }
    // NOUVEAU : Évaluateur de script pour les tests de non-régression
    if (std.mem.eql(u8, args[1], "--run-test") and args.len >= 3) {
        var heaven = heaven_expr_mod.Heaven.init(allocator);
        defer heaven.deinit();
        heaven.ensureInit();

        const file = try platform.fs.cwd().openFile(args[2], .{});
        defer file.close();
        const stat = try file.stat();
        const file_content = try allocator.alloc(u8, stat.size);
        defer allocator.free(file_content);
        _ = try file.readAll(file_content);

        platform.debug.print("── Running tests from {s} ──\n", .{args[2]});

        var lines = std.mem.splitScalar(u8, file_content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue; // Ignorer commentaires et lignes vides

            const result = heaven.eval(trimmed) catch |err| {
                platform.debug.print("❌ FAIL: {s}\n  Error: {}\n", .{ trimmed, err });
                continue;
            };
            defer allocator.free(result);

            // Afficher le résultat de la ligne
            platform.debug.print("✓ {s} → {s}\n", .{ trimmed, result });
        }

        platform.debug.print("── Tests finished ──\n", .{});
        return;
    }
    if (std.mem.eql(u8, args[1], "test") and args.len >= 3) {
        const test_cmd = @import("commands/test_cmd.zig");
        try test_cmd.runTest(allocator, args[2]);
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
            platform.debug.print("[NET] Init failed on port {d}\n", .{port});
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
        platform.debug.print("[BOOT] Ingestion echouee: {s}\n", .{@errorName(err)});
    };

    // --- Chargement du Noyau et de la Logique ---
    const files_to_load = &[_][]const u8{ "core/kernel.hvn", "core/logic.hvn" };

    for (files_to_load) |filename| {
        const source = platform.fs.cwd().readFileAlloc(allocator, filename, 1024 * 1024) catch |err| {
            platform.debug.print("[BOOT] Erreur lecture {s}: {s}\n", .{ filename, @errorName(err) });
            continue;
        };
        defer allocator.free(source);

        uni_ingest.ingest(filename, source) catch |err| {
            platform.debug.print("[BOOT] Erreur ingestion {s}: {s}\n", .{ filename, @errorName(err) });
        };
    }
    platform.debug.print("[BOOT] Noyau logique (kernel/logic) chargé.\n", .{});

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

    // Threads
    var v_thread: ?platform.Thread = null;
    v_thread = try platform.Thread.spawn(.{}, struct {
        fn wrapper(
            m: *matrix_lib.Matrix,
            f: *autofab_lib.AutoFab,
            p: u16,
            ex: *const std.atomic.Value(bool),
        ) void {
            vessel_lib.startVesselServer(m, f, p, ex);
        }
    }.wrapper, .{ &matrix, &fab, port + 2919, &exiting });
    // v_thread n'est pas jointe car elle peut être détachée
    // Si besoin de la joindre, décommenter : v_thread.join();

    var last_processed_id: matrix_lib.BobId = 0;
    var net_thread: ?platform.Thread = null;

    // On ne lance les threads réseau QUE si on n'est pas en local
    if (!is_local) {
        net_thread = try platform.Thread.spawn(.{}, struct {
            fn wrapper(
                m: *matrix_lib.Matrix,
                re: *react_lib.ReactionEngine,
                a: std.mem.Allocator,
                lp_id: *matrix_lib.BobId,
                queue: *network_queue.MessageQueue,
                egraph: *egraph_mod.EGraph,
                ex: *const std.atomic.Value(bool),
            ) !void {
                var last_ping: i64 = 0;
                while (!ex.load(.acquire)) {
                    // 1. TRAITEMENT : Vidage de la file réseau (Consommateur)
                    while (queue.pop()) |msg| {
                        platform.debug.print("[NET] Reçu {d} octets: {any}\n", .{ msg.payload.len, msg.payload[0..@min(msg.payload.len, 8)] });
                        // 1. Décodage du binaire vers le type attendu
                        const incoming = codec.decode(msg.payload) catch {
                            platform.debug.print("[NET] Échec décodage message\n", .{});
                            a.free(msg.payload);
                            continue;
                        };
                        // Traitement métier du message
                        const addr = std.net.Address{ .in = std.net.Address.initIp4([4]u8{ 0, 0, 0, 0 }, 0).in };
                        network.handleIncoming(a, m, egraph, incoming, addr) catch |err| {
                            platform.debug.print("[NET] Handle error: {any}\n", .{err});
                        };
                        // Libération de la mémoire allouée par le 'push'
                        a.free(msg.payload);
                    }

                    // 2. RÉCEPTION : Écoute du réseau et remplissage de la file (Producteur)
                    if (try network.listen(a)) |incoming| {
                        // Log pour confirmer la réception
                        platform.debug.print("[NET] Traitement de {d} octets\n", .{incoming.len});

                        // Accès direct au buffer selon le type contenu dans l'union
                        const raw_slice: []u8 = switch (incoming.data) {
                            .RawCode => |bytes| bytes,
                            .MatrixSync => |bytes| bytes,
                            .Signal => |bytes| bytes,
                            // On crée une variable mutable pour pouvoir en prendre l'adresse en tant que []u8
                            .Task => |*t| @constCast(std.mem.asBytes(t)),
                            else => &[_]u8{},
                        };

                        // Maintenant utilisez raw_slice, qui est déjà borné à la taille réelle
                        if (raw_slice.len > 0) {
                            _ = try codec.decode(raw_slice);
                        }

                        // On duplique le payload pour que la file en soit propriétaire
                        const incoming_bytes = std.mem.asBytes(&incoming.data);
                        const actual_data = incoming_bytes[0..incoming_bytes.len];
                        const payload = try a.dupe(u8, actual_data);

                        try queue.push(.{
                            .msg_type = .egraph_sync,
                            .peer_id = ("peer" ++ ([1]u8{0} ** 12)).*,
                            .payload = payload,
                            .timestamp = @as(u64, @intCast(std.time.milliTimestamp())),
                        });

                        // Libération des ressources de structure temporaire (pas du payload_copy)
                        // Note: Si incoming.data contient des sous-allocations, libérez-les ici
                    }

                    // 3. TRAVAIL LOCAL : Inférence et maintien du système
                    const now = std.time.milliTimestamp();
                    if (now - last_ping > 15000) {
                        network.broadcastPresence() catch {};
                        last_ping = now;
                    }

                    m.saturate();
                    while (lp_id.* < m.next_id) : (lp_id.* += 1) {
                        re.processNewFact(lp_id.*) catch {};
                    }

                    platform.Thread.sleep(10 * std.time.ns_per_ms);
                }
            }
        }.wrapper, .{ &matrix, &reaction_engine, allocator, &last_processed_id, &msg_queue, &my_egraph, &exiting });
        //_ = net_thread;
    }

    // Signal server (en dehors du bloc pour être accessible à la fin)
    var signal_server = signaling.SignalingServer.init(allocator, 9000, &exiting);
    const signal_thread = try platform.Thread.spawn(.{}, struct {
        fn wrapper(s: *signaling.SignalingServer) void {
            s.run() catch {};
        }
    }.wrapper, .{&signal_server});

    const loop_thread = try platform.Thread.spawn(.{}, struct {
        fn wrapper(e: *heaven_lib.Engine, m: *matrix_lib.Matrix, ex: *const std.atomic.Value(bool)) void {
            loop.runLoop(e, m, ex);
        }
    }.wrapper, .{ &heaven_engine, &matrix, &exiting });
    loop_thread.detach();

    // Shell
    // ─── Nouveau REPL basé sur le Shell officiel ───
    bobLog("CORE", "Système prêt. Entrée dans le Shell.", .{});

    var shell = shell_lib.Shell.init(allocator, &matrix, &heaven_engine, &uni_ingest, port);
    defer shell.deinit();

    try shell.run();

    // 1. Signaler aux threads de s'arrêter
    exiting.store(true, .release);

    platform.io.print("[CORE] Arrêt en cours...\n", .{});

    // On détache les threads pour ne pas attendre leur fin
    if (net_thread) |t| t.detach();
    signal_thread.detach();

    // 3. Forcer la fermeture du processus.
    std.process.exit(0);
}

// Variables globales pour stocker les références nécessaires au pont
var global_queue: *network_queue.MessageQueue = undefined;
var global_allocator: std.mem.Allocator = undefined;

// Cette fonction est exportée et sera appelée par le C++
export fn on_rtc_message(remote_peer_id: [*c]const u8, msg: [*c]const u8, len: usize) void {
    const data_slice = msg[0..len];
    const peer_slice = std.mem.span(remote_peer_id);

    // 1. Duplication pour la queue (sécurité mémoire)
    const payload = global_allocator.dupe(u8, data_slice) catch return;

    // 2. Préparation du PeerID
    var pid: [16]u8 = std.mem.zeroes([16]u8);
    @memcpy(pid[0..@min(pid.len, peer_slice.len)], peer_slice);

    // 3. Injection dans la file
    global_queue.push(.{
        .msg_type = .egraph_sync,
        .peer_id = pid,
        .payload = payload,
        .timestamp = @as(u64, @intCast(std.time.milliTimestamp())),
    }) catch |err| {
        platform.debug.print("[RTC] Erreur injection queue: {any}\n", .{err});
        global_allocator.free(payload);
    };
}
