const std = @import("std");

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn main() !void {
    const x = add(10, 20);
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Result: {d}\n", .{x});

    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try stdout.print("{d} ", .{i});
    }

    if (x > 15) {
        try stdout.print("big\n", .{});
    } else {
        try stdout.print("small\n", .{});
    }
}

const Point = struct {
    x: f64,
    y: f64,

    pub fn distance(self: Point) f64 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }
};
