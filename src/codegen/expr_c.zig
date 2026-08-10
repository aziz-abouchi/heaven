const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;

const headers = @import("headers");

pub const Codegen = struct {
    store: *const Store,
    allocator: Allocator,
    out: std.ArrayListUnmanaged(u8) = .{},

    const Self = @This();
    const Error = Allocator.Error || error{UnsupportedTypeForCodegen};

    pub fn init(store: *const Store, allocator: Allocator) Codegen {
        return .{ .store = store, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        self.out.deinit(self.allocator);
    }

    pub fn generate(self: *Self, ids: []const Id) Error![]u8 {
        //try self.emit("#include <stdio.h>\n#include <stdint.h>\n#include <stdbool.h>\n\n");
        try headers.emitStandardHeaders(self);
        for (ids) |id| {
            try self.emitTopLevel(id);
            try self.emit("\n");
        }
        return self.out.toOwnedSlice(self.allocator);
    }

    fn emitTopLevel(self: *Self, id: Id) Error!void {
        const node = self.store.get(id);
        if (node.tag == .bind or node.tag == .let) {
            const name = self.store.interner.resolve(node.payload);
            const args = node.span_a.slice(self.store.pool.items);
            if (args.len > 0 and self.isLambda(args[0])) {
                try self.emitFunction(name, args[0]);
            } else if (args.len > 0) {
                try self.emit("int64_t ");
                try self.emit(name);
                try self.emit(" = ");
                try self.emitExpr(args[0]);
                try self.emit(";\n");
            }
        }
    }

    fn emitFunction(self: *Self, name: []const u8, lambda_id: Id) Error!void {
        try self.emit("int64_t ");
        try self.emit(name);
        try self.emit("(");
        
        var cur_id = lambda_id;
        var first = true;
        while (self.store.get(cur_id).tag == .lambda) {
            const lam_node = self.store.get(cur_id);
            if (!first) try self.emit(", ");
            try self.emit("int64_t ");
            try self.emit(self.store.interner.resolve(lam_node.payload));
            first = false;
            const children = lam_node.span_a.slice(self.store.pool.items);
            if (children.len == 0) break;
            cur_id = children[0];
        }
        
        try self.emit(") {\n    return ");
        try self.emitExpr(cur_id);
        try self.emit(";\n}\n");
    }

    fn isLambda(self: *Self, id: Id) bool {
        const node = self.store.get(id);
        // Gère le nouveau tag .lambda directement
        if (node.tag == .lambda) return true;
        // Legacy fallback
        if (node.tag != .apply) return false;
        const fn_node = self.store.get(node.payload);
        if (fn_node.tag != .sym) return false;
        return std.mem.eql(u8, self.store.interner.resolve(fn_node.payload), "\xCE\xBB");
    }

    fn emitExpr(self: *Self, id: Id) Error!void {
        const node = self.store.get(id);
        const pool = self.store.pool.items;
        switch (node.tag) {
            .sym => try self.emit(self.store.interner.resolve(node.payload)),
            .lit => {
                const l = self.store.lits.items[node.aux];
                switch (l) {
                    .int => |v| {
                        var tmp: [32]u8 = undefined;
                        try self.emit(std.fmt.bufPrint(&tmp, "{d}", .{v}) catch "0");
                    },
                    .float => |v| {
                        var tmp: [64]u8 = undefined;
                        try self.emit(std.fmt.bufPrint(&tmp, "{d:.6}", .{v}) catch "0.0");
                    },
                    .boolean => |v| try self.emit(if (v) "true" else "false"),
                    .str => |v| {
                        try self.emit("\"");
                        try self.emit(self.store.interner.resolve(v));
                        try self.emit("\"");
                    },
                    .unit => try self.emit("((void)0)"),
                    .runtime => try self.emit("/* runtime */ 0"),
                }
            },
            .apply => {
                const func_node = self.store.get(node.payload);
                const all_children = node.span_a.slice(pool);
                if (all_children.len == 0) return;
                const args = all_children[1..];

                if (func_node.tag == .sym) {
                    const name = self.store.interner.resolve(func_node.payload);
                    if (self.isInfix(name) and args.len == 2) {
                        try self.emit("(");
                        try self.emitExpr(args[0]);
                        try self.emit(" ");
                        try self.emit(name);
                        try self.emit(" ");
                        try self.emitExpr(args[1]);
                        try self.emit(")");
                        return;
                    }
                    if (std.mem.eql(u8, name, "if") and args.len >= 2) {
                        try self.emit("(");
                        try self.emitExpr(args[0]);
                        try self.emit(" ? ");
                        try self.emitExpr(args[1]);
                        try self.emit(" : ");
                        if (args.len > 2) try self.emitExpr(args[2]) else try self.emit("0");
                        try self.emit(")");
                        return;
                    }
                    if (std.mem.eql(u8, name, "\xCE\xA0") and args.len == 4) {
                        try self.emitAgg(args, "*", "1");
                        return;
                    }
                    if (std.mem.eql(u8, name, "\xCE\xA3") and args.len == 4) {
                        try self.emitAgg(args, "+", "0");
                        return;
                    }
                    try self.emit(name);
                } else {
                    try self.emitExpr(node.payload);
                }
                try self.emit("(");
                for (args, 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try self.emitExpr(arg);
                }
                try self.emit(")");
            },
            .hole => {
                var tmp: [32]u8 = undefined;
                try self.emit(std.fmt.bufPrint(&tmp, "_hole_{d}", .{node.payload}) catch "?");
            },
            .bind => try self.emit(self.store.interner.resolve(node.payload)),
            .relation => try self.emit("/* relation */"),
            else => return error.UnsupportedTypeForCodegen,
        }
    }

    fn emitAgg(self: *Self, args: []const Id, op: []const u8, identity: []const u8) Error!void {
        const var_node = self.store.get(args[0]);
        const var_name = if (var_node.tag == .sym) self.store.interner.resolve(var_node.payload) else "_i";
        try self.emit("({ int64_t _acc = ");
        try self.emit(identity);
        try self.emit("; for (int64_t ");
        try self.emit(var_name);
        try self.emit(" = ");
        try self.emitExpr(args[1]);
        try self.emit("; ");
        try self.emit(var_name);
        try self.emit(" <= ");
        try self.emitExpr(args[2]);
        try self.emit("; ");
        try self.emit(var_name);
        try self.emit("++) _acc ");
        try self.emit(op);
        try self.emit("= ");
        try self.emitExpr(args[3]);
        try self.emit("; _acc; })");
    }

    fn isInfix(_: *Self, name: []const u8) bool {
        const ops = [_][]const u8{ "+", "-", "*", "/", "%", "==", "!=", "<", ">", "<=", ">=" };
        for (ops) |op| if (std.mem.eql(u8, name, op)) return true;
        return false;
    }

    pub fn emit(self: *Self, s: []const u8) Error!void {
        try self.out.appendSlice(self.allocator, s);
    }
};

test "codegen C — bind" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    const val = try store.int(42);
    const def = try store.bind("x", val);
    var cg = Codegen.init(&store, allocator);
    defer cg.deinit();
    const result = try cg.generate(&.{def});
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "int64_t x = 42;") != null);
}

test "codegen C — function" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    const x = try store.sym("x");
    const body = try store.binop("+", x, x);
    const lam = try store.lambda(&.{"x"}, body);
    const def = try store.bind("double_val", lam);
    var cg = Codegen.init(&store, allocator);
    defer cg.deinit();
    const result = try cg.generate(&.{def});
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "double_val(") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "return (x + x)") != null);
}
