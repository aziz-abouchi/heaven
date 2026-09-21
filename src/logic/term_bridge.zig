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

/// Convertit un `Id` Core issu de `store` en un `Term` Kanren.
pub fn idToTerm(allocator: std.mem.Allocator, store: *const Store, id: Id) BridgeError!Term {
    const node = store.get(id);
    return switch (node.tag) {
        .lit, .int => {
            const lit_val = store.lits.items[node.aux];
            return Term{ .Int = lit_val.int };
        },
        .sym, .identifier => {
            const str = store.interner.resolve(node.payload);
            if (std.mem.eql(u8, str, "Nil")) return .Nil;
            return Term.sym(str);
        },
        .hole => {
            const name = store.interner.resolve(node.payload);
            return Term.freshVar(name);
        },
        .apply, .call => {
            const head_node = store.get(node.payload);

            // Cas spécial : Cons(h, t) -> Pair(h, t)
            if (head_node.tag == .sym or head_node.tag == .identifier) {
                const func_name = store.interner.resolve(head_node.payload);
                if (std.mem.eql(u8, func_name, "Cons")) {
                    const args = node.span_a.slice(store.pool.items);
                    if (args.len == 2) {
                        const h = try idToTerm(allocator, store, args[0]);
                        const t = try idToTerm(allocator, store, args[1]);
                        return Term.pair(allocator, h, t);
                    }
                }
            }

            // Cas général : (head arg1 arg2 ...) -> Term.list
            const args = node.span_a.slice(store.pool.items);
            var term_list = std.ArrayListUnmanaged(Term){};
            defer term_list.deinit(allocator);

            const head_term = try idToTerm(allocator, store, node.payload);
            try term_list.append(allocator, head_term);

            for (args[1..]) |arg_id| {
                try term_list.append(allocator, try idToTerm(allocator, store, arg_id));
            }

            return Term.list(allocator, term_list.items);
        },
        else => Term.sym(@tagName(node.tag)),
    };
}

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

// ─────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────

const testing = std.testing;

test "idToTerm — atome, entier et aller-retour (roundtrip)" {
    var store = Store.init(testing.allocator);
    defer store.deinit();

    const alloc = testing.allocator;

    // 1. Entier
    const int_id = try store.int(42);
    const int_term = try idToTerm(alloc, &store, int_id);
    try testing.expectEqual(@as(i64, 42), int_term.Int);

    // 2. Symbole
    const sym_id = try store.sym("foo");
    const sym_term = try idToTerm(alloc, &store, sym_id);
    try testing.expectEqualStrings("foo", sym_term.Atom);

    // 3. Roundtrip S-expression
    const original = Term.list(alloc, &.{
        Term.sym("arrow"),
        Term.sym("Int"),
        Term.sym("Int"),
    });
    defer freeTerm(alloc, original);

    const converted_id = try termToId(&store, original);
    const roundtrip_term = try idToTerm(alloc, &store, converted_id);
    defer freeTerm(alloc, roundtrip_term);

    try testing.expect(roundtrip_term == .Pair);
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
