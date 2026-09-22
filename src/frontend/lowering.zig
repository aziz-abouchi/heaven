const std = @import("std");
const expr = @import("expr");

const Store = expr.Store;
const Id = expr.Id;

pub const LoweringError = error{
    InvalidASTNode,
    UnboundSymbol,
    OutOfMemory,
};

pub const ASTNode = union(enum) {
    Int: i64,
    Symbol: []const u8,
    Call: struct {
        func: []const u8,
        args: []const ASTNode,
    },
};

/// Convertit un nœud AST Frontend en un Id Core interné dans le Store.
pub fn lowerAST(allocator: std.mem.Allocator, store: *Store, ast: ASTNode) LoweringError!Id {
    switch (ast) {
        .Int => |val| {
            return store.int(val) catch LoweringError.OutOfMemory;
        },
        .Symbol => |sym_name| {
            return store.sym(sym_name) catch LoweringError.OutOfMemory;
        },
        .Call => |call| {
            const func_id = store.sym(call.func) catch return LoweringError.OutOfMemory;
            var arg_ids: std.ArrayList(Id) = .empty;
            defer arg_ids.deinit(allocator);

            for (call.args) |arg| {
                const arg_id = try lowerAST(allocator, store, arg);
                try arg_ids.append(allocator, arg_id);
            }

            return store.apply(func_id, arg_ids.items) catch LoweringError.OutOfMemory;
        },
    }
}

// ─────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────

const testing = std.testing;

test "lowering — conversion AST vers Store Core" {
    const alloc = testing.allocator;
    var store = Store.init(alloc);
    defer store.deinit();

    const ast = ASTNode{
        .Call = .{
            .func = "add",
            .args = &.{
                .{ .Int = 10 },
                .{ .Int = 20 },
            },
        },
    };

    const id = try lowerAST(alloc, &store, ast);
    try testing.expect(store.isCore(id));
}
