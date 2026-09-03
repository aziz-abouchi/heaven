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

test "syntax HIR — data declaration" {
    const source =
        \\data Nat
        \\    = Zero
        \\    | Succ Nat
        \\
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var result = try lower_mod.lowerSource(
        arena.allocator(),
        source,
    );
    defer result.deinit();

    try testing.expectEqual(@as(usize, 1), result.items.len);

    switch (result.items[0]) {
        .data_decl => |data| {
            try testing.expectEqualStrings("Nat", data.name);
            try testing.expectEqual(@as(usize, 2), data.constructors.len);

            try testing.expectEqualStrings(
                "Zero",
                data.constructors[0].name,
            );

            try testing.expectEqualStrings(
                "Succ",
                data.constructors[1].name,
            );

            try testing.expectEqual(
                @as(usize, 1),
                data.constructors[1].args.len,
            );
        },
        else => return error.TestExpectedEqual,
    }
}

test "syntax HIR — theorem" {
    const source =
        \\theorem add_zero :
        \\    forall (n : Nat). Eq<Add<n,Zero>, n>
        \\
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var result = try lower_mod.lowerSource(
        arena.allocator(),
        source,
    );
    defer result.deinit();

    try testing.expectEqual(@as(usize, 1), result.items.len);

    switch (result.items[0]) {
        .theorem_decl => |thm| {
            try testing.expectEqualStrings(
                "add_zero",
                thm.name,
            );

            switch (thm.proposition) {
                .forall => |forall| {
                    try testing.expectEqual(
                        @as(usize, 1),
                        forall.binders.len,
                    );

                    try testing.expectEqualStrings(
                        "n",
                        forall.binders[0].name,
                    );
                },
                else => return error.TestExpectedEqual,
            }
        },
        else => return error.TestExpectedEqual,
    }
}
