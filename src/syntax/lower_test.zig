const std = @import("std");
const testing = std.testing;

const lower_mod = @import("lower");

test "syntax HIR — equation" {
    const source =
        "add zero n = n\n";

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var result = try lower_mod.lowerSource(arena.allocator(), source);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 1), result.items.len);

    switch (result.items[0]) {
        .equation => |eq| {
            try testing.expectEqualStrings("add", eq.name);
            try testing.expectEqual(@as(usize, 2), eq.patterns.len);

            switch (eq.body) {
                .identifier => |name| {
                    try testing.expectEqualStrings("n", name);
                },
                else => return error.TestExpectedEqual,
            }
        },
        else => return error.TestExpectedEqual,
    }
}
