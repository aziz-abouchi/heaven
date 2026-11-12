//! Round-trip B0.1 : formatId → parseSExpr → formatId doit être idempotent.
//!
//! Vérifie le critère "dump relisible" de B0.1 sans dépendre de HP.parse
//! (Heaven pur) ni de structuralEql (IDs Store internes).
//!
//! Exclusions documentées :
//!   - relation : parseSExpr produit apply(sym("relation"), …), pas .relation
//!                → round-trip différé à B3 (parse.zig doit apprendre la forme)
//!   - \xNN     : decodeEscapes ne gère pas les contrôles hex
//!                → round-trip différé à B0.2
//!   - lambda   : round-trip string-level OK (paren-branch), couvert si besoin
//!                via un apply(sym("lambda"), …) ; pas testé ici pour ne pas
//!                figer un format que B3 peut vouloir revoir

const std = @import("std");
const expr = @import("expr");
const engine_expr = @import("engine_expr");
const parse = @import("parse");
const sexpr_dump = @import("sexpr_dump");

fn roundtrip(
    alloc: std.mem.Allocator,
    store: *expr.Store,
    engine: *engine_expr.Engine,
    env: *engine_expr.Env,
    id: expr.Id,
) ![]u8 {
    const s1 = try sexpr_dump.formatId(store, id, alloc);
    defer alloc.free(s1);
    var p = parse.Parser.init(store, engine, env, alloc);
    defer p.deinit();
    const reparsed = try p.parseSExpr(s1);
    return try sexpr_dump.formatId(store, reparsed, alloc);
}

test "roundtrip B0.1 — int, float, str, sym, apply, bind (string-level)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var store = expr.Store.init(alloc);
    var env = try expr.Env.create(alloc);
    defer env.unref();
    var engine = engine_expr.Engine.initTest(alloc, &store, env);

    const f = try store.sym("f");
    const a = try store.int(1);
    const b = try store.int(2);
    const n_sym = try store.interner.intern("n");
    const y = try store.sym("y");
    const five = try store.int(5);
    const str_ab = try store.interner.intern("a\\b");

    const cases = [_]struct { id: expr.Id, expect: []const u8 }{
        .{ .id = try store.int(3),                  .expect = "3" },
        .{ .id = try store.float(3.0),              .expect = "3.0" },
        .{ .id = try store.lit(.{ .str = str_ab }), .expect = "\"a\\\\b\"" },
        .{ .id = f,                                  .expect = "f" },
        .{ .id = try store.apply(f, &.{ a, b }),    .expect = "(f 1 2)" },
        .{ .id = try store.bindSymWithBody(n_sym, five, y), .expect = "(let n 5 y)" },
    };

    for (cases) |c| {
        // 1) formatId produit le canonique attendu
        const s1 = try sexpr_dump.formatId(&store, c.id, alloc);
        try std.testing.expectEqualStrings(c.expect, s1);

        // 2) parseSExpr relit, formatId re-produit : idempotence string-level
        const s2 = try roundtrip(alloc, &store, &engine, env, c.id);
        try std.testing.expectEqualStrings(s1, s2);
    }
}
