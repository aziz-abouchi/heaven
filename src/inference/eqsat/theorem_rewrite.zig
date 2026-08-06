const std = @import("std");

pub const TheoremRewrite = struct {
    name: []const u8,

    lhs: []const u8,
    rhs: []const u8,
};
