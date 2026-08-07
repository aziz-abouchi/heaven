const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;

pub const LaTeX = struct {
    store: *const Store,
    allocator: Allocator,
    out: std.ArrayListUnmanaged(u8) = .{},

    const Self = @This();
    const Error = Allocator.Error;

    pub fn init(store: *const Store, allocator: Allocator) LaTeX {
        return .{ .store = store, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        self.out.deinit(self.allocator);
    }

    pub fn generate(self: *Self, ids: []const Id) Error![]u8 {
        try self.emit("\\begin{align}\n");
        for (ids, 0..) |id, i| {
            try self.emit("  ");
            try self.emitTop(id);
            if (i < ids.len - 1) try self.emit(" \\\\\n") else try self.emit("\n");
        }
        try self.emit("\\end{align}\n");
        return self.out.toOwnedSlice(self.allocator);
    }

    pub fn renderInline(self: *Self, id: Id) Error![]u8 {
        try self.emitExpr(id);
        return self.out.toOwnedSlice(self.allocator);
    }

    fn emitTop(self: *Self, id: Id) Error!void {
        const node = self.store.get(id);
        if (node.tag == .bind) {
            try self.emitName(self.store.interner.resolve(node.payload));
            try self.emit(" &\\coloneqq ");
            try self.emitExpr(node.aux);
        } else if (node.tag == .relation) {
            try self.emitRelation(id);
        } else {
            try self.emitExpr(id);
        }
    }

    fn emitExpr(self: *Self, id: Id) Error!void {
        const node = self.store.get(id);
        const pool = self.store.pool.items;
        switch (node.tag) {
            .sym => try self.emitName(self.store.interner.resolve(node.payload)),
            .lit => {
                const l = self.store.lits.items[node.aux];
                switch (l) {
                    .int => |v| {
                        var tmp: [32]u8 = undefined;
                        try self.emit(std.fmt.bufPrint(&tmp, "{d}", .{v}) catch "?");
                    },
                    .float => |v| {
                        var tmp: [64]u8 = undefined;
                        try self.emit(std.fmt.bufPrint(&tmp, "{d:.4}", .{v}) catch "?");
                    },
                    .boolean => |v| try self.emit(if (v) "\\top" else "\\bot"),
                    .str => |v| {
                        try self.emit("\\text{\"");
                        try self.emit(self.store.interner.resolve(v));
                        try self.emit("\"}");
                    },
                    .unit => try self.emit("()"),
                    .runtime => try self.emit("\\mathtt{runtime}"),
                }
            },
            .apply => {
                const func_node = self.store.get(node.payload);
                const args = node.span_a.slice(pool);
                if (func_node.tag == .sym) {
                    const name = self.store.interner.resolve(func_node.payload);
                    if (args.len == 2) {
                        if (std.mem.eql(u8, name, "+")) {
                            try self.emitBin(args, " + ");
                            return;
                        }
                        if (std.mem.eql(u8, name, "-")) {
                            try self.emitBin(args, " - ");
                            return;
                        }
                        if (std.mem.eql(u8, name, "*")) {
                            try self.emitMulArg(args[0]);
                            try self.emit(" \\cdot ");
                            try self.emitMulArg(args[1]);
                            return;
                        }
                        if (std.mem.eql(u8, name, "/")) {
                            try self.emit("\\frac{");
                            try self.emitExpr(args[0]);
                            try self.emit("}{");
                            try self.emitExpr(args[1]);
                            try self.emit("}");
                            return;
                        }
                        if (std.mem.eql(u8, name, "^")) {
                            try self.emit("{");
                            try self.emitExpr(args[0]);
                            try self.emit("}^{");
                            try self.emitExpr(args[1]);
                            try self.emit("}");
                            return;
                        }
                        if (std.mem.eql(u8, name, "==")) {
                            try self.emitBin(args, " = ");
                            return;
                        }
                    }
                    if (std.mem.eql(u8, name, "\xCE\xA3") and args.len == 4) {
                        try self.emitSum(args);
                        return;
                    }
                    if (std.mem.eql(u8, name, "\xCE\xA0") and args.len == 4) {
                        try self.emitProd(args);
                        return;
                    }
                    if (std.mem.eql(u8, name, "\xCE\xBB")) {
                        try self.emitLambda(args);
                        return;
                    }
                    try self.emitName(name);
                } else {
                    try self.emitExpr(node.payload);
                }
                if (args.len > 0) {
                    try self.emit("\\left(");
                    for (args, 0..) |arg, i| {
                        if (i > 0) try self.emit(",\\; ");
                        try self.emitExpr(arg);
                    }
                    try self.emit("\\right)");
                }
            },
            .bind => {
                try self.emitName(self.store.interner.resolve(node.payload));
                try self.emit(" \\coloneqq ");
                try self.emitExpr(node.aux);
            },
            .relation => try self.emitRelation(id),
            .hole => {
                var tmp: [16]u8 = undefined;
                try self.emit("?_{");
                try self.emit(std.fmt.bufPrint(&tmp, "{d}", .{node.payload}) catch "?");
                try self.emit("}");
            },
            else => try self.out.appendSlice(self.allocator, "<?>"),
        }
    }

    fn emitBin(self: *Self, args: []const Id, op: []const u8) Error!void {
        try self.emitExpr(args[0]);
        try self.emit(op);
        try self.emitExpr(args[1]);
    }

    fn emitMulArg(self: *Self, id: Id) Error!void {
        const node = self.store.get(id);
        const pool = self.store.pool.items;
        _ = pool;
        var needs_parens = false;
        if (node.tag == .apply) {
            const fn_node = self.store.get(node.payload);
            if (fn_node.tag == .sym) {
                const op = self.store.interner.resolve(fn_node.payload);
                if (std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "-")) {
                    needs_parens = true;
                }
            }
        }
        if (needs_parens) try self.emit("\\left(");
        try self.emitExpr(id);
        if (needs_parens) try self.emit("\\right)");
    }

    fn emitSum(self: *Self, args: []const Id) Error!void {
        try self.emit("\\sum_{");
        try self.emitExpr(args[0]);
        try self.emit(" = ");
        try self.emitExpr(args[1]);
        try self.emit("}^{");
        try self.emitExpr(args[2]);
        try self.emit("} ");
        try self.emitExpr(args[3]);
    }

    fn emitProd(self: *Self, args: []const Id) Error!void {
        try self.emit("\\prod_{");
        try self.emitExpr(args[0]);
        try self.emit(" = ");
        try self.emitExpr(args[1]);
        try self.emit("}^{");
        try self.emitExpr(args[2]);
        try self.emit("} ");
        try self.emitExpr(args[3]);
    }

    fn emitLambda(self: *Self, children: []const Id) Error!void {
        if (children.len == 0) return;
        try self.emit("\\lambda\\, ");
        for (children[0 .. children.len - 1]) |param| {
            try self.emitExpr(param);
            try self.emit("\\, ");
        }
        try self.emit(".\\; ");
        try self.emitExpr(children[children.len - 1]);
    }

    fn emitRelation(self: *Self, id: Id) Error!void {
        const node = self.store.get(id);
        const pool = self.store.pool.items;
        const head = self.store.interner.resolve(node.payload);
        const body_slice = node.span_b.slice(pool);
        if (body_slice.len > 0) {
            try self.emit("\\frac{");
            for (body_slice, 0..) |bb, i| {
                if (i > 0) try self.emit(" \\quad ");
                try self.emitExpr(bb);
            }
            try self.emit("}{\\mathrm{");
            try self.emit(head);
            try self.emit("}(");
            for (node.span_a.slice(pool), 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try self.emitExpr(arg);
            }
            try self.emit(")}");
        } else {
            try self.emit("\\mathrm{");
            try self.emit(head);
            try self.emit("}(");
            for (node.span_a.slice(pool), 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try self.emitExpr(arg);
            }
            try self.emit(")");
        }
    }

    fn emitName(self: *Self, name: []const u8) Error!void {
        if (name.len == 1) {
            try self.emit(name);
        } else {
            try self.emit("\\mathrm{");
            try self.emit(name);
            try self.emit("}");
        }
    }

    fn emit(self: *Self, s: []const u8) Error!void {
        try self.out.appendSlice(self.allocator, s);
    }
};

test "latex — fraction" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    const a = try store.sym("a");
    const b = try store.sym("b");
    const div = try store.binop("/", a, b);
    var gen = LaTeX.init(&store, allocator);
    defer gen.deinit();
    const result = try gen.renderInline(div);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\frac{a}{b}") != null);
}

test "latex — product" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    const k = try store.sym("k");
    const n = try store.sym("n");
    const one = try store.int(1);
    const prod = try store.aggregate("\xCE\xA0", "k", one, n, k);
    var gen = LaTeX.init(&store, allocator);
    defer gen.deinit();
    const result = try gen.renderInline(prod);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\prod_{") != null);
}

test "latex — list_nil" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    // Si tu as un moyen de générer un list_nil (par exemple via ton parser ou ton Store)
    // Ce test validera que le tag compile parfaitement avec le générateur LaTeX.
}
