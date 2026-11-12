//! sexpr_dump.zig — formatteur S-expression canonique pour le Core.
//!
//! Contrairement à `toStringInfix` (qui produit un format mixte
//! `:=`/`(lambda …)`/atoms), ce formateur émet un S-expr **pur**,
//! relisible par le parseur natif. Utilisé par B0.1 (dump Core
//! de référence pour B3).
//!
//! Format :
//!   lit(int)      → `42`, `-7`
//!   lit(float)    → `3.14`
//!   lit(str)      → `"…"` (échappement minimal)
//!   lit(bool)     → `true` / `false`
//!   lit(unit)     → `unit`
//!   sym           → `<name>` (sans quotes, sans ID)
//!   apply(f, a…)  → `(f a1 a2 …)`
//!   bind(n, v)    → `(bind n v)`
//!   lambda(p, b)  → `(lambda p b)`
//!   conditional   → `(if c t e)` — encodé comme apply(sym("if"), [c,t,e]),
//!                   donc couvert par le case .apply, pas de Tag dédié.
//!   letrec        → `(letrec n v b)`
//!
//! Tag inconnu → `error.UnsupportedTag` (jamais d'omission
//! silencieuse, exigence 2 du contrat B0).

const std = @import("std");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;

pub const FormatError = error{
    UnsupportedTag,
    OutOfMemory,
};

/// Formate un Id en S-expression canonique.
/// L'allocateur reçoit la string finale ; le caller la libère.
pub fn formatId(
    store: *const Store,
    id: Id,
    allocator: std.mem.Allocator,
) FormatError![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);
    try formatInto(store, id, &buf, allocator);
    return try buf.toOwnedSlice(allocator);
}

fn formatInto(
    store: *const Store,
    id: Id,
    buf: *std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,
) FormatError!void {
    if (id >= store.len()) return error.UnsupportedTag;
    const node = store.get(id);
    const w = buf.writer(allocator);
    switch (node.tag) {
        .lit => {
            const v = store.getLit(node.aux);
            switch (v) {
                .int => |n| try w.print("{d}", .{n}),
                .float => |f| {
                    if (!std.math.isFinite(f)) return error.UnsupportedTag;
                    var tmp: [64]u8 = undefined;
                    const s = std.fmt.bufPrint(&tmp, "{d}", .{f}) catch unreachable; // 64o >> max f64 (~24o)
                    try w.writeAll(s);
                    if (std.mem.indexOfAny(u8, s, ".eE") == null) try w.writeAll(".0");
                },
                .str => |s| {
                    const name = store.interner.resolve(s);
                    try w.writeByte('"');
                    for (name) |c| {
                        switch (c) {
                            '"' => try w.writeAll("\\\""),
                            '\\' => try w.writeAll("\\\\"),
                            '\n' => try w.writeAll("\\n"),
                            '\r' => try w.writeAll("\\r"),
                            '\t' => try w.writeAll("\\t"),
                            0...8, 11, 12, 14...0x1f, 0x7f => try w.print("\\x{x:0>2}", .{c}),
                            else => try w.writeByte(c),
                        }
                    }
                    try w.writeByte('"');
                },
                .boolean => |b| try w.writeAll(if (b) "true" else "false"),
                .unit => try w.writeAll("unit"),
                else => return error.UnsupportedTag,
            }
        },
        .sym => {
            try w.writeAll(store.interner.resolve(node.payload));
        },
        .apply => {
            const args = store.applyArgs(node);
            try w.writeByte('(');
            try formatInto(store, node.payload, buf, allocator);
            for (args) |a| {
                try w.writeByte(' ');
                try formatInto(store, a, buf, allocator);
            }
            try w.writeByte(')');
        },
        .bind => {
            if (node.aux != 0) return error.UnsupportedTag;
            const span = store.spanSliceConst(node.span_a);
            if (span.len != 2) return error.UnsupportedTag;
            try w.writeAll("(let ");
            try w.writeAll(store.interner.resolve(node.payload));
            try w.writeByte(' ');
            try formatInto(store, span[0], buf, allocator);
            try w.writeByte(' ');
            try formatInto(store, span[1], buf, allocator);
            try w.writeByte(')');
        },
        .lambda => {
            if (node.payload == 0) return error.UnsupportedTag;
            if (node.aux != 0) return error.UnsupportedTag;
            const body = store.spanSliceConst(node.span_a);
            if (body.len != 1) return error.UnsupportedTag;
            try w.writeAll("(lambda ");
            try w.writeAll(store.interner.resolve(node.payload));
            try w.writeByte(' ');
            try formatInto(store, body[0], buf, allocator);
            try w.writeByte(')');
        },
        .relation => {
            if (node.aux != 0) return error.UnsupportedTag;
            try w.writeAll("(relation ");
            try w.writeAll(store.interner.resolve(node.payload));
            try w.writeAll(" (");
            const lhs = store.spanSliceConst(node.span_a);
            for (lhs, 0..) |a, k| {
                if (k > 0) try w.writeByte(' ');
                try formatInto(store, a, buf, allocator);
            }
            try w.writeAll(") (");
            const rhs = store.spanSliceConst(node.span_b);
            for (rhs, 0..) |r, k| {
                if (k > 0) try w.writeByte(' ');
                try formatInto(store, r, buf, allocator);
            }
            try w.writeAll("))");
        },
        // Exhaustif : tout ajout à expr.Tag casse la compilation ici.
        .hole, .evar, .true, .false, .int, .float, .string, .var_tag, .let, .letrec,
        .fun, .eq, .add, .sub, .mul, .div, .mod, .and_tag, .or_tag, .not, .cons,
        .head, .tail, .tuple, .block, .seq, .unit_lit, .vector, .vector_lit, .sum,
        .aggregate, .source_file, .block_legacy, .call, .binary, .unary, .identifier,
        .str_legacy, .bool_lit, .pi_tag, .universe_tag, .ctor, .data, .forall,
        .exists, .arrow, .sigma, .pair, .thunk => return error.UnsupportedTag,
    }
}

test "compile-check" {
    // Force la compilation du fichier par `zig build test`.
    // refAllDecls analyse le corps de formatId ; `_ = formatId;`
    // ne vérifiait que sa signature (lazy analysis).
    std.testing.refAllDecls(@This());
}


test "smoke — int / sym / apply / if" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    // int(42) -> "42"
    {
        const id = try store.int(42);
        const s = try formatId(&store, id, allocator);
        defer allocator.free(s);
        try std.testing.expectEqualStrings("42", s);
    }
    // sym("f") -> "f" (sans quotes, sans ID — cf. docstring)
    {
        const id = try store.sym("f");
        const s = try formatId(&store, id, allocator);
        defer allocator.free(s);
        try std.testing.expectEqualStrings("f", s);
    }
    // (f 1 2) — via apply
    {
        const f = try store.sym("f");
        const a = try store.int(1);
        const b = try store.int(2);
        const id = try store.apply(f, &.{ a, b });
        const s = try formatId(&store, id, allocator);
        defer allocator.free(s);
        try std.testing.expectEqualStrings("(f 1 2)", s);
    }
}


test "float — 3.0 et 3 sont distinguables (injectivité)" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const f = try store.float(3.0);
    const i = try store.int(3);
    const sf = try formatId(&store, f, allocator);
    defer allocator.free(sf);
    const si = try formatId(&store, i, allocator);
    defer allocator.free(si);
    try std.testing.expectEqualStrings("3.0", sf);
    try std.testing.expectEqualStrings("3", si);
    try std.testing.expect(!std.mem.eql(u8, sf, si));
}

test "str — échappements table-driven" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const cases = [_]struct { raw: []const u8, expected: []const u8 }{
        .{ .raw = "a",    .expected = "\"a\"" },
        .{ .raw = "a\"b", .expected = "\"a\\\"b\"" },
        .{ .raw = "a\\b", .expected = "\"a\\\\b\"" },
        .{ .raw = "a\nb", .expected = "\"a\\nb\"" },
        .{ .raw = "a\tb", .expected = "\"a\\tb\"" },
    };
    for (cases) |c| {
        const sym = try store.interner.intern(c.raw);
        const id = try store.lit(.{ .str = sym });
        const s = try formatId(&store, id, allocator);
        defer allocator.free(s);
        try std.testing.expectEqualStrings(c.expected, s);
    }
}
test "bind — corps vide doit échouer (pas d'omission silencieuse)" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const name = try store.interner.intern("y");
    const id = try store.addNode(.{
        .tag = .bind, .payload = name, .aux = 0,
        .span_a = expr.Span.EMPTY, .span_b = expr.Span.EMPTY,
    });
    try std.testing.expectError(error.UnsupportedTag, formatId(&store, id, allocator));
}


test "bind — (let n val body) via bindSymWithBody" {
    // .bind est une primitive Core (span_a = [val, body], aux = 0).
    // .let (produit par letIn) est une extension frontend, rejetée
    // par le dump (voir le switch exhaustif plus haut).
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const val = try store.int(5);
    const body = try store.sym("y");
    const name = try store.interner.intern("y");
    const id = try store.bindSymWithBody(name, val, body);
    const s = try formatId(&store, id, allocator);
    defer allocator.free(s);
    try std.testing.expectEqualStrings("(let y 5 y)", s);
}

test "let — extension frontend rejetée (UnsupportedTag)" {
    // letIn produit .tag = .let, non-Core. Le dump doit refuser,
    // pas formater silencieusement.
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const val = try store.int(5);
    const body = try store.sym("y");
    const id = try store.letIn("y", val, body);
    try std.testing.expectError(error.UnsupportedTag, formatId(&store, id, allocator));
}

test "lambda — sans paramètre (payload 0) → UnsupportedTag" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const body = try store.int(1);
    const id = try store.lambda(&[_][]const u8{}, body);
    try std.testing.expectError(error.UnsupportedTag, formatId(&store, id, allocator));
}

test "relation — (relation Eq (1) (2))" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const a = try store.int(1);
    const b = try store.int(2);
    const id = try store.relation("Eq", &.{a}, &.{b});
    const s = try formatId(&store, id, allocator);
    defer allocator.free(s);
    try std.testing.expectEqualStrings("(relation Eq (1) (2))", s);
}

test "relation — aux != 0 → UnsupportedTag" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const head = try store.interner.intern("Eq");
    const id = try store.addNode(.{
        .tag = .relation,
        .payload = head,
        .aux = 1,
        .span_a = expr.Span.EMPTY,
        .span_b = expr.Span.EMPTY,
    });
    try std.testing.expectError(error.UnsupportedTag, formatId(&store, id, allocator));
}
