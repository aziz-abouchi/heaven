const std = @import("std");
const platform = @import("platform");

pub const History = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayListUnmanaged([]const u8),
    max_len: usize,
    index: usize,

    pub fn init(allocator: std.mem.Allocator, max_len: usize) History {
        return .{
            .allocator = allocator,
            .items = .{},
            .max_len = max_len,
            .index = 0,
        };
    }

    pub fn deinit(self: *History) void {
        for (self.items.items) |item| self.allocator.free(item);
        self.items.deinit(self.allocator);
    }

    pub fn push(self: *History, line: []const u8) !void {
        if (line.len == 0) return;
        if (self.items.items.len > 0 and std.mem.eql(u8, self.items.items[self.items.items.len - 1], line)) {
            return;
        }
        if (self.items.items.len >= self.max_len) {
            const oldest = self.items.orderedRemove(0);
            self.allocator.free(oldest);
        }
        const copy = try self.allocator.dupe(u8, line);
        try self.items.append(self.allocator, copy);
        self.index = self.items.items.len;
    }

    pub fn previous(self: *History) ?[]const u8 {
        if (self.index == 0) return null;
        self.index -= 1;
        return self.items.items[self.index];
    }

    pub fn next(self: *History) ?[]const u8 {
        if (self.index == self.items.items.len) return null;
        self.index += 1;
        if (self.index == self.items.items.len) return "";
        return self.items.items[self.index];
    }

    pub fn saveToFile(self: *History, path: []const u8) !void {
        const file = try platform.fs.cwd().createFile(path, .{ .truncate = true });
        defer file.close();
        var buf: [4096]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);
        for (self.items.items) |line| {
            stream.reset();
            try stream.writer().writeAll(line);
            try stream.writer().writeAll("\n");
            try file.writeAll(stream.getWritten());
        }
    }

    pub fn loadFromFile(self: *History, path: []const u8) !void {
        const file = platform.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        defer file.close();
        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);
        var it = std.mem.splitScalar(u8, content, '\n');
        while (it.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \r");
            if (trimmed.len > 0) {
                try self.push(trimmed);
            }
        }
        self.index = self.items.items.len;
    }
};