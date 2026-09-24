const std = @import("std");
const builtin = @import("builtin");

pub const Intrinsics = struct {
    pub fn dispatchSyscall(nr: usize, args: []const usize) !usize {
        if (builtin.target.cpu.arch == .wasm32) {
            return error.SyscallNotSupportedOnWasm;
        }

        // Sur Linux / macOS x86_64 / arm64
        return switch (args.len) {
            0 => std.os.linux.syscall0(@enumFromInt(nr)),
            1 => std.os.linux.syscall1(@enumFromInt(nr), args[0]),
            2 => std.os.linux.syscall2(@enumFromInt(nr), args[0], args[1]),
            3 => std.os.linux.syscall3(@enumFromInt(nr), args[0], args[1], args[2]),
            4 => std.os.linux.syscall4(@enumFromInt(nr), args[0], args[1], args[2], args[3]),
            5 => std.os.linux.syscall5(@enumFromInt(nr), args[0], args[1], args[2], args[3], args[4]),
            6 => std.os.linux.syscall6(@enumFromInt(nr), args[0], args[1], args[2], args[3], args[4], args[5]),
            else => error.TooManySyscallArgs,
        };
    }

    pub fn dispatchExtern(lib_name: []const u8, symbol_name: []const u8, args: []const usize) !usize {
        _ = args;
        _ = symbol_name;
        _ = lib_name;
        // Résolution dynamique via std.DynLib ou imports WASM
        return error.NotImplemented;
    }
};
