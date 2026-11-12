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
//!   conditional   → `(if c t e)`
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
            const v = store.litValue(id);
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
            const args = store.spanSliceConst(node.span_a);
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
        .conditional => |c| {
            try w.writeAll("(if ");
            try formatInto(store, c.cond, buf, allocator);
            try w.writeByte(' ');
            try formatInto(store, c.then_branch, buf, allocator);
            try w.writeByte(' ');
            try formatInto(store, c.else_branch, buf, allocator);
            try w.writeByte(')');
        },
        .letrec => |l| {
            try w.writeAll("(letrec ");
            try w.writeAll(store.interner.resolve(l.name));
            try w.writeByte(' ');
            try formatInto(store, l.val, buf, allocator);
            try w.writeByte(' ');
            try formatInto(store, l.body, buf, allocator);
            try w.writeByte(')');
        },
        else => return error.UnsupportedTag,
    }
}
