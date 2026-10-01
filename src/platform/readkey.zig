const std = @import("std");
const builtin = @import("builtin");

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
    _padding: u16 = 0,
    Event: extern union {
        KeyEvent: KEY_EVENT_RECORD,
        _reserved: [16]u8,
    },
};

extern "kernel32" fn ReadConsoleInputA(
    hConsoleInput: std.os.windows.HANDLE,
    lpBuffer: *INPUT_RECORD,
    nLength: u32,
    lpNumberOfEventsRead: *u32,
) callconv(.winapi) i32;

pub fn readKey() !KeyEvent {
    if (builtin.os.tag == .windows) {
        return readKeyWindows();
    } else {
        return readKeyUnix();
    }
}

fn readKeyWindows() !KeyEvent {
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

fn readKeyUnix() !KeyEvent {
    var buf: [1]u8 = undefined;
    const n = try std.posix.read(0, &buf);
    if (n == 0) return error.EndOfStream;
    const c = buf[0];
    if (c == 27) {
        var seq: [2]u8 = undefined;
        var count: usize = 0;
        while (count < 2) {
            const r = try std.posix.read(0, seq[count .. count + 1]);
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
