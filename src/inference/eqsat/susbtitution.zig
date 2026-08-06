const std = @import("std");

pub const Substitution = struct {
    allocator: std.mem.Allocator,
    map: std.StringHashMap(u32),

    pub fn init(alloc: std.mem.Allocator) Substitution {
        return .{
            .allocator = alloc,
            .map = std.StringHashMap(u32).init(alloc),
        };
    }

    pub fn get(self: *Substitution, key: []const u8) ?u32 {
        return self.map.get(key);
    }

    pub fn put(self: *Substitution, key: []const u8, val: u32) !void {
        try self.map.put(key, val);
    }
};
