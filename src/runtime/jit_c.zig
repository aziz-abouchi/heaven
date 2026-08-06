const std = @import("std");
const platform = @import("platform");

pub const JitC = struct {
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) JitC {
        return .{ .allocator = alloc };
    }

    fn wrapIfNeeded(self: *JitC, code: []const u8) ![]const u8 {
        // Si déjà une fonction entry → on ne touche pas
        if (std.mem.indexOf(u8, code, "heaven_entry") != null) {
            return code;
        }

        return try std.fmt.allocPrint(self.allocator,
            \\#include <stdio.h>
            \\
            \\void heaven_entry() {{
            \\{s}
            \\}}
        , .{code});
    }

    pub fn compileAndRun(self: *JitC, code: []const u8) !void {
        const wrapped = try self.wrapIfNeeded(code);
        defer if (wrapped.ptr != code.ptr) std.heap.page_allocator.free(wrapped);

        const src_path = "/tmp/heaven_tmp.c";
        const so_path = "/tmp/heaven_tmp.so";

        // 1. write C file
        const file = try platform.fs.cwd().createFile(src_path, .{});
        defer file.close();
        try file.writeAll(wrapped);

        // 2. compile
        const args = [_][]const u8{
            "cc",
            "-shared",
            "-fPIC",
            "-o",
            so_path,
            src_path,
        };

        var child = std.process.Child.init(&args, self.allocator);
        try child.spawn();
        const term = try child.wait();
        if (term != .Exited or term.Exited != 0) return error.CompileError;

        // 3. load .so
        var lib = try std.DynLib.open(so_path);
        defer lib.close();

        const fn_ptr = lib.lookup(*const fn () callconv(.c) void, "heaven_entry") orelse return error.SymbolNotFound;

        _ = fn_ptr();
    }
};
