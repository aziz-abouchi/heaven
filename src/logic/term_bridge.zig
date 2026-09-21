//! Passerelle Term (Kanren) → Id (Core).
//!
//! Le moteur Kanren raisonne sur des `Term` (langage logique),
//! le noyau Core manipule des `expr.Id` (références dans un `Store`).
//!
//! Cette passerelle permet à `typeo.zig` de convertir ses résultats
//! (inférence / synthèse) en expressions Core exploitables par l'EGraph,
//! le codegen, le checker, etc.
//!
//! Voir aussi `src/syntax/core_lower.zig` : c'est l'autre étage
//! (HIR ast.Expr → expr.Id). Les deux convergent vers les mêmes
//! 6 primitives, sans se marcher dessus.

const std = @import("std");
const kanren = @import("kanren");
const expr = @import("expr");

const Term = kanren.Term;
const Store = expr.Store;
const Id = expr.Id;

pub const BridgeError = error{OutOfMemory};

/// Convertit un `Term` Kanren en un `Id` Core dans `store`.
///
/// Encodage retenu :
///
/// | Term                          | Core                                       |
/// |-------------------------------|--------------------------------------------|
/// | `Term.Int(n)`                 | `lit(int(n))`                              |
/// | `Term.Atom(s)`                | `sym(s)`                                   |
/// | `Term.Var(v)`                 | `hole(v)`                                  |
/// | `Term.Nil`                    | `sym("Nil")`                               |
/// | `Term.Pair(atom(f), xs…)`     | `apply(sym(f), [termToId(x) for x in xs])` |
/// | `Term.Pair(h, t)` (impropre)  | `apply(sym("Cons"), [h', t'])`             |
///
/// La reconnaissance S-expression est déclenchée quand la tête de la
/// liste est un atome. Une queue non-Nil est traitée comme dernier
/// argument (liste impropre supportée).
pub fn termToId(store: *Store, term: Term) BridgeError!Id {
    switch (term) {
        .Int => |n| return store.int(n),
        .Atom => |s| return store.sym(s),
        .Var => |v| return store.hole(v),
        .Nil => return store.sym("Nil"),
        .Pair => |p| {
            switch (p.head) {
                .Atom => |func_name| {
                    var args = std.ArrayListUnmanaged(Id){};
                    defer args.deinit(store.allocator);

                    var cursor = p.tail;
                    while (true) {
                        switch (cursor) {
                            .Pair => |cp| {
                                try args.append(
                                    store.allocator,
                                    try termToId(store, cp.head),
                                );
                                cursor = cp.tail;
                            },
                            .Nil => break,
                            else => {
                                try args.append(
                                    store.allocator,
                                    try termToId(store, cursor),
                                );
                                break;
                            },
                        }
                    }

                    const func = try store.sym(func_name);
                    return store.apply(func, args.items);
                },
                else => {
                    const head = try termToId(store, p.head);
                    const tail = try termToId(store, p.tail);
                    const cons_sym = try store.sym("Cons");
                    return store.apply(cons_sym, &.{ head, tail });
                },
            }
        },
    }
}

// ─────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────

const testing = std.testing;

fn freeTerm(alloc: std.mem.Allocator, term: Term) void {
    switch (term) {
        .Pair => |p| {
            freeTerm(alloc, p.head);
            freeTerm(alloc, p.tail);
            alloc.destroy(@constCast(p));
        },
        else => {},
    }
}

test "termToId — atome et entier" {
    var store = Store.init(testing.allocator);
    defer store.deinit();

    const int_id = try termToId(&store, Term.sym("Int"));
    try testing.expect(store.get(int_id).tag == .sym);

    const n_id = try termToId(&store, .{ .Int = 42 });
    const n_node = store.get(n_id);
    try testing.expect(n_node.tag == .lit);
    try testing.expectEqual(@as(i64, 42), store.lits.items[n_node.aux].int);
}

test "termToId — Nil" {
    var store = Store.init(testing.allocator);
    defer store.deinit();

    const nil_id = try termToId(&store, .Nil);
    try testing.expect(store.get(nil_id).tag == .sym);
    try testing.expectEqualStrings(
        "Nil",
        store.interner.resolve(store.get(nil_id).payload),
    );
}

test "termToId — Var → hole" {
    var store = Store.init(testing.allocator);
    defer store.deinit();

    const v = Term.freshVar("x");
    const id = try termToId(&store, v);
    const node = store.get(id);
    try testing.expect(node.tag == .hole);
}

test "termToId — S-expression (arrow Int Int)" {
    var store = Store.init(testing.allocator);
    defer store.deinit();

    const alloc = testing.allocator;
    const arrow = Term.list(alloc, &.{
        Term.sym("arrow"),
        Term.sym("Int"),
        Term.sym("Int"),
    });
    defer freeTerm(alloc, arrow);

    const id = try termToId(&store, arrow);
    const node = store.get(id);
    try testing.expect(node.tag == .apply);

    // Vérifie le head = sym("arrow")
    const head_node = store.get(node.payload);
    try testing.expect(head_node.tag == .sym);
    try testing.expectEqualStrings(
        "arrow",
        store.interner.resolve(head_node.payload),
    );

    // span_a = [head, arg1, arg2]
    const args = node.span_a.slice(store.pool.items);
    try testing.expectEqual(@as(usize, 3), args.len);
    try testing.expectEqualStrings(
        "Int",
        store.interner.resolve(store.get(args[1]).payload),
    );
    try testing.expectEqualStrings(
        "Int",
        store.interner.resolve(store.get(args[2]).payload),
    );
}

test "termToId — liste impropre" {
    var store = Store.init(testing.allocator);
    defer store.deinit();

    const alloc = testing.allocator;
    // [a | b] = Pair(atom("a"), atom("b")) — pas de Nil terminal
    const improper = Term.pair(alloc, Term.sym("a"), Term.sym("b"));
    defer freeTerm(alloc, improper);

    const id = try termToId(&store, improper);
    const node = store.get(id);
    try testing.expect(node.tag == .apply);

    // Head = sym("a"), args = [sym("b")]
    const head_node = store.get(node.payload);
    try testing.expect(head_node.tag == .sym);
    try testing.expectEqualStrings(
        "a",
        store.interner.resolve(head_node.payload),
    );

    const args = node.span_a.slice(store.pool.items);
    try testing.expectEqual(@as(usize, 2), args.len);
    try testing.expectEqualStrings(
        "b",
        store.interner.resolve(store.get(args[1]).payload),
    );
}
