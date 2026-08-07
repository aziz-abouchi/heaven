const std = @import("std");
const Shell = @import("init.zig").Shell;
const heaven_expr_lib = @import("heaven_expr");

pub var global_heaven_ptr: ?*heaven_expr_lib.Heaven = null;

pub fn greenEvalAdapter(expression: []const u8, allocator: std.mem.Allocator) ?[]const u8 {
    _ = allocator;
    const heaven = global_heaven_ptr orelse return null;
    heaven.engine.fuel = 1000000;

    // Try function call by juxtaposition: "fib 25" -> "fib(25)"
    var tokens = std.mem.tokenizeScalar(u8, expression, ' ');
    const fname = tokens.next() orelse return heaven.eval(expression) catch null;
    if (heaven.engine.fns.get(fname) != null) {
        var args_buf: [256]u8 = undefined;
        var args_len: usize = 0;
        var num_args: usize = 0;
        while (tokens.next()) |arg| {
            if (num_args > 0 and args_len < 255) {
                args_buf[args_len] = ',';
                args_len += 1;
            }
            const copy_len = @min(arg.len, 255 - args_len);
            @memcpy(args_buf[args_len .. args_len + copy_len], arg[0..copy_len]);
            args_len += copy_len;
            num_args += 1;
        }
        if (num_args > 0) {
            var call_buf: [512]u8 = undefined;
            const call_str = std.fmt.bufPrint(&call_buf, "{s}({s})", .{ fname, args_buf[0..args_len] }) catch return null;
            return heaven.eval(call_str) catch null;
        }
    }
    return heaven.eval(expression) catch null;
}

pub fn isCommuted(a: []const u8, b: []const u8) bool {
    // Check if a+b vs b+a or ab vs ba
    const op_pos_a = std.mem.indexOfAny(u8, a, "+-") orelse return false;
    const op_pos_b = std.mem.indexOfAny(u8, b, "+-") orelse return false;
    const a_op = a[op_pos_a];
    const b_op = b[op_pos_b];
    if (a_op != b_op) return false;
    if (a_op != '+' and a_op != '*') return false;
    const a_lhs = std.mem.trim(u8, a[0..op_pos_a], " ");
    const a_rhs = std.mem.trim(u8, a[op_pos_a + 1 ..], " ");
    const b_lhs = std.mem.trim(u8, b[0..op_pos_b], " ");
    const b_rhs = std.mem.trim(u8, b[op_pos_b + 1 ..], " ");
    return std.mem.eql(u8, a_lhs, b_rhs) and std.mem.eql(u8, a_rhs, b_lhs);
}

pub fn proveCommutative(_: *Shell, a: []const u8, b: []const u8) bool {
    if (a.len < 5 or b.len < 5) return false;
    if (a[0] != '(' or b[0] != '(') return false;
    const a_space = std.mem.indexOfScalar(u8, a[1..], ' ') orelse return false;
    const b_space = std.mem.indexOfScalar(u8, b[1..], ' ') orelse return false;
    const a_op = a[1 .. a_space + 1];
    const b_op = b[1 .. b_space + 1];
    if (!std.mem.eql(u8, a_op, b_op)) return false;
    if (!std.mem.eql(u8, a_op, "+") and !std.mem.eql(u8, a_op, "*")) return false;
    const a_rest = std.mem.trim(u8, a[a_space + 2 .. a.len - 1], " ");
    const b_rest = std.mem.trim(u8, b[b_space + 2 .. b.len - 1], " ");
    // Split respecting parens
    const a_mid = splitAtDepthZero(a_rest) orelse return false;
    const b_mid = splitAtDepthZero(b_rest) orelse return false;
    const a_x = std.mem.trim(u8, a_rest[0..a_mid], " ");
    const a_y = std.mem.trim(u8, a_rest[a_mid + 1 ..], " ");
    const b_x = std.mem.trim(u8, b_rest[0..b_mid], " ");
    const b_y = std.mem.trim(u8, b_rest[b_mid + 1 ..], " ");
    return std.mem.eql(u8, a_x, b_y) and std.mem.eql(u8, a_y, b_x);
}

pub fn splitAtDepthZero(s: []const u8) ?usize {
    var depth: i32 = 0;
    for (s, 0..) |ch, idx| {
        switch (ch) {
            '(' => depth += 1,
            ')' => depth -= 1,
            ' ' => if (depth == 0 and idx > 0) return idx,
            else => {},
        }
    }
    return null;
}
