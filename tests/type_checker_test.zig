const std = @import("std");
const elab = @import("elab");
const expr = @import("expr");
const platform = @import("platform");

test "lambda identity type check" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    // Create Nat type
    const nat_type = try store.sym("Nat");

    // Create Π(x:Nat).Nat
    const pi_type = try store.pi("x", nat_type, nat_type);

    // Create λx.x (identity function)
    const var_x = try store.sym("x");
    const lambda_id = try store.lambdaNative("x", var_x);

    // Type check: λx.x should have type Π(x:Nat).Nat
    var ctx = elab.TypingContext.init(allocator);
    defer ctx.deinit();

    var checker = elab.TypeChecker.init(allocator, &store);
    try checker.checkType(&ctx, lambda_id, pi_type);

    platform.debug.print("✓ Identity function type checks successfully!\n", .{});
}

test "application type inference" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    // Create Nat type
    const nat_type = try store.sym("Nat");

    // Create Π(x:Nat).Nat
    const pi_type = try store.pi("x", nat_type, nat_type);
    _ = pi_type;

    // Create λx.x
    const var_x = try store.sym("x");
    const lambda_id = try store.lambdaNative("x", var_x);

    // Create a literal 5 : Nat
    const five = try store.int(5);

    // Create application (λx.x) 5
    const app_id = try store.apply(lambda_id, &.{five});

    // Infer type: should be Nat
    var ctx = elab.TypingContext.init(allocator);
    defer ctx.deinit();

    var checker = elab.TypeChecker.init(allocator, &store);
    const result_type = try checker.inferType(&ctx, app_id);

    // Verify result is Nat
    const result_node = store.get(result_type);
    if (result_node.tag != .sym) return error.TypeMismatch;
    const result_name = store.getSym(result_type) orelse return error.TypeMismatch;
    if (!std.mem.eql(u8, result_name, "Nat")) return error.TypeMismatch;

    platform.debug.print("✓ Application type inference works!\n", .{});
}
