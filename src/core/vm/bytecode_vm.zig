const std = @import("std");
const bc = @import("../../inference/forge/bytecode.zig");

pub const VM = struct {
    stack: std.ArrayList(i64),

    pub fn init(allocator: std.mem.Allocator) VM {
        return .{
            .stack = std.ArrayList(i64).init(allocator),
        };
    }

    pub fn run(self: *VM, code: []bc.Instr) !void {
        for (code) |ins| {
            switch (ins.op) {
                .PUSH => try self.stack.append(ins.arg),
                .ADD => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    try self.stack.append(a + b);
                },
                .MUL => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    try self.stack.append(a * b);
                },
                .HALT => return,
                else => {},
            }
        }
    }
};
