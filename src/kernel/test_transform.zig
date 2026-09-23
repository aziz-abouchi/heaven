const std = @import("std");
const ast = @import("ast.zig");
const Transformer = @import("transform.zig").Transformer;

test "Transformation AST - Récursion complète sur Lambda et Quotients" {
    const allocator = std.testing.allocator;
    var transformer = Transformer.init(allocator);

    // λ(x : Type_0). class(Quot(Type_0, R), x)
    const type_0 = ast.Term{ .sort = .{ .type_sort = .{ .concrete = 0 } } };
    const rel_r = ast.Term{ .sort = .prop };

    const quot = ast.Term{
        .quot = .{
            .type_a = &type_0,
            .relation_r = &rel_r,
        },
    };

    const var_x = ast.Term{ .variable = 0 };
    const class_elem = ast.Term{
        .class = .{
            .quot_type = &quot,
            .element = &var_x,
        },
    };

    const lam = ast.Term{
        .lambda = .{
            .name = "x",
            .domain = &type_0,
            .body = &class_elem,
        },
    };

    var transformed = try transformer.transformTerm(lam);
    defer transformer.destroyTerm(&transformed);

    try std.testing.expect(transformed == .lambda);
    try std.testing.expect(transformed.lambda.body.* == .class);
    try std.testing.expect(transformed.lambda.body.*.class.quot_type.* == .quot);
}
