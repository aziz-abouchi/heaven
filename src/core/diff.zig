//! AST diff — montre la transformation sucre -> 6 primitives.
//! Utilise par le REPL `diff lower <expr>` et les tests.
//! Compare deux arbres Id en lisant le Store, affiche avec +/-.

const std = @import("std");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;

pub const AstDiff = struct {
    store: *const Store,
    use_color: bool = true,

    pub fn init(store: *const Store) AstDiff {
        return .{ .store = store, .use_color = true };
    }

    pub fn print(self: *const AstDiff, writer: anytype, a: Id, b: Id) anyerror!void {
        try self.diffNodes(writer, a, b, 0);
    }

    fn writeIndent(writer: anytype, depth: usize) anyerror!void {
        var i: usize = 0;
        while (i < depth) : (i += 1) try writer.writeAll("  ");
    }

    fn diffNodes(self: *const AstDiff, writer: anytype, a: Id, b: Id, depth: usize) anyerror!void {
        if (a == b) {
            try self.printTree(writer, a, depth, " ");
            return;
        }
        const na = self.store.get(a);
        const nb = self.store.get(b);
        if (na.tag == nb.tag) {
            try writeIndent(writer, depth);
            try writer.print(".{s}\n", .{@tagName(na.tag)});
            try self.diffChildren(writer, a, b, depth + 1);
        } else {
            try self.printTree(writer, a, depth, "-");
            try self.printTree(writer, b, depth, "+");
        }
    }

    fn diffChildren(self: *const AstDiff, writer: anytype, a: Id, b: Id, depth: usize) anyerror!void {
        const na = self.store.get(a);
        const nb = self.store.get(b);
        const pool = self.store.pool.items;
        switch (na.tag) {
            .apply, .lambda, .bind => {
                const aa = na.span_a.slice(pool);
                const ab = nb.span_a.slice(pool);
                const max = @max(aa.len, ab.len);
                for (0..max) |i| {
                    if (i < aa.len and i < ab.len) {
                        try self.diffNodes(writer, aa[i], ab[i], depth);
                    } else if (i < aa.len) {
                        try self.printTree(writer, aa[i], depth, "-");
                    } else {
                        try self.printTree(writer, ab[i], depth, "+");
                    }
                }
            },
            .relation => {
                const la = na.span_a.slice(pool);
                const lb = nb.span_a.slice(pool);
                const lmax = @max(la.len, lb.len);
                for (0..lmax) |i| {
                    if (i < la.len and i < lb.len) {
                        try self.diffNodes(writer, la[i], lb[i], depth);
                    } else if (i < la.len) {
                        try self.printTree(writer, la[i], depth, "-");
                    } else {
                        try self.printTree(writer, lb[i], depth, "+");
                    }
                }
                const ra = na.span_b.slice(pool);
                const rb = nb.span_b.slice(pool);
                const rmax = @max(ra.len, rb.len);
                for (0..rmax) |i| {
                    if (i < ra.len and i < rb.len) {
                        try self.diffNodes(writer, ra[i], rb[i], depth);
                    } else if (i < ra.len) {
                        try self.printTree(writer, ra[i], depth, "-");
                    } else {
                        try self.printTree(writer, rb[i], depth, "+");
                    }
                }
            },
            else => {},
        }
    }

    fn printTree(self: *const AstDiff, writer: anytype, id: Id, depth: usize, prefix: []const u8) anyerror!void {
        const node = self.store.get(id);
        try writeIndent(writer, depth);
        const name = @tagName(node.tag);
        if (self.use_color) {
            const color: []const u8 = switch (prefix[0]) {
                '+' => "\x1b[32m",
                '-' => "\x1b[31m",
                else => "",
            };
            const reset: []const u8 = if (color.len > 0) "\x1b[0m" else "";
            try writer.print("{s}{s} .{s}{s}", .{ color, prefix, name, reset });
        } else {
            try writer.print("{s} .{s}", .{ prefix, name });
        }
        switch (node.tag) {
            .sym => try writer.print(" ({s})", .{self.store.interner.resolve(node.payload)}),
            .lit => {
                const l = self.store.lits.items[node.aux];
                switch (l) {
                    .int => |v| try writer.print(" ({d})", .{v}),
                    .float => |v| try writer.print(" ({d})", .{v}),
                    .boolean => |v| try writer.print(" ({})", .{v}),
                    else => {},
                }
            },
            else => {},
        }
        try writer.writeByte('\n');

        const pool = self.store.pool.items;
        switch (node.tag) {
            .apply, .lambda, .bind => {
                for (node.span_a.slice(pool)) |c| try self.printTree(writer, c, depth + 1, prefix);
            },
            .relation => {
                for (node.span_a.slice(pool)) |c| try self.printTree(writer, c, depth + 1, prefix);
                for (node.span_b.slice(pool)) |c| try self.printTree(writer, c, depth + 1, prefix);
            },
            else => {},
        }
    }
};

// ─── Tests ───

const testing = std.testing;

test "diff — deux arbres identiques ne produisent que du inchange" {
    const allocator = testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const x = try store.sym("x");

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);

    var d = AstDiff.init(&store);
    d.use_color = false;
    try d.print(buf.writer(allocator), x, x);

    try testing.expect(buf.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buf.items, "-") == null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "+") == null);
}

test "diff — deux arbres differents produisent du - et du +" {
    const allocator = testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const x = try store.sym("x");
    const i = try store.int(42);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);

    var d = AstDiff.init(&store);
    d.use_color = false;
    try d.print(buf.writer(allocator), x, i);

    try testing.expect(std.mem.indexOf(u8, buf.items, "- .sym") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "+ .lit") != null);
}

test "diff — apply non identique : marque les enfants" {
    const allocator = testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const f = try store.sym("f");
    const a1 = try store.int(1);
    const a2 = try store.int(2);
    const b1 = try store.int(3);
    const b2 = try store.int(4);
    const ta = try store.apply(f, &.{ a1, a2 });
    const tb = try store.apply(f, &.{ b1, b2 });

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);

    var d = AstDiff.init(&store);
    d.use_color = false;
    try d.print(buf.writer(allocator), ta, tb);

    try testing.expect(std.mem.indexOf(u8, buf.items, "- .lit") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "+ .lit") != null);
}
