//! Tests unitaires de soundness du MIR, isolés de mir.zig.
//!
//! Raison de l'isolation : les 16 tests historiques dans mir.zig sont
//! endormis (aucun addTest ne les exécute) ET désynchronisés de l'API
//! actuelle (unlower, register, signatures). Les réveiller est une
//! tâche dédiée ; ce fichier n'expose que les tests soundness.
//!
//! Champ accédé : MirFunction.fn_defs est un champ de struct pub ;
//! accessible depuis ce fichier sans modification de mir.zig.

const std = @import("std");
const expr = @import("expr");
const engine_expr = @import("engine_expr");
const mir = @import("mir");

test "precompileUserFns — clause gardée exclue de fn_defs (soundness)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var store = expr.Store.init(alloc);
    const env = try expr.Env.create(alloc);
    var engine = engine_expr.Engine.initTest(alloc, &store, env);

    // ── Cas témoin : clause NON gardée → doit entrer dans fn_defs ──
    {
        const pat = try store.sym("n");
        const body = try store.int(1);
        const key_sym = try store.interner.intern("f_unguarded");
        const key = store.interner.resolve(key_sym);
        var fd = engine_expr.FunctionDef{ .clauses = undefined, .num_clauses = 0 };
        fd.addClause(&.{pat}, body);
        try engine.fns.put(alloc, key, fd);

        var mf = mir.MirFunction.initWithStore(alloc, &store);
        defer mf.deinit();
        mf.engine = &engine;

        try mf.precompileUserFns();

        const name_sym = store.interner.lookup("f_unguarded").?;
        try std.testing.expect(mf.fn_defs.contains(name_sym));
    }

    // ── Cas défaut : clause GARDÉE → doit être exclue ──
    {
        const pat = try store.sym("n");
        const body = try store.int(2);
        const guard = try store.boolean(true);
        const key_sym = try store.interner.intern("f_guarded");
        const key = store.interner.resolve(key_sym);
        var fd = engine_expr.FunctionDef{ .clauses = undefined, .num_clauses = 0 };
        fd.addClause(&.{pat}, body);
        fd.setLastGuard(guard);
        try engine.fns.put(alloc, key, fd);

        var mf = mir.MirFunction.initWithStore(alloc, &store);
        defer mf.deinit();
        mf.engine = &engine;

        try mf.precompileUserFns();

        const name_sym = store.interner.lookup("f_guarded").?;
        try std.testing.expect(!mf.fn_defs.contains(name_sym));
    }
}


test "precompileUserFns — multi-clause exclue de fn_defs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var store = expr.Store.init(alloc);
    const env = try expr.Env.create(alloc);
    var engine = engine_expr.Engine.initTest(alloc, &store, env);

    const pat = try store.sym("n");
    const key_sym = try store.interner.intern("f_multi");
    const key = store.interner.resolve(key_sym);
    var fd = engine_expr.FunctionDef{ .clauses = undefined, .num_clauses = 0 };
    fd.addClause(&.{pat}, try store.int(0));
    fd.addClause(&.{pat}, try store.int(1));
    try engine.fns.put(alloc, key, fd);

    var mf = mir.MirFunction.initWithStore(alloc, &store);
    defer mf.deinit();
    mf.engine = &engine;
    try mf.precompileUserFns();

    try std.testing.expect(!mf.fn_defs.contains(key_sym));
}

test "precompileUserFns — motif constructeur exclu de fn_defs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var store = expr.Store.init(alloc);
    const env = try expr.Env.create(alloc);
    var engine = engine_expr.Engine.initTest(alloc, &store, env);

    const lit_pat = try store.int(0);
    const key_sym = try store.interner.intern("f_pattern");
    const key = store.interner.resolve(key_sym);
    var fd = engine_expr.FunctionDef{ .clauses = undefined, .num_clauses = 0 };
    fd.addClause(&.{lit_pat}, try store.int(1));
    try engine.fns.put(alloc, key, fd);

    var mf = mir.MirFunction.initWithStore(alloc, &store);
    defer mf.deinit();
    mf.engine = &engine;
    try mf.precompileUserFns();

    try std.testing.expect(!mf.fn_defs.contains(key_sym));
}
