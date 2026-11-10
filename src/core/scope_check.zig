// scope_check.zig — vérification arité + litteral-comme-fonction
// Walk l'AST Core (expr.Store) : pour chaque .call dont le payload est un
// Sym qui résout à une fonction connue, vérifie l'arité.
// Aussi : .call dont le payload ressemble à un littéral (chiffre en tête)
// → signale ApplyNonFunction.

const std = @import("std");
const expr = @import("expr");
const engine_expr = @import("engine_expr");

pub const Kind = enum { arity, apply_non_function };

pub const Diagnostic = struct {
    kind: Kind,
    name: []const u8,
    expected: u32,
    found: u32,
};

pub const Diags = struct {
    items: std.ArrayListUnmanaged(Diagnostic) = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Diags {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Diags) void {
        self.items.deinit(self.allocator);
    }
    pub fn add(self: *Diags, d: Diagnostic) void {
        self.items.append(self.allocator, d) catch {};
    }
    pub fn count(self: *const Diags) usize {
        return self.items.items.len;
    }
    pub fn print(self: *const Diags, file_path: []const u8) void {
        for (self.items.items) |d| {
            switch (d.kind) {
                .arity => std.debug.print(
                    "{s}: arity mismatch '{s}': expected {d}, found {d}\n",
                    .{ file_path, d.name, d.expected, d.found },
                ),
                .apply_non_function => std.debug.print(
                    "{s}: applying non-function '{s}' (looks like a literal)\n",
                    .{ file_path, d.name },
                ),
            }
        }
    }
};

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

pub fn checkExpr(
    store: *expr.Store,
    engine: *engine_expr.Engine,
    id: expr.Id,
    diags: *Diags,
    depth: u32,
) void {
    if (depth > 500) return;
    if (id >= store.len()) return;
    const node = store.get(id);

    if (node.tag == .call) {
        // payload = Sym (function name or op)
        if (node.payload < store.interner.list.items.len) {
            const name = store.interner.resolve(node.payload);
            const args_len: u32 = @intCast(store.spanSliceConst(node.span_a).len);

            if (engine.fns.get(name)) |fn_def| {
                if (fn_def.num_clauses > 0) {
                    const expected: u32 = fn_def.clauses[0].num_patterns;
                    if (expected != args_len) {
                        diags.add(.{
                            .kind = .arity,
                            .name = name,
                            .expected = expected,
                            .found = args_len,
                        });
                    }
                }
            } else if (name.len > 0 and isDigit(name[0])) {
                // (0 unit) → "0" n'est pas une fonction
                diags.add(.{
                    .kind = .apply_non_function,
                    .name = name,
                    .expected = 0,
                    .found = args_len,
                });
            }
        }
    }

    for (store.spanSliceConst(node.span_a)) |c| checkExpr(store, engine, c, diags, depth + 1);
    for (store.spanSliceConst(node.span_b)) |c| checkExpr(store, engine, c, diags, depth + 1);
}


// ─────────────────────────────────────────────────────────────
// checkUnboundV2 — walker AST avec contexte lexical (Session 44)
//
// Remplace l'approche v0.1 (scan store naïf) qui produisait 20+
// faux positifs sur os/scheduler.hvn. Basé sur Bridge.roots
// (7430b15) qui ne contient que les définitions top-level réelles.
//
// Approche :
//  - Passe 1 : collecter tous les noms définis (bind.payload,
//    lambda.payload, letrec.payload) récursivement depuis roots.
//  - Passe 2 : walk chaque root, à chaque .sym rencontré en
//    position de RÉFÉRENCE (pas payload de .bind), vérifier qu'il
//    est dans le scope global (définitions + builtins) ou filtré.
//
// Filtres (repris de v0.1, validés empiriquement) :
//  - @magic, _hole, digit-en-tête
//  - nom qualifié (contient '.')
//  - suffix '_decl' (fallbacks tree-sitter)
//  - keywords import/export/as
//  - builtins statiques (opérateurs, keywords, types, primitives)
//
// Limitation : scope flat (pas de push/pop). Le shadowing est
// ignoré. Pour v0.2, acceptable (le livre n'utilise pas de
// shadowing critique).
// ─────────────────────────────────────────────────────────────
pub fn checkUnboundV2(
    allocator: std.mem.Allocator,
    store: *expr.Store,
    roots: []const expr.Id,
    file_path: []const u8,
) usize {
    var defined = std.StringHashMap(void).init(allocator);
    defer defined.deinit();

    const builtins = [_][]const u8{
        // Opérateurs binaires et unaires
        "+", "-", "*", "/", "%", "^",
        "<", ">", "<=", ">=", "==", "!=", "=", ">>>",
        "&&", "||", "!",
        // Keywords
        "if", "then", "else", "let", "in", "lambda",
        "data", "case", "match", "do", "import", "as", "test",
        "theorem", "prove", "by", "on",
        "comment", "true", "false", "unit", "Unit",
        // Builtins primitifs
        "print", "println", "debug",
        "len", "length", "size",
        "map", "filter", "reduce", "fold", "sum",
        "sort", "reverse", "head", "tail", "push", "pop",
        "read_file", "write_file",
        "spawn", "send", "receive", "perform", "handle",
        "assert", "assert_eq", "assert_ne", "assert_err",
        "assert_not", "assert_is",
        "sample", "observe", "infer", "steal",
        "cons", "nil",
        // Alias opérateurs
        "add", "sub", "mul", "div", "mod",
        "and", "or", "not", "eq", "neq", "lt", "gt", "le", "ge",
        "seq", "block", "tuple", "bind",
        // Primitives runtime
        "int_to_string", "string_length", "string_ptr", "peek_byte",
        "string_concat", "string_substring", "string_matches_at",
        "char_string",
        // Types standards
        "Int", "Str", "Bool", "Float", "Nat", "List", "Maybe", "Result",
        // Constructeurs standards
        "Ok", "Err", "Some", "None", "Cons", "Nil",
        "TLNil", "TLCons",
    };
    for (builtins) |b| defined.put(b, {}) catch {};

    // Passe 1 : collecter définitions
    for (roots) |rid| {
        collectDefsV2(store, rid, &defined);
    }

    // Passe 2 : walker références
    var errors: usize = 0;
    for (roots) |rid| {
        walkRefsV2(store, rid, &defined, &errors, file_path);
    }
    return errors;
}

fn isFilteredV2(name: []const u8) bool {
    if (name.len == 0) return true;
    if (name[0] == '@' or name[0] == '_') return true;
    if (isDigit(name[0])) return true;
    if (std.mem.indexOfScalar(u8, name, '.') != null) return true;
    if (std.mem.endsWith(u8, name, "_decl")) return true;
    return false;
}

fn collectDefsV2(store: *expr.Store, id: expr.Id, defined: *std.StringHashMap(void)) void {
    if (id >= store.len()) return;
    const node = store.get(id);
    switch (node.tag) {
        .bind, .lambda, .letrec => {
            if (node.payload < store.interner.list.items.len) {
                const name = store.interner.resolve(node.payload);
                if (name.len > 0) defined.put(name, {}) catch {};
            }
            for (store.spanSliceConst(node.span_a)) |c| collectDefsV2(store, c, defined);
            for (store.spanSliceConst(node.span_b)) |c| collectDefsV2(store, c, defined);
        },
        else => {
            for (store.spanSliceConst(node.span_a)) |c| collectDefsV2(store, c, defined);
            for (store.spanSliceConst(node.span_b)) |c| collectDefsV2(store, c, defined);
        },
    }
}

fn walkRefsV2(
    store: *expr.Store,
    id: expr.Id,
    defined: *std.StringHashMap(void),
    errors: *usize,
    file_path: []const u8,
) void {
    if (id >= store.len()) return;
    const node = store.get(id);
    switch (node.tag) {
        .sym => {
            if (node.payload >= store.interner.list.items.len) return;
            const name = store.interner.resolve(node.payload);
            if (name.len == 0) return;
            if (defined.contains(name)) return;
            if (isFilteredV2(name)) return;
            std.debug.print(
                "{s}: error: unbound variable '{s}'\n",
                .{ file_path, name },
            );
            errors.* += 1;
        },
        .bind, .lambda, .letrec => {
            // payload = définition ; ne pas le visiter comme référence
            for (store.spanSliceConst(node.span_a)) |c| walkRefsV2(store, c, defined, errors, file_path);
            for (store.spanSliceConst(node.span_b)) |c| walkRefsV2(store, c, defined, errors, file_path);
        },
        else => {
            for (store.spanSliceConst(node.span_a)) |c| walkRefsV2(store, c, defined, errors, file_path);
            for (store.spanSliceConst(node.span_b)) |c| walkRefsV2(store, c, defined, errors, file_path);
        },
    }
}
