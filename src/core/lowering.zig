const std = @import("std");
const Ast = @import("matrix_lib");
const Bridge = @import("matrix_bridge").MatrixBridge;

pub const Lowering = struct {
    allocator: std.mem.Allocator,
    bridge: *Bridge,

    pub fn init(allocator: std.mem.Allocator, bridge: *Bridge) Lowering {
        return .{ .allocator = allocator, .bridge = bridge };
    }

    pub fn lowerSource(self: *Lowering, root: Ast.BobId) !Ast.BobId {
        return self.lowerNode(root);
    }

    pub fn lowerNode(self: *Lowering, node_id: Ast.BobId) !Ast.BobId {
        const store = self.bridge.store;
        const node = store.get(node_id);
        const pool = store.pool.items;

        switch (node.tag) {
            .source_file => {
                var out = std.ArrayListUnmanaged(Ast.BobId){};
                defer out.deinit(self.allocator);

                const children = node.span_a.slice(pool);
                for (children) |c| {
                    try out.append(self.allocator, try self.lowerNode(c));
                }

                return store.addNode(.{ .tag = .source_file, .payload = 0, .aux = 0, .span_a = try store.pushSpan(out.items), .span_b = Span.EMPTY });
            },

            .block => {
                var body = std.ArrayListUnmanaged(Ast.BobId){};
                defer body.deinit(self.allocator);

                const children = node.span_a.slice(pool);
                for (children) |c| {
                    try body.append(self.allocator, try self.lowerNode(c));
                }

                return store.push(.{
                    .tag = .block,
                    .span_a = try store.pushSpan(body.items),
                });
            },

            .call => {
                const args = node.span_a.slice(pool);

                const callee = args[0];
                var lowered_args = std.ArrayListUnmanaged(Ast.BobId){};
                defer lowered_args.deinit(self.allocator);

                for (args[1..]) |a| {
                    try lowered_args.append(self.allocator, try self.lowerNode(a));
                }

                return store.apply(try self.lowerNode(callee), lowered_args.items);
            },

            .binary => {
                const args = node.span_a.slice(pool);
                if (args.len != 2) return error.InvalidSyntax;

                return store.binop(
                    "op", // ou map node.payload → string op
                    try self.lowerNode(args[0]),
                    try self.lowerNode(args[1]),
                );
            },

            .identifier, .int, .float, .str, .bool_lit => {
                return node_id;
            },

            else => return error.UnsupportedNode,
        }
    }
};
