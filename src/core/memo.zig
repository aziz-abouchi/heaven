const std = @import("std");
const expr = @import("expr");
const Id = expr.Id;

/// Simple memoization cache for function results
pub const MemoCache = struct {
    cache: std.AutoHashMap(u64, Id),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MemoCache {
        return .{
            .cache = std.AutoHashMap(u64, Id).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MemoCache) void {
        self.cache.deinit();
    }

    /// Generate a hash key for a function call
    pub fn hashCall(name: []const u8, args: []const Id) u64 {
        var hash: u64 = 0;
        for (name) |c| {
            hash = hash *% 31 +% c;
        }
        for (args) |arg| {
            hash = hash *% 31 +% @as(u64, @intCast(@intFromEnum(arg)));
        }
        return hash;
    }

    pub fn get(self: *MemoCache, key: u64) ?Id {
        return self.cache.get(key);
    }

    pub fn put(self: *MemoCache, key: u64, value: Id) !void {
        try self.cache.put(key, value);
    }

    pub fn clear(self: *MemoCache) void {
        self.cache.clearRetainingCapacity();
    }
};
