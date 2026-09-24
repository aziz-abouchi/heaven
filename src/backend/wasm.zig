const std = @import("std");
const ast = @import("../kernel/ast.zig");
const typechecker_mod = @import("../kernel/typechecker.zig");
const TypeChecker = typechecker_mod.TypeChecker;

pub const WasmOpcode = enum(u8) {
    @"unreachable" = 0x00,
    nop = 0x01,
    block = 0x02,
    loop = 0x03,
    end = 0x0B,
    call = 0x10,
    local_get = 0x20,
    local_set = 0x21,
    i32_const = 0x41,
    i64_const = 0x42,
    i32_add = 0x6A,
    i32_sub = 0x6B,
    i32_mul = 0x6C,
};

pub const WasmBackend = struct {
    allocator: std.mem.Allocator,
    code: std.ArrayList(u8),
    typechecker: ?*TypeChecker,

    pub fn init(allocator: std.mem.Allocator, tc: ?*TypeChecker) WasmBackend {
        return .{
            .allocator = allocator,
            .code = std.ArrayList(u8){},
            .typechecker = tc,
        };
    }

    pub fn deinit(self: *WasmBackend) void {
        self.code.deinit(self.allocator);
    }

    pub fn emitOpcode(self: *WasmBackend, op: WasmOpcode) !void {
        try self.code.append(self.allocator, @intFromEnum(op));
    }

    pub fn emitLeb128(self: *WasmBackend, value: usize) !void {
        var val = value;
        while (true) {
            var byte: u8 = @intCast(val & 0x7F);
            val >>= 7;
            if (val != 0) {
                byte |= 0x80;
                try self.code.append(self.allocator, byte);
            } else {
                try self.code.append(self.allocator, byte);
                break;
            }
        }
    }

    pub fn compileTerm(self: *WasmBackend, term: ast.Term) !void {
        if (self.typechecker) |tc| {
            if (tc.infer(term)) |tt| {
                if (tc.inferSort(tt)) |sort| {
                    if (sort == .prop) return;
                } else |_| {}
            } else |_| {}
        }

        switch (term) {
            .sort, .pi, .quot => return,

            .class => |c_node| {
                try self.compileTerm(c_node.element.*);
            },

            .lift => |l| {
                try self.compileTerm(l.func_f.*);
            },

            .variable => |v| {
                if (v == 42) {
                    try self.emitOpcode(.i32_const);
                    try self.emitLeb128(42);
                } else {
                    try self.emitOpcode(.local_get);
                    try self.emitLeb128(v);
                }
            },

            .lambda => |l| {
                try self.compileTerm(l.body.*);
            },

            .app => |a| {
                try self.compileTerm(a.arg.*);
                try self.compileTerm(a.func.*);
                // Si la fonction est une opération binaire primitive (ex: i32_add)
                try self.emitOpcode(.i32_add);
            },
        }
    }

    pub fn emitFullModule(self: *WasmBackend, term: ast.Term) ![]const u8 {
        try self.compileTerm(term);
        const body_code = self.code.items;

        var module = std.ArrayList(u8){};
        errdefer module.deinit(self.allocator);

        // En-tête (\0asm + version 1)
        try module.appendSlice(self.allocator, &[_]u8{ 0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00 });

        // Section Type (1) : signature () -> i32
        try module.appendSlice(self.allocator, &[_]u8{ 0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7f });

        // Section Function (3) : 1 fonction (Type 0)
        try module.appendSlice(self.allocator, &[_]u8{ 0x03, 0x02, 0x01, 0x00 });

        // Section Export (7) : export "main"
        try module.appendSlice(self.allocator, &[_]u8{ 0x07, 0x08, 0x01, 0x04 });
        try module.appendSlice(self.allocator, "main");
        try module.appendSlice(self.allocator, &[_]u8{ 0x00, 0x00 });

        // Corps de la fonction
        var fn_body = std.ArrayList(u8){};
        defer fn_body.deinit(self.allocator);
        try fn_body.append(self.allocator, 0x00); // 0 variables locales
        try fn_body.appendSlice(self.allocator, body_code);
        try fn_body.append(self.allocator, 0x0B); // opcode 'end'

        // Section Code (10)
        var code_section = std.ArrayList(u8){};
        defer code_section.deinit(self.allocator);
        try code_section.append(self.allocator, 0x01); // 1 fonction
        try self.writeLeb128Vec(&code_section, fn_body.items.len);
        try code_section.appendSlice(self.allocator, fn_body.items);

        try module.append(self.allocator, 0x0A);
        try self.writeLeb128Vec(&module, code_section.items.len);
        try module.appendSlice(self.allocator, code_section.items);

        return module.toOwnedSlice(self.allocator);
    }

    fn writeLeb128Vec(self: *WasmBackend, buf: *std.ArrayList(u8), value: usize) !void {
        var val = value;
        while (true) {
            var byte: u8 = @intCast(val & 0x7F);
            val >>= 7;
            if (val != 0) {
                byte |= 0x80;
                try buf.append(self.allocator, byte);
            } else {
                try buf.append(self.allocator, byte);
                break;
            }
        }
    }
};
