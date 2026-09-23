const std = @import("std");
const ast = @import("ast.zig");
const TypeChecker = @import("typechecker.zig").TypeChecker;
const Conversion = @import("conversion.zig").Conversion;

test "Proof Irrelevance - Deux preuves distinctes dans Prop sont egales" {
    const allocator = std.testing.allocator;
    var tc = TypeChecker.init(allocator);
    defer tc.deinit();

    var conv = Conversion.init(allocator, &tc);

    // Contexte : P : Prop (items[0]), p1 : P (items[1]), p2 : P (items[2])
    try tc.context.append(allocator, ast.Term{ .sort = .prop });

    // Dans un contexte de taille 3, P (items[0]) correspond à variable = 2
    const term_p = ast.Term{ .variable = 2 };
    try tc.context.append(allocator, term_p); // p1 : P
    try tc.context.append(allocator, term_p); // p2 : P

    const proof1 = ast.Term{ .variable = 1 }; // p1
    const proof2 = ast.Term{ .variable = 0 }; // p2

    // p1 et p2 ont des variables différentes mais habitent Prop -> ÉGAUX
    const is_equal = try conv.areEqual(proof1, proof2);
    try std.testing.expect(is_equal);
}

test "Non-Proof Irrelevance - Deux elements distincts dans Type_0 restent differents" {
    const allocator = std.testing.allocator;
    var tc = TypeChecker.init(allocator);
    defer tc.deinit();

    var conv = Conversion.init(allocator, &tc);

    // Contexte : A : Type_0 (items[0]), a1 : A (items[1]), a2 : A (items[2])
    try tc.context.append(allocator, ast.Term{ .sort = .{ .type_sort = .{ .concrete = 0 } } });

    const term_a = ast.Term{ .variable = 2 };
    try tc.context.append(allocator, term_a); // a1 : A
    try tc.context.append(allocator, term_a); // a2 : A

    const elem1 = ast.Term{ .variable = 1 }; // a1
    const elem2 = ast.Term{ .variable = 0 }; // a2

    // a1 et a2 habitent Type_0 -> DIFFÉRENTS
    const is_equal = try conv.areEqual(elem1, elem2);
    try std.testing.expect(!is_equal);
}
