const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform");
const History = @import("history.zig").History;
const Heaven = @import("heaven_expr").Heaven;
const eval = @import("eval.zig");

fn readStdinByte(buf: []u8) !usize {
    if (comptime builtin.os.tag == .windows) {
        const handle = try std.os.windows.GetStdHandle(
            std.os.windows.STD_INPUT_HANDLE,
        );
        return std.os.windows.ReadFile(handle, buf, null);
    } else {
        return std.posix.read(std.posix.STDIN_FILENO, buf);
    }
}

const KEY_EVENT: u16 = 0x0001;
const VK_LEFT: u16 = 0x25;
const VK_UP: u16 = 0x26;
const VK_RIGHT: u16 = 0x27;
const VK_DOWN: u16 = 0x28;

const KEY_EVENT_RECORD = extern struct {
    bKeyDown: i32,
    wRepeatCount: u16,
    wVirtualKeyCode: u16,
    wVirtualScanCode: u16,
    uChar: extern union {
        UnicodeChar: u16,
        AsciiChar: u8,
    },
    dwControlKeyState: u32,
};

const INPUT_RECORD = extern struct {
    EventType: u16,
    // padding pour aligner l'union sur 4 octets, comme dans le vrai INPUT_RECORD Win32
    _padding: u16 = 0,
    Event: extern union {
        KeyEvent: KEY_EVENT_RECORD,
        _reserved: [16]u8, // couvre MOUSE_EVENT_RECORD/WINDOW_BUFFER_SIZE_RECORD/etc., non utilisés ici
    },
};

extern "kernel32" fn ReadConsoleInputA(
    hConsoleInput: std.os.windows.HANDLE,
    lpBuffer: *INPUT_RECORD,
    nLength: u32,
    lpNumberOfEventsRead: *u32,
) callconv(.winapi) i32;

pub const KeyEvent = union(enum) {
    char: u8,
    arrow_up,
    arrow_down,
    arrow_left,
    arrow_right,
    tab,
    enter,
    backspace,
    delete,
    ctrl_c,
    ctrl_d,
    escape,
    unknown,
};

pub const CompletionItem = eval.CompletionItem;

pub const Reader = struct {
    allocator: std.mem.Allocator,
    heaven: *Heaven,
    history: *History,

    line: std.ArrayListUnmanaged(u8) = .{},
    cursor: usize = 0,
    prompt: []const u8 = "",

    // Pour Unix raw mode
    raw_mode: bool = false,
    termios_orig: ?std.posix.termios = null,

    pub fn init(allocator: std.mem.Allocator, heaven: *Heaven, history: *History) !Reader {
        var self = Reader{
            .allocator = allocator,
            .heaven = heaven,
            .history = history,
        };
        try self.enableRawMode();
        return self;
    }

    pub fn deinit(self: *Reader) void {
        self.disableRawMode();
        self.line.deinit(self.allocator);
    }

    fn enableRawMode(self: *Reader) !void {
        if (comptime builtin.os.tag == .windows) {
            self.raw_mode = false;
            return;
        }
        const fd = std.posix.STDIN_FILENO;

        // Pipe, redirection, CI headless : pas de TTY → pas de mode raw,
        // pas d'erreur non plus. On bascule en mode ligne (readUntilDelimiter).
        if (!std.posix.isatty(fd)) {
            self.raw_mode = false;
            return;
        }

        var termios = try std.posix.tcgetattr(fd);
        self.termios_orig = termios;

        // Désactiver ECHO et ICANON
        switch (builtin.os.tag) {
            .macos, .ios, .tvos, .watchos, .visionos => {
                termios.lflag.ECHO   = false;
                termios.lflag.ICANON = false;
                termios.lflag.ISIG   = false;  // sinon Ctrl-C tue le process
                termios.iflag.ICRNL  = false;  // CR (0x0D) ne devient PAS NL (0x0A)
                termios.iflag.IXON   = false;  // Ctrl-S/Ctrl-Q ne gèlent pas
                termios.iflag.INLCR  = false;
                termios.iflag.IGNCR  = false;
            },
            .linux => {
                const ECHO: u32   = 0x00000008;
                const ICANON: u32 = 0x00000002;
                const ISIG: u32   = 0x00000001;
                const ICRNL: u32  = 0x00000100;
                const IXON: u32   = 0x00000400;
                termios.lflag &= ~@as(@TypeOf(termios.lflag), ECHO | ICANON | ISIG);
                termios.iflag &= ~@as(@TypeOf(termios.iflag), ICRNL | IXON);
            },
            else => {},
        }

        try std.posix.tcsetattr(fd, .NOW, termios);
        self.raw_mode = true;
    }

    fn disableRawMode(self: *Reader) void {
        if (comptime builtin.os.tag == .windows) return;
        if (self.raw_mode) {
            if (self.termios_orig) |orig| {
                _ = std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, orig) catch {};
            }
            self.raw_mode = false;
        }
    }

    pub fn readKey(self: *Reader) !KeyEvent {
        if (comptime builtin.os.tag == .windows) {
            return self.readKeyWindows();
        } else {
            return self.readKeyUnix();
        }
    }

    fn readKeyWindows(self: *Reader) !KeyEvent {
        _ = self;
        const windows = std.os.windows;
        const handle = windows.kernel32.GetStdHandle(windows.STD_INPUT_HANDLE) orelse return error.BadFileDescriptor;
        var event: INPUT_RECORD = undefined;
        var events_read: u32 = 0;
        while (true) {
            const ok = ReadConsoleInputA(handle, &event, 1, &events_read);
            if (ok == 0) return error.ReadError;
            if (event.EventType == KEY_EVENT and event.Event.KeyEvent.bKeyDown != 0) {
                const ascii = event.Event.KeyEvent.uChar.AsciiChar;
                if (ascii != 0) {
                    return switch (ascii) {
                        '\r' => .enter,
                        '\t' => .tab,
                        127 => .backspace,
                        3 => .ctrl_c,
                        4 => .ctrl_d,
                        27 => .escape,
                        else => .{ .char = ascii },
                    };
                }
                const vk = event.Event.KeyEvent.wVirtualKeyCode;
                return switch (vk) {
                    VK_UP => .arrow_up,
                    VK_DOWN => .arrow_down,
                    VK_LEFT => .arrow_left,
                    VK_RIGHT => .arrow_right,
                    else => .unknown,
                };
            }
        }
    }

    fn readKeyUnix(self: *Reader) !KeyEvent {
        _ = self;
        var buf: [1]u8 = undefined;
        const n = try std.posix.read(0, &buf);
        if (n == 0) return error.EndOfStream;
        const c = buf[0];
        if (c == 27) {
            var seq: [2]u8 = undefined;
            var count: usize = 0;
            while (count < 2) {
                const r = try std.posix.read(0, seq[count..count+1]);
                if (r == 0) break;
                count += 1;
            }
            if (count >= 2 and seq[0] == '[') {
                return switch (seq[1]) {
                    'A' => .arrow_up,
                    'B' => .arrow_down,
                    'C' => .arrow_right,
                    'D' => .arrow_left,
                    else => .escape,
                };
            }
            return .escape;
        }
        return switch (c) {
            '\r' => .enter,
            '\t' => .tab,
            127 => .backspace,
            3 => .ctrl_c,
            4 => .ctrl_d,
            else => .{ .char = c },
        };
    }

    fn clampCursor(self: *Reader) void {
        if (self.cursor > self.line.items.len) {
            self.cursor = self.line.items.len;
        }
    }

    pub fn readLine(self: *Reader, prompt: []const u8) ![]const u8 {
        self.prompt = prompt;
        if (!self.raw_mode) {
            // Chemin dégradé : lit ligne par ligne sur fd 0 (pipe, redirection, CI).
            // Pas de flèches, pas de Tab, pas de redraw.
            _ = try platform.writeStdout(prompt);
            self.line.clearRetainingCapacity();
            self.cursor = 0;
            var buf: [1]u8 = undefined;
            while (true) {
                const n = readStdinByte(&buf) catch return error.ReadError;
                if (n == 0) {
                    if (self.line.items.len == 0) return error.EndOfStream;
                    break;
                }
                const c = buf[0];
                if (c == '\n') break;
                if (c == '\r') continue;
                try self.line.append(self.allocator, c);
            }
            const line = try self.line.toOwnedSlice(self.allocator);
            if (line.len > 0) try self.history.push(line);
            return line;
        }
        _ = try platform.writeStdout(prompt);

        self.line.clearRetainingCapacity();
        self.cursor = 0;
        var history_index: usize = self.history.items.items.len;

        while (true) {
            const event = try self.readKey();
            switch (event) {
                .enter => {
                    _ = try platform.writeStdout("\r\n");
                    const line = try self.line.toOwnedSlice(self.allocator);
                    if (line.len > 0) {
                        try self.history.push(line);
                    }
                    return line;
                },
                .tab => {
                    const prefix = self.getCurrentPrefix();
                    const start = std.mem.lastIndexOfScalar(u8, self.line.items[0..self.cursor], ' ') orelse 0;
                    const items = eval.getCompletions(self.allocator, self.heaven, prefix) catch |err| {
                        platform.debug.print("  Erreur de complétion : {}\n", .{err});
                        continue;
                    };
                    defer {
                        for (items) |item| self.allocator.free(item.label);
                        self.allocator.free(items);
                    }
                    if (items.len == 1) {
                        // Remplacer le préfixe par la suggestion
                        const insert = items[0].label;
                        self.clampCursor();
                        if (start < self.cursor) {
                            _ = try self.line.replaceRange(self.allocator, start, self.cursor, "");
                            self.cursor = start;
                        }
                        try self.line.insertSlice(self.allocator, start, insert);
                        self.cursor = start + insert.len;
                        try self.redrawLine();
                    } else if (items.len > 1) {
                        _ = try platform.writeStdout("\r\n");
                        for (items) |item| {
                            platform.debug.print("  {s} ({s})\n", .{ item.label, @tagName(item.kind) });
                        }
                        _ = try platform.writeStdout(prompt);
                        _ = try platform.writeStdout(self.line.items);
                        try self.moveCursorTo(self.cursor);
                    }
                },
                .arrow_up => {
                    if (history_index > 0) {
                        history_index -= 1;
                        const prev = self.history.items.items[history_index];
                        self.line.clearRetainingCapacity();
                        try self.line.appendSlice(self.allocator, prev);
                        self.cursor = prev.len;
                        try self.redrawLine();
                    }
                },
                .arrow_down => {
                    if (history_index < self.history.items.items.len) {
                        history_index += 1;
                        const next = if (history_index == self.history.items.items.len) "" else self.history.items.items[history_index];
                        self.line.clearRetainingCapacity();
                        try self.line.appendSlice(self.allocator, next);
                        self.cursor = next.len;
                        try self.redrawLine();
                    }
                },
                .backspace => {
                    if (self.cursor > 0) {
                        self.cursor -= 1;
                        _ = self.line.orderedRemove(self.cursor);
                        try self.redrawLine();
                    }
                },
                .ctrl_c => {
                    _ = try platform.writeStdout("^C\r\n");
                    self.line.clearRetainingCapacity();
                    self.cursor = 0;
                    _ = try platform.writeStdout(prompt);
                },
                .ctrl_d => {
                    if (self.line.items.len == 0) {
                        return error.EndOfStream;
                    }
                },
                .char => |c| {
                    try self.line.insert(self.allocator, self.cursor, c);
                    self.cursor += 1;
                    try self.redrawLine();
                },
                else => {},
            }
            self.clampCursor();
        }
    }

    fn getCurrentPrefix(self: *Reader) []const u8 {
        const start = std.mem.lastIndexOfScalar(u8, self.line.items[0..self.cursor], ' ') orelse 0;
        return self.line.items[start..self.cursor];
    }

    fn redrawLine(self: *Reader) !void {
        _ = try platform.writeStdout("\r\x1b[K");
        _ = try platform.writeStdout(self.prompt);
        _ = try platform.writeStdout(self.line.items);
        try self.moveCursorTo(self.prompt.len + self.cursor);
    }

    fn moveCursorTo(self: *Reader, pos: usize) !void {
        _ = self;
        var buf: [32]u8 = undefined;
        const s = try std.fmt.bufPrint(&buf, "\x1b[{d}G", .{pos + 1});
        _ = try platform.writeStdout(s);
    }
};
