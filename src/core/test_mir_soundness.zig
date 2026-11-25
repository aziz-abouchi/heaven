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
        try fd.addClause(&.{pat}, body);
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
        try fd.addClause(&.{pat}, body);
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


test "precompileUserFns — multi-clause sans clause generale compilee avec repli @abort" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var store = expr.Store.init(alloc);
    const env = try expr.Env.create(alloc);
    var engine = engine_expr.Engine.initTest(alloc, &store, env);

    // f 0 = 0 ; f 1 = 1 : aucune clause generale. Pas de valeur par defaut
    // inventee : la chaine se termine par un @abort explicite (echec bruyant si
    // aucun motif ne correspond), ce qui permet de compiler les fonctions
    // exhaustives sans `_` (toks_rev, zlen...). Voir tests/diff/reject.sh.
    const key_sym = try store.interner.intern("f_multi");
    const key = store.interner.resolve(key_sym);
    var fd = engine_expr.FunctionDef{ .clauses = undefined, .num_clauses = 0 };
    try fd.addClause(&.{try store.int(0)}, try store.int(0));
    try fd.addClause(&.{try store.int(1)}, try store.int(1));
    try engine.fns.put(alloc, key, fd);

    var mf = mir.MirFunction.initWithStore(alloc, &store);
    defer mf.deinit();
    mf.engine = &engine;
    try mf.precompileUserFns();

    try std.testing.expect(mf.fn_defs.contains(key_sym));
}

test "precompileUserFns — multi-clause entier + clause generale compilee" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var store = expr.Store.init(alloc);
    const env = try expr.Env.create(alloc);
    var engine = engine_expr.Engine.initTest(alloc, &store, env);

    // f 0 = 1 ; f n = 2
    const key_sym = try store.interner.intern("f_eq");
    const key = store.interner.resolve(key_sym);
    var fd = engine_expr.FunctionDef{ .clauses = undefined, .num_clauses = 0 };
    try fd.addClause(&.{try store.int(0)}, try store.int(1));
    try fd.addClause(&.{try store.sym("n")}, try store.int(2));
    try engine.fns.put(alloc, key, fd);

    var mf = mir.MirFunction.initWithStore(alloc, &store);
    defer mf.deinit();
    mf.engine = &engine;
    try mf.precompileUserFns();

    try std.testing.expect(mf.fn_defs.contains(key_sym));
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
    try fd.addClause(&.{lit_pat}, try store.int(1));
    try engine.fns.put(alloc, key, fd);

    var mf = mir.MirFunction.initWithStore(alloc, &store);
    defer mf.deinit();
    mf.engine = &engine;
    try mf.precompileUserFns();

    try std.testing.expect(!mf.fn_defs.contains(key_sym));
}

test "precompileUserFns — multi-clause avec garde exclue (soundness)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var store = expr.Store.init(alloc);
    const env = try expr.Env.create(alloc);
    var engine = engine_expr.Engine.initTest(alloc, &store, env);

    const key_sym = try store.interner.intern("f_multi_guarded");
    const key = store.interner.resolve(key_sym);

    var fd = engine_expr.FunctionDef{ .clauses = undefined, .num_clauses = 0 };
    try fd.addClause(&.{try store.int(0)}, try store.int(10));
    fd.setLastGuard(try store.boolean(true));
    try fd.addClause(&.{try store.int(1)}, try store.int(20));
    try engine.fns.put(alloc, key, fd);

    var mf = mir.MirFunction.initWithStore(alloc, &store);
    defer mf.deinit();
    mf.engine = &engine;

    try mf.precompileUserFns();

    try std.testing.expect(!mf.fn_defs.contains(key_sym));
}

test "evalFunction — gardes vraies et fausses (interpréteur)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var store = expr.Store.init(alloc);
    const env = try expr.Env.create(alloc);
    var engine = engine_expr.Engine.initTest(alloc, &store, env);

    const arg = try store.int(7);

    // Garde vraie : la première clause doit gagner.
    const true_sym = try store.interner.intern("f_guard_true");
    const true_name = store.interner.resolve(true_sym);
    var true_fd = engine_expr.FunctionDef{ .clauses = undefined, .num_clauses = 0 };
    try true_fd.addClause(&.{try store.sym("n")}, try store.int(10));
    true_fd.setLastGuard(try store.boolean(true));
    try true_fd.addClause(&.{try store.sym("n")}, try store.int(20));
    try engine.fns.put(alloc, true_name, true_fd);

    // Garde fausse : la deuxième clause doit être sélectionnée.
    const false_sym = try store.interner.intern("f_guard_false");
    const false_name = store.interner.resolve(false_sym);
    var false_fd = engine_expr.FunctionDef{ .clauses = undefined, .num_clauses = 0 };
    try false_fd.addClause(&.{try store.sym("n")}, try store.int(10));
    false_fd.setLastGuard(try store.boolean(false));
    try false_fd.addClause(&.{try store.sym("n")}, try store.int(20));
    try engine.fns.put(alloc, false_name, false_fd);

    // Les deux fonctions gardées doivent rester hors du MIR précompilé.
    var mf = mir.MirFunction.initWithStore(alloc, &store);
    defer mf.deinit();
    mf.engine = &engine;
    try mf.precompileUserFns();

    try std.testing.expect(!mf.fn_defs.contains(true_sym));
    try std.testing.expect(!mf.fn_defs.contains(false_sym));

    // L'interpréteur doit néanmoins les exécuter correctement.
    const true_result = try engine.evalFunction(env, true_name, &.{arg});
    const true_node = store.get(true_result);
    try std.testing.expectEqual(expr.Tag.lit, true_node.tag);
    try std.testing.expect(store.lits.items[true_node.aux].eql(.{ .int = 10 }));

    const false_result = try engine.evalFunction(env, false_name, &.{arg});
    const false_node = store.get(false_result);
    try std.testing.expectEqual(expr.Tag.lit, false_node.tag);
    try std.testing.expect(store.lits.items[false_node.aux].eql(.{ .int = 20 }));
}
