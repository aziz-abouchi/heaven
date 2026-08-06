const std = @import("std"); const Allocator = std.mem.Allocator;

pub const CCodegen = struct { allocator: Allocator, matrix: *anyopaque,

pub fn init(allocator: Allocator, matrix: anytype) CCodegen {
    return .{
        .allocator = allocator,
        .matrix = @ptrCast(matrix),
    };
}

pub fn deinit(_: *CCodegen) void {}

pub fn generateForFunction(self: *CCodegen, _: []const u8) ![]u8 {
    return self.allocator.dupe(u8, "/* codegen: not yet migrated to Expr */\n");
}

pub fn generate(self: *CCodegen) ![]u8 {
    return self.allocator.dupe(u8, "/* codegen: not yet migrated to Expr */\n");
}
};
