// HEAVEN:io_console — extraction console/stdio (refactor plateforme)
const std = @import("std");
const target = @import("target.zig");

pub var debug_enabled: bool = false;

/// Debug conditionnel : activé par HEAVEN_DEBUG=1
pub fn dbg(comptime fmt: []const u8, args: anytype) void {
    if (debug_enabled) std.debug.print(fmt, args);
}

pub fn getenv(key: []const u8) ?[]const u8 {
    if (target.is_windows) {
        return std.process.getEnvVarOwned(std.heap.page_allocator, key) catch null;
    } else {
        return std.posix.getenv(key);
    }
}

// --- RAW MODE (clavier caractere par caractere) ---
pub const ConsoleRawMode = struct {
    original: std.posix.termios,
};

/// Passe le terminal en mode raw. Retourne null si stdin n'est pas un TTY.
pub fn enableRawMode() !?ConsoleRawMode {
    const fd = std.posix.STDIN_FILENO;
    if (!std.posix.isatty(fd)) return null;
    var termios = try std.posix.tcgetattr(fd);
    const original = termios;
    termios.lflag.ECHO = false;
    termios.lflag.ICANON = false;
    termios.lflag.ISIG = false;
    termios.iflag.ICRNL = false;
    termios.iflag.IXON = false;
    termios.iflag.INLCR = false;
    termios.iflag.IGNCR = false;
    try std.posix.tcsetattr(fd, .NOW, termios);
    return .{ .original = original };
}

/// Restaure les attributs termios originaux.
pub fn disableRawMode(state: ConsoleRawMode) void {
    _ = std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, state.original) catch {};
}

pub fn initConsole() void {}

// --- STDIN / STDOUT / STDERR ---
pub fn writeStdout(buf: []const u8) !usize {
    if (target.is_windows) {
        const handle = std.os.windows.kernel32.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) orelse return error.BadFileDescriptor;
        if (handle == std.os.windows.INVALID_HANDLE_VALUE) return error.BadFileDescriptor;
        return std.posix.write(handle, buf);
    } else {
        return std.posix.write(std.posix.STDOUT_FILENO, buf);
    }
}

pub fn readStdin(buf: []u8) !usize {
    return std.posix.read(std.posix.STDIN_FILENO, buf);
}
