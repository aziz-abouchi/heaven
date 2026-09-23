const std = @import("std");
const ast = @import("ast.zig");
const TypeChecker = @import("typechecker.zig").TypeChecker;

test "Types Quotients - Quot(A, R) conserve l'univers de A" {
    const allocator = std.testing.allocator;
    var tc = TypeChecker.init(allocator);
    defer tc.deinit();

    // On ajoute dans le contexte : A : Type_0 (items[0])
    try tc.context.append(allocator, ast.Term{ .sort = .{ .type_sort = .{ .concrete = 0 } } });

    // A est la variable De Bruijn 0 (de type Type_0)
    const term_a = ast.Term{ .variable = 0 };
    // R (relation fictive)
    const rel_r = ast.Term{ .sort = .prop };

    const quot_term = ast.Term{
        .quot = .{
            .type_a = &term_a,
            .relation_r = &rel_r,
        },
    };

    const inferred = try tc.infer(quot_term);
    try std.testing.expect(inferred == .sort);
    try std.testing.expectEqual(@as(?u32, 0), inferred.sort.type_sort.getConcrete());
}
