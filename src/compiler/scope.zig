const std = @import("std");
const expr = @import("expr");

pub const TypeInfo = struct {
    type_name: []const u8,
    expr_id: expr.Id = expr.NULL,
    mutable: bool = false,
    kind: Kind = .variable,

    pub const Kind = enum {
        variable,
        function,
        type_decl,
        effect,
        actor,
        module,
    };
};

pub const Scope = struct {
    frames: std.ArrayListUnmanaged(Frame) = .{},
    allocator: std.mem.Allocator,

    const Frame = struct {
        symbols: std.StringHashMapUnmanaged(TypeInfo) = .{},
        name: []const u8 = "<block>",
    };

    pub fn init(allocator: std.mem.Allocator) Scope {
        var s = Scope{ .allocator = allocator };
        s.push("global") catch {};
        return s;
    }

    pub fn deinit(self: *Scope) void {
        for (self.frames.items) |*f| {
            f.symbols.deinit(self.allocator);
        }
        self.frames.deinit(self.allocator);
    }

    pub fn push(self: *Scope, name: []const u8) !void {
        try self.frames.append(self.allocator, .{ .name = name });
    }

    pub fn pop(self: *Scope) void {
        if (self.frames.items.len > 1) {
            const f = self.frames.pop().?;
            var frame = f;
            frame.symbols.deinit(self.allocator);
        }
    }

    pub fn define(self: *Scope, name: []const u8, info: TypeInfo) !void {
        if (self.frames.items.len == 0) return;
        var frame = &self.frames.items[self.frames.items.len - 1];
        try frame.symbols.put(self.allocator, name, info);
    }

    pub fn lookup(self: *const Scope, name: []const u8) ?TypeInfo {
        var i = self.frames.items.len;
        while (i > 0) {
            i -= 1;
            if (self.frames.items[i].symbols.get(name)) |info| {
                return info;
            }
        }
        return null;
    }

    pub fn currentFrame(self: *const Scope) []const u8 {
        if (self.frames.items.len == 0) return "<empty>";
        return self.frames.items[self.frames.items.len - 1].name;
    }
    pub fn addBuiltins(self: *Scope) !void {
        const builtins = [_][]const u8{
            "print",
            "println",
            "debug",
            "len",
            "length",
            "size",
            "map",
            "filter",
            "reduce",
            "fold",
            "sum",
            "sort",
            "reverse",
            "head",
            "tail",
            "push",
            "pop",
            "read_file",
            "write_file",
            "spawn",
            "send",
            "receive",
            "perform",
            "handle",
            "assert",
            "assert_eq",
            "assert_ne",
            "assert_err",
            "assert_not",
            "assert_is",
            "sample",
            "observe",
            "infer",
            "steal",
            "health_check",
            "gc_force",
            "random_vec",
            "parse_csv",
            "log_warn",
            "log_error",
            "fetch",
            "emit_metrics",
            "pow",
            "abs",
            "min",
            "max",
            "sqrt",
            "compose",
            "id",
            "not",
            "and",
            "or",
            "true",
            "false",
            "divide",
            "add",
            "sub",
            "mul",
            "double",
            "triple",
            "best",
            "promote",
            "independent",
        };
        for (builtins) |name| {
            try self.define(name, .{ .type_name = "builtin", .kind = .function });
        }
    }
};
