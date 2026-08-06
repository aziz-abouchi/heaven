const std = @import("std");

pub const TCCState = opaque {};
pub extern "c" fn tcc_new() ?*TCCState;
pub extern "c" fn tcc_delete(s: *TCCState) void;
pub extern "c" fn tcc_set_output_type(s: *TCCState, output_type: c_int) c_int;
pub extern "c" fn tcc_compile_string(s: *TCCState, code: [*:0]const u8) c_int;
pub extern "c" fn tcc_relocate(s: *TCCState, ptr: ?*anyopaque) c_int;
pub extern "c" fn tcc_get_symbol(s: *TCCState, name: [*:0]const u8) ?*anyopaque;
pub extern "c" fn tcc_add_symbol(s: *TCCState, name: [*:0]const u8, val: ?*const anyopaque) c_int;

pub const JIT = struct {
    state: *TCCState,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !JIT {
        const s = tcc_new() orelse return error.TccInitFailed;
        _ = tcc_set_output_type(s, 1); // TCC_OUTPUT_MEMORY
        return JIT{ .state = s, .allocator = allocator };
    }

    pub fn addSymbol(self: *JIT, name: [:0]const u8, ptr: ?*const anyopaque) void {
        _ = tcc_add_symbol(self.state, name, ptr);
    }

    pub fn compile(self: *JIT, code: []const u8) !void {
        const c_code = try self.allocator.dupeZ(u8, code);
        defer self.allocator.free(c_code);
        if (tcc_compile_string(self.state, c_code) != 0) return error.CompileError;
        if (tcc_relocate(self.state, null) < 0) return error.RelocateError;
    }

    pub fn getEntryPoint(self: *JIT, name: [:0]const u8) ?*anyopaque {
        return tcc_get_symbol(self.state, name);
    }

    pub fn deinit(self: *JIT) void {
        tcc_delete(self.state);
    }
};
