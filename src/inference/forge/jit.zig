const std = @import("std");
const matrix_lib = @import("../../core/matrix.zig");
const autofab = @import("../../runtime/autofab.zig");

pub const JitEngine = struct {
    state: *autofab.TCCState,
    allocator: std.mem.Allocator,

    pub fn init() !JitEngine {
        const s = autofab.tcc_new() orelse return error.TccInitFailed;
        return JitEngine{ .state = s, .allocator = std.heap.page_allocator };
    }
    pub fn compileAndRun(self: *JitEngine, code: []const u8, entry_point: []const u8) !void {
        // On crée un state temporaire pour ce pulse précis
        const tmp_state = autofab.tcc_new() orelse return error.TccInitFailed;
        defer autofab.tcc_delete(tmp_state); // Nettoyage après exécution

        const code_z = try self.allocator.dupeZ(u8, code);
        defer self.allocator.free(code_z);

        // Ajout des symboles système (pour write, printf, etc.)
        _ = autofab.tcc_set_lib_path(tmp_state, "/usr/lib"); // Ajuste selon ton OS

        if (autofab.tcc_compile_string(tmp_state, code_z.ptr) != 0) return error.CompilationFailed;
        if (autofab.tcc_relocate(tmp_state, autofab.TCC_RELOCATE_AUTO) < 0) return error.RelocationFailed;

        const func_ptr = autofab.tcc_get_symbol(tmp_state, entry_point.ptr) orelse return error.SymbolNotFound;
        const func = @as(*const fn () callconv(.c) void, @ptrCast(@alignCast(func_ptr)));

        func(); // <--- C'est ici que Bob parle !
    }
};
