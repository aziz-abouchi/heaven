//! Round-trip B0.1 : formatId → parseSExpr → formatId doit être idempotent.
//!
//! Vérifie le critère "dump relisible" de B0.1 sans dépendre de HP.parse
//! (Heaven pur) ni de structuralEql (IDs Store internes).
//!
//! Limites du critère de relecture (B0.1) :
//!   - relation : parseSExpr produit apply(sym("relation"), …), pas .relation.
//!                Le dump n'est pas relisible à l'identique → B3.
//!   - \xNN     : formatId ÉMET \x01 pour les contrôles, decodeEscapes ne sait
//!                pas les relire. Le dump n'est donc pas relisible pour ces
//!                caractères : c'est une entorse au critère, pas une dette
//!                cosmétique. Corriger en B0.2 (decodeEscapes ou format).
//!   - lambda   : couvert en relecture depuis a5723ed (`(lambda n y)` testé).
//!                Format susceptible d'évoluer en B3 ; l'ajuster à ce moment-là.

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

    const cases = [_]struct { id: expr.Id, expect: ?[]const u8, min_len: usize = 0 }{
        .{ .id = try store.int(3),                  .expect = "3" },
        .{ .id = try store.float(3.0),              .expect = "3.0" },
        .{ .id = try store.lit(.{ .str = str_ab }), .expect = "\"a\\\\b\"" },
        .{ .id = f,                                  .expect = "f" },
        .{ .id = try store.apply(f, &.{ a, b }),    .expect = "(f 1 2)" },
        .{ .id = try store.bindSymWithBody(n_sym, five, y), .expect = "(let n 5 y)" },
        // Float extrêmes : {d} sans exposant, ~300 caractères. Tampon fixe crashait.
        .{ .id = try store.float(1e300),  .expect = null, .min_len = 250 },
        .{ .id = try store.float(1e-300), .expect = null, .min_len = 250 },
        // Lambda : couvre la 5e primitive (relation reste exclue, cf. en-tête).
        .{ .id = try store.lambda(&[_][]const u8{"n"}, y), .expect = "(lambda n y)" },
    };

    for (cases) |c| {
        // 1) formatId produit le canonique attendu (null = non contraint, juste non-vide)
        const s1 = try sexpr_dump.formatId(&store, c.id, alloc);
        if (c.expect) |exp| {
            try std.testing.expectEqualStrings(exp, s1);
        } else {
            // Floats extrêmes : {d} sans exposant, ~300 caractères.
            // Vérifie que la sortie est longue, pas juste non-vide — le
            // bug initial (bufPrint[64]) aurait produit NoSpaceLeft.
            const min: usize = if (c.min_len == 0) 1 else c.min_len;
            try std.testing.expect(s1.len >= min);
        }

        // 2) parseSExpr relit, formatId re-produit : idempotence string-level
        const s2 = try roundtrip(alloc, &store, &engine, env, c.id);
        try std.testing.expectEqualStrings(s1, s2);
    }
}
