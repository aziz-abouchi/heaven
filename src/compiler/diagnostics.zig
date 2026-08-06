const std = @import("std");
const platform = @import("platform");

pub const Severity = enum {
    err,
    warning,
    info,
    hint,
};

pub const Position = struct {
    line: u32,
    col: u32,
};

pub const Diagnostic = struct {
    severity: Severity,
    start: Position,
    end: Position,
    message: []const u8,
    source: []const u8 = "heaven",
};

pub const DiagnosticList = struct {
    items: std.ArrayListUnmanaged(Diagnostic) = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DiagnosticList {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *DiagnosticList) void {
        self.items.deinit(self.allocator);
    }

    pub fn err(self: *DiagnosticList, line: u32, col: u32, msg: []const u8) void {
        self.items.append(self.allocator, .{
            .severity = .err,
            .start = .{ .line = line, .col = col },
            .end = .{ .line = line, .col = col },
            .message = msg,
        }) catch {};
    }

    pub fn warn(self: *DiagnosticList, line: u32, col: u32, msg: []const u8) void {
        self.items.append(self.allocator, .{
            .severity = .warning,
            .start = .{ .line = line, .col = col },
            .end = .{ .line = line, .col = col },
            .message = msg,
        }) catch {};
    }

    pub fn print(self: *const DiagnosticList, file_path: []const u8) void {
        for (self.items.items) |d| {
            const sev: []const u8 = switch (d.severity) {
                .err => "error",
                .warning => "warning",
                .info => "info",
                .hint => "hint",
            };
            platform.debug.print("{s}:{d}:{d}: {s}: {s}\n", .{
                file_path,
                d.start.line + 1,
                d.start.col + 1,
                sev,
                d.message,
            });
        }
    }
};
