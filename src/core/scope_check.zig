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

// ─────────────────────────────────────────────────────────────
// checkUnbound — détection des variables non définies (v0.1)
//
// Walk exhaustif du store : collecte les noms définis (bind, lambda,
// function, letrec), puis vérifie chaque .call/.apply dont le payload
// est un Sym.
//
// Filtres (pour éviter les faux positifs) :
//   - @magic (préfixe @)
//   - _hole (préfixe _)
//   - littéral numérique (digit en tête)
//   - nom qualifié (contient '.') — résolu côté module
//   - builtins (liste statique dupliquée de scope.addBuiltins)
//
// Limitation v0.1 : un paramètre local qui n'apparaît PAS comme
// .lambda/.function/.bind dans le store sera signalé à tort.
// Testé sur f n = n + 1 (doit passer). Si régression, ne pas commit.
//
// Voir docs/spec/_check_v2_plan.md.
pub fn checkUnbound(
    allocator: std.mem.Allocator,
    store: *expr.Store,
    file_path: []const u8,
) usize {
    // Pré-remplir avec les builtins (dupliqué de scope.addBuiltins).
    var defined = std.StringHashMap(void).init(allocator);
    defer defined.deinit();

    const builtins = [_][]const u8{
        "print", "println", "debug",
        "len", "length", "size",
        "map", "filter", "reduce", "fold", "sum",
        "sort", "reverse", "head", "tail", "push", "pop",
        "read_file", "write_file",
        "spawn", "send", "receive", "perform", "handle",
        "assert", "assert_eq", "assert_ne", "assert_err",
        "assert_not", "assert_is",
        "sample", "observe", "infer", "steal",
        "cons", "nil", "true", "false", "unit",
        "if", "let", "lambda", "bind", "seq", "block", "tuple",
        "add", "sub", "mul", "div", "mod",
        "and", "or", "not", "eq", "neq", "lt", "gt", "le", "ge",
        "int_to_string", "string_length", "string_ptr", "peek_byte",
        "string_concat", "string_substring", "string_matches_at",
        "char_string",
    };
    for (builtins) |b| defined.put(b, {}) catch {};

    // Passe 1 : collecter les noms définis.
    var id: expr.Id = 0;
    while (id < store.len()) : (id += 1) {
        const node = store.get(id);
        switch (node.tag) {
            .bind, .lambda, .function, .letrec => {
                if (node.payload < store.interner.list.items.len) {
                    const name = store.interner.resolve(node.payload);
                    if (name.len > 0) defined.put(name, {}) catch {};
                }
            },
            else => {},
        }
    }

    // Passe 2 : vérifier les .call / .apply.
    var errors: usize = 0;
    id = 0;
    while (id < store.len()) : (id += 1) {
        const node = store.get(id);
        if (node.tag != .call and node.tag != .apply) continue;
        if (node.payload >= store.interner.list.items.len) continue;
        const name = store.interner.resolve(node.payload);
        if (name.len == 0) continue;
        // Filtres
        if (name[0] == '@' or name[0] == '_') continue;
        if (isDigit(name[0])) continue;
        if (std.mem.indexOfScalar(u8, name, '.') != null) continue;
        if (defined.contains(name)) continue;
        // Littéral numérique direct
        if (std.fmt.parseInt(i64, name, 10)) |_| continue else |_| {}
        // Unbound
        platform.debug.print(
            "{s}: error: unbound variable '{s}'\n",
            .{ file_path, name },
        );
        errors += 1;
    }

    return errors;
}
}
