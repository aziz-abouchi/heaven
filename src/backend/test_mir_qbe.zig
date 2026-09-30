//! Tests M3 : MIR → QBE → asm natif → binaire → exécution.
//! Oracle : mir.execute (référence). Skip si qbe/cc absents.

const std = @import("std");
const mir = @import("mir");
const expr = @import("expr");
const qbe = @import("mir_qbe.zig");
const build_options = @import("build_options");

const Store = expr.Store;
const MirFunction = mir.MirFunction;
const Reg = mir.Reg;

fn applyNoFunc(store: *Store, func: expr.Id, args: []const expr.Id) !expr.Id {
    const span = try store.reserveSpan(args.len);
    for (args, 0..) |a, i| store.pool.items[span.start + i] = a;
    return store.addNode(.{
        .tag = .apply,
        .payload = func,
        .aux = 0,
        .span_a = span,
        .span_b = expr.Span.EMPTY,
    });
}

fn compileRoot(alloc: std.mem.Allocator, store: *Store, body: expr.Id) !MirFunction {
    var mf = MirFunction.initWithStore(alloc, store);
    errdefer mf.deinit();
    const entry = try mf.newBlock();
    var locals = std.AutoHashMap(u32, Reg).init(alloc);
    defer locals.deinit();
    const result = try mf.compileExpr(store, body, entry, locals);
    if (mf.blocks.items[entry].terminator == .fallthrough) {
        mf.blocks.items[entry].terminator = .{ .ret = result };
    }
    return mf;
}

fn freeInstrExtras(alloc: std.mem.Allocator, mf: *const MirFunction) void {
    for (mf.blocks.items) |blk| {
        for (blk.instrs.items) |inst| {
            switch (inst) {
                .phi => |p| alloc.free(@constCast(p.incoming)),
                .call_user => |c| alloc.free(@constCast(c.args)),
                else => {},
            }
        }
    }
}

fn deinitSansValues(alloc: std.mem.Allocator, mf: *MirFunction) void {
    for (mf.blocks.items) |*blk| blk.instrs.deinit(alloc);
    mf.blocks.deinit(alloc);
    mf.break_values.deinit(alloc);
    var it = mf.fn_defs.valueIterator();
    while (it.next()) |def| {
        def.fn_mir.deinit();
        alloc.free(def.param_names);
        alloc.free(def.param_regs);
    }
    mf.fn_defs.deinit();
}

/// qbe → cc → run. Retourne le i64 imprimé par le wrapper $main.
fn runNative(alloc: std.mem.Allocator, ssa: []const u8) !i64 {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "prog.ssa", .data = ssa });
    // QBE v1.2 : chemin absolu injecte par build.zig (build_options).
    // C'est la seule facon fiable : `zig build test` execute le
    // binaire depuis .zig-cache/o/..., pas depuis la racine du repo,
    // donc tout chemin relatif est casse.
    const qbe_path = build_options.qbe_path;
    std.fs.accessAbsolute(qbe_path, .{}) catch return error.SkipZigTest;
    try runCmd(alloc, &[_][]const u8{ qbe_path, "-o", "prog.s", "prog.ssa" }, tmp.dir);
    try runCmd(alloc, &[_][]const u8{ "cc", "-no-pie", "prog.s", "-o", "prog" }, tmp.dir);
    const out = try runCapture(alloc, &.{"./prog"}, tmp.dir);
    defer alloc.free(out);
    return std.fmt.parseInt(i64, std.mem.trim(u8, out, " \t\r\n"), 10) catch error.NativeRunFailed;
}

fn runCmd(alloc: std.mem.Allocator, argv: []const []const u8, cwd: std.fs.Dir) !void {
    var child = std.process.Child.init(argv, alloc);
    child.cwd_dir = cwd;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    var env_map = std.process.getEnvMap(alloc) catch null;
    defer if (env_map) |*em| em.deinit();
    if (env_map) |*em| {
        em.put("LC_ALL", "C") catch {};
        child.env_map = em;
    }
    child.spawn() catch |err| return if (err == error.FileNotFound) error.SkipZigTest else err;
    const stdout_data = child.stdout.?.readToEndAlloc(alloc, 1024 * 1024) catch "";
    defer alloc.free(stdout_data);
    const stderr_data = child.stderr.?.readToEndAlloc(alloc, 1024 * 1024) catch "";
    defer alloc.free(stderr_data);
    
    const term = try child.wait();
    if (term.Exited != 0) {
        std.debug.print("\n=== QBE stderr ===\n{s}\n=== End stderr ===\n", .{stderr_data});
        return error.NativeRunFailed;
    }
}

fn runCapture(alloc: std.mem.Allocator, argv: []const []const u8, cwd: std.fs.Dir) ![]u8 {
    var child = std.process.Child.init(argv, alloc);
    child.cwd_dir = cwd;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.spawn() catch |err| return if (err == error.FileNotFound) error.SkipZigTest else err;
    const out = try child.stdout.?.readToEndAlloc(alloc, 4096);
    return out;
}

fn oracleCheck(alloc: std.mem.Allocator, store: *Store, body: expr.Id, expected: i64) !void {
    var mf = try compileRoot(alloc, store, body);
    defer deinitSansValues(alloc, &mf);
    defer freeInstrExtras(alloc, &mf);

    var globals = std.AutoHashMap(u32, i64).init(alloc);
    defer globals.deinit();
    const oracle = try mf.execute(&globals);
    try std.testing.expectEqual(expected, oracle);

    const ssa = try qbe.emitQbe(alloc, &mf);
    defer alloc.free(ssa);
    const got = try runNative(alloc, ssa);
    try std.testing.expectEqual(expected, got);
}

test "qbe — M3 : oracle mir.execute vs natif" {
    const alloc = std.testing.allocator;
    // P1 : (+ 2 3) → 5
    {
        var store = Store.init(alloc);
        defer store.deinit();
        const body = try applyNoFunc(&store, try store.sym("+"), &.{ try store.int(2), try store.int(3) });
        try oracleCheck(alloc, &store, body, 5);
    }
    // P2 : (if (< 1 2) 10 20) -> 10
    {
        var store = Store.init(alloc);
        defer store.deinit();
        const cond = try applyNoFunc(&store, try store.sym("<"), &.{ try store.int(1), try store.int(2) });
        const body = try applyNoFunc(&store, try store.sym("if"), &.{ cond, try store.int(10), try store.int(20) });
        try oracleCheck(alloc, &store, body, 10);
    }
    //     // P3 : (while (< 5 1) 42) → 0
    //     {
    //         var store = Store.init(alloc);
    //         defer store.deinit();
    //         const cond = try applyNoFunc(&store, try store.sym("<"), &.{ try store.int(5), try store.int(1) });
    //         const body = try applyNoFunc(&store, try store.sym("while"), &.{ cond, try store.int(42) });
    //         try oracleCheck(alloc, &store, body, 0);
    //     }
    //     // P4 : (while (< 0 1) (break 7)) → 7
    //     {
    //         var store = Store.init(alloc);
    //         defer store.deinit();
    //         const cond = try applyNoFunc(&store, try store.sym("<"), &.{ try store.int(0), try store.int(1) });
    //         const bk = try applyNoFunc(&store, try store.sym("break"), &.{try store.int(7)});
    //         const body = try applyNoFunc(&store, try store.sym("while"), &.{ cond, bk });
    //         try oracleCheck(alloc, &store, body, 7);
    //     }
}
