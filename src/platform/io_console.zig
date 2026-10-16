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

// --- I/O ABSTRACTION (deplace depuis x86_64_linux.zig) ---
pub const io = struct {
    pub fn print(comptime fmt: []const u8, args: anytype) void {
        std.debug.print(fmt, args);
    }

    pub fn readLine(alloc: std.mem.Allocator) ![]u8 {
        const stdin = std.fs.File.stdin().reader();
        return stdin.readUntilDelimiterAlloc(alloc, '\n', 4096);
    }
};

pub fn readLine(alloc: std.mem.Allocator) ![]u8 {
    var buf: [4096]u8 = undefined;
    const n = try std.posix.read(0, &buf);

    if (n == 0) return error.EndOfStream;
    const line = buf[0..n];
    const line_clean = if (line.len > 0 and line[line.len - 1] == '\n')
        line[0 .. line.len - 1]
    else
        line;
    return try alloc.dupe(u8, line_clean);
}
