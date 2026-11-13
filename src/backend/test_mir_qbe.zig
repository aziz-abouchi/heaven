//! Tests M3 : MIR → QBE → asm natif → binaire → exécution.
//! Oracle : mir.execute (référence). Skip si qbe/cc absents.

const std = @import("std");
const mir = @import("mir");
const expr = @import("expr");
const engine_expr = @import("engine_expr");
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



/// qbe → cc → run. Retourne le i64 imprimé par le wrapper $main.
fn runNative(alloc: std.mem.Allocator, ssa: []const u8) !i64 {
    // QBE aarch64 Darwin : binaire retourne un pointeur au lieu de la valeur.
    // Backend QBE moins mature que x86_64. Interpreteur (mf.execute) reste teste.
    if (@import("builtin").os.tag.isDarwin()) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "prog.ssa", .data = ssa });
    // QBE v1.2 : chemin absolu injecte par build.zig (build_options).
    // C'est la seule facon fiable : `zig build test` execute le
    // binaire depuis .zig-cache/o/..., pas depuis la racine du repo,
    // donc tout chemin relatif est casse.
    const qbe_path = build_options.qbe_path;
    std.fs.accessAbsolute(qbe_path, .{}) catch {
        // HEAVEN_STRICT_QBE=1 (CI) : panique au lieu de skipper, pour
        // que la CI échoue si QBE n'est pas construit par build.sh.
        // Sans cette var, comportement local inchangé (skip silencieux).
        const strict = std.process.hasEnvVar(std.testing.allocator, "HEAVEN_STRICT_QBE") catch false;
        if (strict) @panic("HEAVEN_STRICT_QBE=1 but qbe binary missing (vendor/qbe-1.2/qbe). Run 'bash build.sh' first.");
        return error.SkipZigTest;
    };
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
    defer mf.deinit();

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
    // P3 : (while (< 5 1) 42) -> 0
    {
        var store = Store.init(alloc);
        defer store.deinit();
        const cond = try applyNoFunc(&store, try store.sym("<"), &.{ try store.int(5), try store.int(1) });
        const body = try applyNoFunc(&store, try store.sym("while"), &.{ cond, try store.int(42) });
        try oracleCheck(alloc, &store, body, 0);
    }
    // P4 : (while (< 0 1) (break 7)) -> 7
    {
        var store = Store.init(alloc);
        defer store.deinit();
        const cond = try applyNoFunc(&store, try store.sym("<"), &.{ try store.int(0), try store.int(1) });
        const bk = try applyNoFunc(&store, try store.sym("break"), &.{try store.int(7)});
        const body = try applyNoFunc(&store, try store.sym("while"), &.{ cond, bk });
        try oracleCheck(alloc, &store, body, 7);
    }
}

test "qbe — rejet : call_user hors fn_defs (contrat §6)" {
    const alloc = std.testing.allocator;
    var store = Store.init(alloc);
    defer store.deinit();

    var mf = MirFunction.initWithStore(alloc, &store);
    defer mf.deinit();
    const entry = try mf.newBlock();

    // arguments alloues (comme compileExpr les aurait fait).
    // deinit() de MirFunction libere .call_user.args, donc pas de
    // defer ici : ca ferait un double free.
    const args = try alloc.alloc(mir.Id, 0);

    try mf.blocks.items[entry].instrs.append(alloc, .{
        .call_user = .{
            .dest = mf.newReg(),
            .name = 0xDEADBEEF, // jamais dans fn_defs
            .args = args,
        },
    });
    mf.blocks.items[entry].terminator = .{ .ret = 0 };

    // Contrat : call_user hors fn_defs → error.UnsupportedCall.
    // Un stub ret 0 retournerait un résultat faux silencieux : refusé.
    // if/catch explicite (pas expectError) : sur succès, le buffer
    // doit être libéré, sinon leak.
    if (qbe.emitQbe(alloc, &mf)) |buf| {
        alloc.free(buf);
        return error.TestExpectedError;
    } else |err| {
        try std.testing.expectEqual(@as(anyerror, error.UnsupportedCall), @as(anyerror, err));
    }
}

test "qbe — shape : emitQbe produit la structure attendue (sans QBE)" {
    const alloc = std.testing.allocator;
    var store = Store.init(alloc);
    defer store.deinit();

    // (+ 2 3) : pipeline complet sauf invocation QBE.
    const body = try applyNoFunc(&store, try store.sym("+"), &.{ try store.int(2), try store.int(3) });
    var mf = try compileRoot(alloc, &store, body);
    defer mf.deinit();

    const ssa = try qbe.emitQbe(alloc, &mf);
    defer alloc.free(ssa);

    // Structure obligatoire :
    // 1. wrapper heaven_main (le MIR root)
    try std.testing.expect(has(ssa, "function l $heaven_main()"));
    // 2. wrapper main export (QBE exige export+function sur une ligne)
    try std.testing.expect(has(ssa, "export function l $main()"));
    // 3. appel printf + data $fmt pour le resultat i64
    try std.testing.expect(has(ssa, "call $printf(l $fmt, l "));
    try std.testing.expect(has(ssa, "data $fmt = { b \"%ld\\n\", b 0 }"));
    // 4. pas de tabulation en indentation (QBE rejette)
    try std.testing.expect(!has(ssa, "\t"));
    // 5. un bloc @b0 par fonction
    try std.testing.expect(has(ssa, "@b0"));
    // 6. retour MIR traduit
    try std.testing.expect(has(ssa, "ret %r"));

    // Et pas de régression silencieuse : les N ouvrants/accolades
    // doivent être équilibrés.
    var opens: u32 = 0;
    var closes: u32 = 0;
    for (ssa) |c| {
        if (c == '{') opens += 1;
        if (c == '}') closes += 1;
    }
    try std.testing.expectEqual(opens, closes);
}

fn has(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}


test "qbe — transitif : éligible appelle exclu → UnsupportedCall" {
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

    // f : 1 clause, pattern sym, corps = (g n) → éligible
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
    // g : 1 clause gardée → exclue
    {
        const n_id = try store.sym("n");
        const g_body = try store.int(1);
        const g_guard = try store.boolean(true);
        const key_sym = try store.interner.intern("g");
        const key = store.interner.resolve(key_sym);
        var fd = engine_expr.FunctionDef{ .clauses = undefined, .num_clauses = 0 };
        try fd.addClause(&.{n_id}, g_body);
        fd.setLastGuard(g_guard);
        try engine.fns.put(alloc, key, fd);
    }

    var mf = MirFunction.initWithStore(alloc, &store);
    defer mf.deinit();
    mf.engine = &engine;
    try mf.precompileUserFns();

    const f_sym = store.interner.lookup("f").?;
    const g_sym = store.interner.lookup("g").?;
    try std.testing.expect(mf.fn_defs.contains(f_sym));
    try std.testing.expect(!mf.fn_defs.contains(g_sym));

    const entry = try mf.newBlock();
    var locals = std.AutoHashMap(u32, Reg).init(alloc);
    defer locals.deinit();
    const f_id = try store.sym("f");
    const root_body = try store.apply(f_id, &.{try store.int(1)});
    const result = try mf.compileExpr(&store, root_body, entry, locals);
    if (mf.blocks.items[entry].terminator == .fallthrough) {
        mf.blocks.items[entry].terminator = .{ .ret = result };
    }

    if (qbe.emitQbe(alloc, &mf)) |buf| {
        alloc.free(buf);
        return error.TestExpectedError;
    } else |err| {
        try std.testing.expectEqual(@as(anyerror, error.UnsupportedCall), @as(anyerror, err));
    }
}
