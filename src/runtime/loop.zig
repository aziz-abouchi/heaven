const std = @import("std");
const dispatch = @import("../core/dispatch.zig");
const matrix_lib = @import("matrix_lib");
const heaven = @import("heaven.zig");
const platform = @import("platform");

/// 1. Ingestion des commandes externes → Matrix
pub fn ingest_commands(matrix: *matrix_lib.Matrix) void {
    while (dispatch.command_queue.get()) |node| {
        const cmd = node.data;

        switch (cmd) {
            .AddSymbol => |name| {
                _ = matrix.addUniqueSymbol(name) catch {};
            },

            .Unify => |u| {
                matrix.unify(u.a, u.b) catch {};
            },

            .PostMail => |m| {
                matrix.postMessage(m.target, m.msg) catch {};
            },

            .MatrixSync => |data| {
                matrix.mergeDelta(data) catch |err| {
                    platform.debug.print("[LOOP] Échec de fusion: {s}\n", .{@errorName(err)});
                };
            },

            else => {},
        }
    }
}

/// 2. Propagation logique (unification, règles, mailbox)
pub fn run_inference(matrix: *matrix_lib.Matrix) void {
    matrix.saturate();
}

/// 3. Sélection + exécution (SRG + Engine)
pub fn select_actions(engine: *heaven.Engine, matrix: *matrix_lib.Matrix) void {
    const Ctx = struct {
        engine: *heaven.Engine,
        matrix: *matrix_lib.Matrix,
        fn process(_symbol: []const u8, id: matrix_lib.BobId, ctx: *@This()) void {
            _ = _symbol;
            const selected = ctx.engine.srg.select(id);
            if (selected != 0) {
                platform.debug.print("[LOOP] Action {d} activée pour le symbole {d}\n", .{ selected, id });
                ctx.engine.pulse(ctx.matrix, selected, 0) catch |err| {
                    platform.debug.print("[LOOP] Échec pulse: {s}\n", .{@errorName(err)});
                };
            }
        }
    };
    var ctx = Ctx{ .engine = engine, .matrix = matrix };
    matrix.forEachSymbol(Ctx.process, .{&ctx});
}

/// 4. Loop principale
/// On passe le drapeau 'exiting' en paramètre pour éviter la dépendance circulaire avec main.zig
pub fn runLoop(engine: *heaven.Engine, matrix: *matrix_lib.Matrix, exiting: *const std.atomic.Value(bool)) void {
    while (!exiting.load(.acquire)) {
        ingest_commands(matrix);
        run_inference(matrix);
        select_actions(engine, matrix);
        platform.Thread.sleep(10 * std.time.ns_per_ms);
    }
}
