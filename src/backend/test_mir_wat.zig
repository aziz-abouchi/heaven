//! Tests M2a : MIR → WAT (fragments golden). L'oracle de sémantique
//! reste mir.execute ; l'exécution réelle du WAT (wasmtime) = M2b.

const std = @import("std");
const mir = @import("mir");
const expr = @import("expr");
const wat = @import("mir_wat.zig");

const Store = expr.Store;
const MirFunction = mir.MirFunction;
const Reg = mir.Reg;

/// Convention attendue par compileExpr : span_a = args SEULS,
/// payload = func. (store.apply peut préfixer func dans span_a —
/// cf. expr.applyArgs ; construction manuelle pour être
/// indépendant de la convention.)
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
    // Ne pas écraser un terminator posé par compileIf (branch).
    if (mf.blocks.items[entry].terminator == .fallthrough) {
        mf.blocks.items[entry].terminator = .{ .ret = result };
    }
    return mf;
}

fn has(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

test "wat — arithmétique (+ 2 3)" {
    const alloc = std.testing.allocator;
    var store = Store.init(alloc);
    defer store.deinit();
    const plus = try store.sym("+");
    const two = try store.int(2);
    const three = try store.int(3);
    const body = try applyNoFunc(&store, plus, &.{ two, three });
    var mf = try compileRoot(alloc, &store, body);
    defer mf.deinit();
    const out = try wat.emitWat(alloc, &mf);
    defer alloc.free(out);
    try std.testing.expect(has(out, "(export \"main\")"));
    try std.testing.expect(has(out, "(i64.const 2)"));
    try std.testing.expect(has(out, "(i64.const 3)"));
    try std.testing.expect(has(out, "i64.add"));
    try std.testing.expect(has(out, "(return (local.get $r"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, out, "$g"));
}

test "wat — if : branch, dispatch, global" {
    const alloc = std.testing.allocator;
    var store = Store.init(alloc);
    defer store.deinit();
    const if_s = try store.sym("if");
    const lt = try store.sym("<");
    const x = try store.sym("x");
    const cond = try applyNoFunc(&store, lt, &.{ x, try store.int(2) });
    const body = try applyNoFunc(&store, if_s, &.{ cond, try store.int(10), try store.int(20) });
    var mf = try compileRoot(alloc, &store, body);
    defer mf.deinit();
    const out = try wat.emitWat(alloc, &mf);
    defer alloc.free(out);
    try std.testing.expect(has(out, "(global $g"));
    try std.testing.expect(has(out, "i64.lt_s"));
    try std.testing.expect(has(out, "i64.extend_i32_s"));
    try std.testing.expect(has(out, "(loop $dispatch"));
    try std.testing.expect(has(out, "br $dispatch"));
    // entry + then + else + merge = 4 gardes de dispatch.
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, out, "(if (i32.eq (local.get $cur)"));
}

test "wat — fn_defs : fonction séparée et appel" {
    const alloc = std.testing.allocator;
    var root = MirFunction.init(alloc);
    defer root.deinit();
    const entry = try root.newBlock();
    const a = root.newReg();
    const b = root.newReg();
    const c = root.newReg();
    try root.blocks.items[entry].instrs.append(alloc, .{ .const_int = .{ .dest = a, .value = 20 } });
    try root.blocks.items[entry].instrs.append(alloc, .{ .const_int = .{ .dest = b, .value = 22 } });
    const args42 = try alloc.dupe(u32, &.{ a, b });
    try root.blocks.items[entry].instrs.append(alloc, .{ .call_user = .{ .dest = c, .name = 42, .args = args42 } });
    root.blocks.items[entry].terminator = .{ .ret = c };

    var fn_mir = MirFunction.init(alloc);
    const fentry = try fn_mir.newBlock();
    const p0 = fn_mir.newReg();
    fn_mir.blocks.items[fentry].terminator = .{ .ret = p0 };
    try root.fn_defs.put(42, .{
        .fn_mir = fn_mir,
        .param_names = &[_]u32{},
        .param_regs = try alloc.dupe(u32, &[_]u32{p0}),
    });

    const out = try wat.emitWat(alloc, &root);
    defer alloc.free(out);
    try std.testing.expect(has(out, "(func $f42 (param $p0 i64) (result i64)"));
    try std.testing.expect(has(out, "(local.set $r0 (local.get $p0))"));
    try std.testing.expect(has(out, "(local.set $r2 (call $f42 (local.get $r0) (local.get $r1)))"));
}

test "wat — call_user hors fn_defs : rejet explicite" {
    const alloc = std.testing.allocator;
    var root = MirFunction.init(alloc);
    defer root.deinit();
    const entry = try root.newBlock();
    const a = root.newReg();
    try root.blocks.items[entry].instrs.append(alloc, .{ .call_user = .{ .dest = a, .name = 7, .args = &.{} } });
    root.blocks.items[entry].terminator = .{ .ret = a };
    try std.testing.expectError(error.UnsupportedCall, wat.emitWat(alloc, &root));
}

test "wat — M2b : oracle mir.execute vs wasmtime" {
    const alloc = std.testing.allocator;

    // P1 : (+ 2 3) → 5 — arithmétique linéaire
    {
        var store = Store.init(alloc);
        defer store.deinit();
        const body = try applyNoFunc(&store, try store.sym("+"), &.{ try store.int(2), try store.int(3) });
        try oracleCheck(alloc, &store, body, 5);
    }
    // P2 : (if (< 1 2) 10 20) → 10 — branch + phi de merge
    {
        var store = Store.init(alloc);
        defer store.deinit();
        const cond = try applyNoFunc(&store, try store.sym("<"), &.{ try store.int(1), try store.int(2) });
        const body = try applyNoFunc(&store, try store.sym("if"), &.{ cond, try store.int(10), try store.int(20) });
        try oracleCheck(alloc, &store, body, 10);
    }
    // P3 : (while (< 5 1) 42) → 0 — boucle jamais entrée
    {
        var store = Store.init(alloc);
        defer store.deinit();
        const cond = try applyNoFunc(&store, try store.sym("<"), &.{ try store.int(5), try store.int(1) });
        const body = try applyNoFunc(&store, try store.sym("while"), &.{ cond, try store.int(42) });
        try oracleCheck(alloc, &store, body, 0);
    }
    // P4 : (while (< 0 1) (break 7)) → 7 — break + phi à travers dispatch
    {
        var store = Store.init(alloc);
        defer store.deinit();
        const cond = try applyNoFunc(&store, try store.sym("<"), &.{ try store.int(0), try store.int(1) });
        const bk = try applyNoFunc(&store, try store.sym("break"), &.{try store.int(7)});
        const body = try applyNoFunc(&store, try store.sym("while"), &.{ cond, bk });
        try oracleCheck(alloc, &store, body, 7);
    }
}
// ═══ M2b : helpers — exécution wasmtime + comparaison oracle ═══



fn runWasmtime(alloc: std.mem.Allocator, wat_src: []const u8) !i64 {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "prog.wat", .data = wat_src });
    const dir_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(dir_path);
    const wat_path = try std.fs.path.join(alloc, &.{ dir_path, "prog.wat" });
    defer alloc.free(wat_path);

    var child = std.process.Child.init(&.{ "wasmtime", "run", "--invoke", "main", wat_path }, alloc);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.spawn() catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    const stdout = try child.stdout.?.readToEndAlloc(alloc, 4096);
    defer alloc.free(stdout);
    const stderr = try child.stderr.?.readToEndAlloc(alloc, 4096);
    defer alloc.free(stderr);
    // Note : en Zig 0.15, l'erreur de spawn (FileNotFound si
    // wasmtime absent) peut etre differement rapportee au wait()
    // selon le POSIX. On catch ici aussi, cas observe en CI.
    const term = child.wait() catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    const code = switch (term) { .Exited => |c| c, else => return error.WasmtimeFailed };
    if (code != 0) {
        std.debug.print("wasmtime stderr: {s}\n", .{stderr});
        return error.WasmtimeFailed;
    }
    return std.fmt.parseInt(i64, std.mem.trim(u8, stdout, " \t\r\n"), 10) catch error.WasmtimeFailed;
}

fn oracleCheck(alloc: std.mem.Allocator, store: *Store, body: expr.Id, expected: i64) !void {
    var mf = try compileRoot(alloc, store, body);
    defer mf.deinit();

    var globals = std.AutoHashMap(u32, i64).init(alloc);
    defer globals.deinit();
    const oracle = try mf.execute(&globals);
    try std.testing.expectEqual(expected, oracle);

    const src = try wat.emitWat(alloc, &mf);
    defer alloc.free(src);
    const got = try runWasmtime(alloc, src);
    try std.testing.expectEqual(expected, got);
}
