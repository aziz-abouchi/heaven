const std = @import("std");
const ast = @import("ast.zig");
const TypeChecker = @import("typechecker.zig").TypeChecker;

test "Règle Pi - Type_0 -> Type_1 donne Type_1" {
    const allocator = std.testing.allocator;
    var tc = TypeChecker.init(allocator);
    defer tc.deinit();

    // On déclare dans le contexte : A : Type_0, B : Type_1
    try tc.context.append(allocator, ast.Term{ .sort = .{ .type_sort = .{ .concrete = 0 } } }); // idx 1 (A)
    try tc.context.append(allocator, ast.Term{ .sort = .{ .type_sort = .{ .concrete = 1 } } }); // idx 0 (B)

    const term_a = ast.Term{ .variable = 1 }; // A : Type_0
    const term_b = ast.Term{ .variable = 1 }; // B : Type_1 (dans le contexte étendu avec x:A)

    const sort_res = try tc.inferPi(term_a, term_b);

    try std.testing.expect(sort_res == .type_sort);
    try std.testing.expectEqual(@as(?u32, 1), sort_res.type_sort.getConcrete());
}

test "Règle Pi - Imprédicativité de Prop (Type_1 -> Prop donne Prop)" {
    const allocator = std.testing.allocator;
    var tc = TypeChecker.init(allocator);
    defer tc.deinit();

    // On déclare dans le contexte : A : Type_1, P : Prop
    try tc.context.append(allocator, ast.Term{ .sort = .{ .type_sort = .{ .concrete = 1 } } }); // idx 1 (A)
    try tc.context.append(allocator, ast.Term{ .sort = .prop }); // idx 0 (P)

    const term_a = ast.Term{ .variable = 1 }; // A : Type_1
    const term_p = ast.Term{ .variable = 1 }; // P : Prop (dans le contexte étendu avec x:A)

    const sort_res = try tc.inferPi(term_a, term_p);

    try std.testing.expect(sort_res == .prop);
}
