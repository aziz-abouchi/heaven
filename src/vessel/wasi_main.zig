// HEAVEN:wasi_main — entrée WASI (Wasmtime).
// Supporte : expression directe, --eval-file <path>, --fuel <n>.
// Pas de REPL interactif.
const std = @import("std");
const heaven_expr = @import("heaven_expr");
const platform = @import("platform");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        platform.io.printOut("usage: heaven-wasi [--fuel N] <expr>\n", .{});
        platform.io.printOut("       heaven-wasi [--fuel N] --eval-file <path>\n", .{});
        return;
    }

    // ── Parse options ──
    var i: usize = 1;
    var fuel: ?u64 = null;
    var eval_file: ?[]const u8 = null;

    while (i < args.len) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--fuel") and i + 1 < args.len) {
            fuel = try std.fmt.parseInt(u64, args[i + 1], 10);
            i += 2;
        } else if (std.mem.eql(u8, a, "--eval-file") and i + 1 < args.len) {
            eval_file = args[i + 1];
            i += 2;
        } else break;
    }

    const heaven = try heaven_expr.Heaven.init(allocator);
    defer heaven.deinit();

    // Optionnel : régler le fuel avant évaluation
    if (fuel) |f| {
        heaven.engine.fuel = f;
    }

    if (eval_file) |path| {
        // Lecture fichier + split lignes + eval séquentielle
        const content = try platform.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
        defer allocator.free(content);

        var it = std.mem.splitScalar(u8, content, '\n');
        var last: []const u8 = "";
        var own_last: bool = false;
        while (it.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            if (trimmed[0] == '#') continue;
            if (std.mem.startsWith(u8, trimmed, "//")) continue;

            if (own_last) {
                allocator.free(last);
                own_last = false;
            }
            const r = heaven.eval(trimmed) catch |err| {
                platform.io.printOut("eval error on line: {s} -> {s}\n", .{ trimmed, @errorName(err) });
                return;
            };
            last = r;
            own_last = true;
        }
        if (own_last) {
            platform.io.printOut("{s}\n", .{last});
            allocator.free(last);
        }
        return;
    }

    // Fallback : join args[1..] en une expression unique
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);
    var first = true;
    for (args[i..]) |a| {
        if (!first) try buf.append(allocator, ' ');
        try buf.appendSlice(allocator, a);
        first = false;
    }

    const result = try heaven.eval(buf.items);
    defer allocator.free(result);
    platform.io.printOut("{s}\n", .{result});
}
