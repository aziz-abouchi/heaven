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
