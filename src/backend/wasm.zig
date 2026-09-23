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
            .code = std.ArrayList(u8).init(allocator),
            .typechecker = tc,
        };
    }

    pub fn deinit(self: *WasmBackend) void {
        self.code.deinit();
    }

    pub fn emitOpcode(self: *WasmBackend, op: WasmOpcode) !void {
        try self.code.append(@intFromEnum(op));
    }

    pub fn emitLeb128(self: *WasmBackend, value: usize) !void {
        var val = value;
        while (true) {
            var byte: u8 = @intCast(val & 0x7F);
            val >>= 7;
            if (val != 0) {
                byte |= 0x80;
                try self.code.append(byte);
            } else {
                try self.code.append(byte);
                break;
            }
        }
    }

    pub fn compileTerm(self: *WasmBackend, term: ast.Term) !void {
        // 1. Effacement absolu des preuves (Prop)
        if (self.typechecker) |tc| {
            if (tc.infer(term)) |tt| {
                if ((tc.inferSort(tt) catch .type_sort) == .prop) {
                    return; // Aucun bytecode généré pour les preuves
                }
            } else |_| {}
        }

        // 2. Traitement des termes quotients et émission Wasm standard
        switch (term) {
            // Les types purement statiques (Sorts, Pi, Quot) sont totalement effacés à l'exécution
            .sort, .pi, .quot => {
                return;
            },

            // class(x) s'efface vers x (pas de surcoût à l'exécution)
            .class => |c| {
                try self.compileTerm(c.element.*);
            },

            // lift(f, p) s'efface vers f (la preuve p est totalement ignorée)
            .lift => |l| {
                try self.compileTerm(l.func_f.*);
            },

            // Variables locales : émission de local.get index
            .variable => |v| {
                try self.emitOpcode(.local_get);
                try self.emitLeb128(v);
            },

            // Abstraction Lambda : compilation du corps
            .lambda => |l| {
                try self.compileTerm(l.body.*);
            },

            // Application de fonction : empilement des arguments puis appel
            .app => |a| {
                try self.compileTerm(a.arg.*);
                try self.compileTerm(a.func.*);
                try self.emitOpcode(.call);
                try self.emitLeb128(0);
            },
        }
    }
};