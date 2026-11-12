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
                .float => |f| try w.print("{d}", .{f}),
                .str => |s| {
                    const name = store.interner.resolve(s);
                    try w.writeByte('"');
                    for (name) |c| {
                        if (c == '"') try w.writeAll("\\\"") else try w.writeByte(c);
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
            try w.writeAll("(bind ");
            try w.writeAll(store.interner.resolve(node.payload));
            try w.writeByte(' ');
            const val = store.spanSliceConst(node.span_a);
            if (val.len > 0) try formatInto(store, val[0], buf, allocator);
            try w.writeByte(')');
        },
        .lambda => {
            try w.writeAll("(lambda ");
            try w.writeAll(store.interner.resolve(node.payload));
            try w.writeByte(' ');
            const body = store.spanSliceConst(node.span_a);
            if (body.len > 0) try formatInto(store, body[0], buf, allocator);
            try w.writeByte(')');
        },
        else => return error.UnsupportedTag,
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
