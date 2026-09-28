const std = @import("std");

pub const LanguageSpec = struct {
    name: []const u8,
    tokens: std.StringHashMap([]const u8), // "Print" -> "printf(\"{payload}\")"

    pub fn init(allocator: std.mem.Allocator, name: []const u8) LanguageSpec {
        return .{
            .name = name,
            .tokens = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn translateEffect(self: *const LanguageSpec, allocator: std.mem.Allocator, effect_name: []const u8, payload: []const u8) ![]const u8 {
        const pattern = self.tokens.get(effect_name) orelse return payload;
        // Remplacement simple du template {payload}
        return std.mem.replaceOwned(u8, allocator, pattern, "{payload}", payload);
    }
};
