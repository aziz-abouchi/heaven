const std = @import("std");
const expr = @import("expr");

const Store = expr.Store;
const Id = expr.Id;

pub const CodegenError = error{
    UnsupportedCoreNode,
    WriteFailed,
    OutOfMemory,
};

pub const CodeGenerator = struct {
    store: *const Store,

    pub fn init(store: *const Store) CodeGenerator {
        return .{ .store = store };
    }

    pub fn emitC(self: *CodeGenerator, writer: anytype, id: Id) CodegenError!void {
        const node = self.store.get(id);
        switch (node.tag) {
            .lit, .int => {
                const lit_val = self.store.lits.items[node.aux];
                writer.print("{d}", .{lit_val.int}) catch return CodegenError.WriteFailed;
            },
            .sym, .identifier => {
                const name = self.store.interner.resolve(node.payload);
                writer.print("{s}", .{name}) catch return CodegenError.WriteFailed;
            },
            .apply, .call => {
                const func_node = self.store.get(node.payload);
                if (func_node.tag == .sym or func_node.tag == .identifier) {
                    const func_name = self.store.interner.resolve(func_node.payload);
                    writer.print("{s}(", .{func_name}) catch return CodegenError.WriteFailed;

                    const args = node.span_a.slice(self.store.pool.items);
                    for (args, 0..) |arg_id, i| {
                        if (i > 0) writer.writeAll(", ") catch return CodegenError.WriteFailed;
                        try self.emitC(writer, arg_id);
                    }
                    writer.writeAll(")") catch return CodegenError.WriteFailed;
                }
            },
            else => return CodegenError.UnsupportedCoreNode,
        }
    }
};

const testing = std.testing;

test "codegen — émission C depuis un Id Core" {
    const alloc = testing.allocator;
    var store = Store.init(alloc);
    defer store.deinit();

    const func_id = try store.sym("add");
    const arg1 = try store.int(10);
    const arg2 = try store.int(32);
    const app_id = try store.apply(func_id, &.{ arg1, arg2 });

    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();

    var emitter = CodeGenerator.init(&store);
    try emitter.emitC(buf.writer(), app_id);

    try testing.expectEqualStrings("add(10, 32)", buf.items);
}
