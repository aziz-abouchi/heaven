const std = @import("std");
const expr_mod = @import("expr");
const Store = expr_mod.Store;
const Id = expr_mod.Id;

pub fn exprToJs(store: *const Store, id: Id, allocator: std.mem.Allocator) ![]u8 {
    const node = store.get(id);
    switch (node.tag) {
        .lit => {
            const lit = store.lits.items[node.aux];
            switch (lit) {
                .int => |v| return std.fmt.allocPrint(allocator, "{d}", .{v}),
                .boolean => |b| return std.fmt.allocPrint(allocator, "{}", .{b}),
                else => return std.fmt.allocPrint(allocator, "\"{s}\"", .{@tagName(lit)}),
            }
        },
        .sym => {
            const name = store.interner.resolve(node.payload);
            return allocator.dupe(u8, name);
        },
        .apply => {
            const func_node = store.get(node.payload);
            const op_name = if (func_node.tag == .sym) store.interner.resolve(func_node.payload) else "?";
            const args = node.span_a.slice(store.pool.items);

            if (std.mem.eql(u8, op_name, "+") or std.mem.eql(u8, op_name, "-") or std.mem.eql(u8, op_name, "*") or std.mem.eql(u8, op_name, "/") or std.mem.eql(u8, op_name, "<") or std.mem.eql(u8, op_name, "=") or std.mem.eql(u8, op_name, "^")) {
                if (args.len == 2) {
                    const lhs = try exprToJs(store, args[0], allocator);
                    defer allocator.free(lhs);
                    const rhs = try exprToJs(store, args[1], allocator);
                    defer allocator.free(rhs);
                    const jsop: []const u8 = if (std.mem.eql(u8, op_name, "=")) "===" else if (std.mem.eql(u8, op_name, "^")) "**" else op_name;
                    return std.fmt.allocPrint(allocator, "({s} {s} {s})", .{ lhs, jsop, rhs });
                }
            }
            if (std.mem.eql(u8, op_name, "if") and args.len == 3) {
                const cond = try exprToJs(store, args[0], allocator);
                defer allocator.free(cond);
                const then_ = try exprToJs(store, args[1], allocator);
                defer allocator.free(then_);
                const else_ = try exprToJs(store, args[2], allocator);
                defer allocator.free(else_);
                return std.fmt.allocPrint(allocator, "({s} ? {s} : {s})", .{ cond, then_, else_ });
            }
            // Cas général : appel de fonction
            var buf = std.ArrayListUnmanaged(u8){};
            const w = buf.writer(allocator);
            try w.print("{s}(", .{op_name});
            for (args, 0..) |arg, i| {
                if (i > 0) try w.writeAll(", ");
                const arg_str = try exprToJs(store, arg, allocator);
                defer allocator.free(arg_str);
                try w.writeAll(arg_str);
            }
            try w.writeAll(")");
            return buf.toOwnedSlice(allocator);
        },
        .bind => {
            // let x = val
            const name = store.interner.resolve(node.payload);
            const val_str = try exprToJs(store, node.aux, allocator);
            defer allocator.free(val_str);
            return std.fmt.allocPrint(allocator, "const {s} = {s}", .{ name, val_str });
        },
        else => return allocator.dupe(u8, "/* unsupported */"),
    }
}
