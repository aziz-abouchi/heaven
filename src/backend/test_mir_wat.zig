//! Tests M2a : MIR → WAT (fragments golden). L'oracle de sémantique
//! reste mir.execute ; l'exécution réelle du WAT (wasmtime) = M2b.

const std = @import("std");
const mir = @import("mir");
const expr = @import("expr");
const engine_expr = @import("engine_expr");
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
    var cur_entry = entry;
    const result = try mf.compileExpr(store, body, &cur_entry, locals);
    // Ne pas écraser un terminator posé par compileIf (branch).
    if (mf.blocks.items[cur_entry].terminator == .fallthrough) {
        mf.blocks.items[cur_entry].terminator = .{ .ret = result };
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

test "wat — call_user hors fn_defs → UnsupportedCall" {
    // Contrat : call_user hors fn_defs → error.UnsupportedCall.
    // Un stub i64.const 0 retournerait un résultat faux silencieux : refusé.
    const alloc = std.testing.allocator;
    var root = MirFunction.init(alloc);
    defer root.deinit();
    const entry = try root.newBlock();
    const a = root.newReg();
    try root.blocks.items[entry].instrs.append(alloc, .{ .call_user = .{ .dest = a, .name = 7, .args = &.{} } });
    root.blocks.items[entry].terminator = .{ .ret = a };
    if (wat.emitWat(alloc, &root)) |buf| {
        alloc.free(buf);
        return error.TestExpectedError;
    } else |err| {
        try std.testing.expectEqual(@as(anyerror, error.UnsupportedCall), @as(anyerror, err));
    }
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


test "wat — transitif : éligible appelle exclu → UnsupportedCall" {
    // Arena : libère store, env, engine, mf, et engine.fns (hash map
    // alloué par put) d'un coup. Les defer existants deviennent des
    // no-ops (arena.free = no-op) mais restent pour la lisibilité.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var store = Store.init(alloc);
    defer store.deinit();
    const env = try expr.Env.create(alloc);
    defer env.unref();
    var engine = engine_expr.Engine.initTest(alloc, &store, env);

    {
        const n_id = try store.sym("n");
        const g_id = try store.sym("g");
        const f_body = try store.apply(g_id, &.{n_id});
        const key_sym = try store.interner.intern("f");
        const key = store.interner.resolve(key_sym);
        var fd = engine_expr.FunctionDef{ .clauses = undefined, .num_clauses = 0 };
        try fd.addClause(&.{n_id}, f_body);
        try engine.fns.put(alloc, key, fd);
    }
    {
        const n_id = try store.sym("n");
        const g_body = try store.int(1);
        const key_sym = try store.interner.intern("g");
        const key = store.interner.resolve(key_sym);
        var fd = engine_expr.FunctionDef{ .clauses = undefined, .num_clauses = 0 };
        try fd.addClause(&.{n_id}, g_body);
        fd.clauses[0].patterns[0] = try store.lit(.{ .str = try store.interner.intern("excluded") });
        try engine.fns.put(alloc, key, fd);
    }

    var mf = MirFunction.initWithStore(alloc, &store);
    defer mf.deinit();
    mf.engine = &engine;
    try mf.precompileUserFns();

    const f_sym = store.interner.lookup("f").?;
    const g_sym = store.interner.lookup("g").?;
    // Contrat (retrait transitif) : f (eligible) appelle g (exclue) -> f est
    // retiree de fn_defs au lieu d'empoisonner tout le module. L'appel de la
    // racine vers f reste rejete explicitement (UnsupportedCall), jamais stubbe.
    try std.testing.expect(!mf.fn_defs.contains(f_sym));
    try std.testing.expect(!mf.fn_defs.contains(g_sym));

    const entry = try mf.newBlock();
    var locals = std.AutoHashMap(u32, Reg).init(alloc);
    defer locals.deinit();
    const f_id = try store.sym("f");
    const root_body = try store.apply(f_id, &.{try store.int(1)});
    var cur_entry = entry;
    const result = try mf.compileExpr(&store, root_body, &cur_entry, locals);
    if (mf.blocks.items[cur_entry].terminator == .fallthrough) {
        mf.blocks.items[cur_entry].terminator = .{ .ret = result };
    }

    if (wat.emitWat(alloc, &mf)) |buf| {
        alloc.free(buf);
        return error.TestExpectedError;
    } else |err| {
        try std.testing.expectEqual(@as(anyerror, error.UnsupportedCall), @as(anyerror, err));
    }
}

test "wat — non-terminal if in arithmetic expression with let binding" {
    const alloc = std.testing.allocator;
    var store = Store.init(alloc);
    defer store.deinit();

    const cond = try applyNoFunc(&store, try store.sym("<"), &.{ try store.int(1), try store.int(2) });
    const if_expr = try applyNoFunc(&store, try store.sym("if"), &.{ cond, try store.int(2), try store.int(3) });
    const add_expr = try applyNoFunc(&store, try store.sym("+"), &.{ if_expr, try store.int(1) });

    var mf = try compileRoot(alloc, &store, add_expr);
    defer mf.deinit();

    var globals = std.AutoHashMap(u32, i64).init(alloc);
    defer globals.deinit();
    const oracle = try mf.execute(&globals);
    try std.testing.expectEqual(@as(i64, 3), oracle);

    const out_wat = try wat.emitWat(alloc, &mf);
    defer alloc.free(out_wat);
    try std.testing.expect(out_wat.len > 0);
}

test "wat — nested non-terminal if inside arithmetic expression" {
    const alloc = std.testing.allocator;
    var store = Store.init(alloc);
    defer store.deinit();

    const outer_cond = try applyNoFunc(&store, try store.sym("<"), &.{ try store.int(1), try store.int(2) });
    const inner_cond = try applyNoFunc(&store, try store.sym(">"), &.{ try store.int(5), try store.int(2) });
    const inner_if = try applyNoFunc(&store, try store.sym("if"), &.{ inner_cond, try store.int(10), try store.int(20) });
    const outer_if = try applyNoFunc(&store, try store.sym("if"), &.{ outer_cond, inner_if, try store.int(30) });
    const mul_expr = try applyNoFunc(&store, try store.sym("*"), &.{ outer_if, try store.int(2) });

    var mf = try compileRoot(alloc, &store, mul_expr);
    defer mf.deinit();

    var globals = std.AutoHashMap(u32, i64).init(alloc);
    defer globals.deinit();
    const oracle = try mf.execute(&globals);
    try std.testing.expectEqual(@as(i64, 20), oracle);

    const out_wat = try wat.emitWat(alloc, &mf);
    defer alloc.free(out_wat);
    try std.testing.expect(out_wat.len > 0);
}

test "wat — non-terminal if inside break expression" {
    const alloc = std.testing.allocator;
    var store = Store.init(alloc);
    defer store.deinit();

    const if_cond = try applyNoFunc(&store, try store.sym("<"), &.{ try store.int(1), try store.int(2) });
    const if_val = try applyNoFunc(&store, try store.sym("if"), &.{ if_cond, try store.int(42), try store.int(99) });
    const brk = try applyNoFunc(&store, try store.sym("break"), &.{if_val});
    const loop_cond = try applyNoFunc(&store, try store.sym("<"), &.{ try store.int(0), try store.int(1) });
    const loop_expr = try applyNoFunc(&store, try store.sym("while"), &.{ loop_cond, brk });

    var mf = try compileRoot(alloc, &store, loop_expr);
    defer mf.deinit();

    var globals = std.AutoHashMap(u32, i64).init(alloc);
    defer globals.deinit();
    const oracle = try mf.execute(&globals);
    try std.testing.expectEqual(@as(i64, 42), oracle);

    const out_wat = try wat.emitWat(alloc, &mf);
    defer alloc.free(out_wat);
    try std.testing.expect(out_wat.len > 0);
}

test "wat — heap : alloc, store_at et load_at (offsets 0 et 8)" {
    const alloc = std.testing.allocator;
    var mf = MirFunction.init(alloc);
    defer mf.deinit();

    const entry = try mf.newBlock();
    const base_r = mf.newReg();
    const v0_r = mf.newReg();
    const v1_r = mf.newReg();
    const l0_r = mf.newReg();
    const l1_r = mf.newReg();
    const sum_r = mf.newReg();

    try mf.blocks.items[entry].instrs.append(alloc, .{ .alloc = .{ .dest = base_r, .size = 16 } });
    try mf.blocks.items[entry].instrs.append(alloc, .{ .const_int = .{ .dest = v0_r, .value = 17 } });
    try mf.blocks.items[entry].instrs.append(alloc, .{ .const_int = .{ .dest = v1_r, .value = 25 } });
    try mf.blocks.items[entry].instrs.append(alloc, .{ .store_at = .{ .base = base_r, .offset = 0, .src = v0_r } });
    try mf.blocks.items[entry].instrs.append(alloc, .{ .store_at = .{ .base = base_r, .offset = 8, .src = v1_r } });
    try mf.blocks.items[entry].instrs.append(alloc, .{ .load_at = .{ .dest = l0_r, .base = base_r, .offset = 0 } });
    try mf.blocks.items[entry].instrs.append(alloc, .{ .load_at = .{ .dest = l1_r, .base = base_r, .offset = 8 } });
    try mf.blocks.items[entry].instrs.append(alloc, .{ .add = .{ .dest = sum_r, .lhs = l0_r, .rhs = l1_r } });
    mf.blocks.items[entry].terminator = .{ .ret = sum_r };

    const out = try wat.emitWat(alloc, &mf);
    defer alloc.free(out);

    try std.testing.expect(has(out, "(memory (export \"memory\") 1)"));
    try std.testing.expect(has(out, "$heap_ptr"));
    // Invariant MIR : pointeur de tas >= 4096 (sinon ADT n-aire mal filtre).
    try std.testing.expect(wat.heap_base >= 4096);
    try std.testing.expect(has(out, "(global $heap_ptr (mut i32) (i32.const 4096))"));
    try std.testing.expect(has(out, "i64.store"));
    try std.testing.expect(has(out, "i64.load"));

    const got = try runWasmtime(alloc, out);
    try std.testing.expectEqual(@as(i64, 42), got);
}

test "wasi — execution bout-en-bout du binaire heaven-wasi (wasmtime / wasmer)" {
    const alloc = std.testing.allocator;
    const wasm_path = "zig-out/bin/heaven-wasi.wasm";
    std.fs.cwd().access(wasm_path, .{}) catch return error.SkipZigTest;

    const runner: ?[]const u8 = blk: {
        for ([_][]const u8{ "wasmtime", "wasmer" }) |cmd| {
            var child = std.process.Child.init(&.{ cmd, "--version" }, alloc);
            child.stdout_behavior = .Ignore;
            child.stderr_behavior = .Ignore;
            if (child.spawnAndWait()) |term| {
                switch (term) {
                    .Exited => |code| if (code == 0) break :blk cmd,
                    else => {},
                }
            } else |_| {}
        }
        break :blk null;
    };
    const bin = runner orelse return error.SkipZigTest;

    const argv: []const []const u8 = if (std.mem.eql(u8, bin, "wasmtime"))
        &.{ bin, "run", wasm_path, "(+ 17 25)" }
    else
        &.{ bin, "run", wasm_path, "--", "(+ 17 25)" };

    const res = try std.process.Child.run(.{
        .allocator = alloc,
        .argv = argv,
    });
    defer alloc.free(res.stdout);
    defer alloc.free(res.stderr);

    try std.testing.expectEqual(@as(u8, 0), switch (res.term) {
        .Exited => |c| c,
        else => 1,
    });
    const trimmed = std.mem.trim(u8, res.stdout, " \t\r\n");
    try std.testing.expectEqualStrings("42", trimmed);
}

test "wat — chaines : segments de donnees, tas apres les donnees, strcmp en WAT" {
    const alloc = std.testing.allocator;
    var mf = MirFunction.init(alloc);
    defer mf.deinit();
    try mf.str_pool.append(alloc, "ab"); // 4096..4098 (NUL inclus)
    try mf.str_pool.append(alloc, "abc"); // 4099..4102
    const entry = try mf.newBlock();
    const a = mf.newReg();
    const b = mf.newReg();
    try mf.blocks.items[entry].instrs.append(alloc, .{ .const_str = .{ .dest = a, .sym = 0 } });
    try mf.blocks.items[entry].instrs.append(alloc, .{ .const_str = .{ .dest = b, .sym = 1 } });
    mf.blocks.items[entry].terminator = .{ .ret = b };

    const out = try wat.emitWat(alloc, &mf);
    defer alloc.free(out);

    // Donnees a partir de heap_base, une chaine apres l'autre (NUL final).
    try std.testing.expect(has(out, "(data (i32.const 4096) \"\\61\\62\\00\")"));
    try std.testing.expect(has(out, "(data (i32.const 4099) \"\\61\\62\\63\\00\")"));
    // const_str = adresse de la donnee, plus de trap.
    try std.testing.expect(has(out, "(i64.const 4096)"));
    try std.testing.expect(has(out, "(i64.const 4099)"));
    try std.testing.expect(!has(out, "const_str not yet"));
    // Le tas demarre apres les donnees (4103 arrondi a 8 = 4104), >= 4096.
    try std.testing.expect(has(out, "(global $heap_ptr (mut i32) (i32.const 4104))"));
    try std.testing.expect(has(out, "$__strcmp"));
}
