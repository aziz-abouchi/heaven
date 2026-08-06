const std = @import("std");
const elab = @import("elab.zig");
const expr = @import("expr");

test "lambda identity type check" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const nat_type = try store.sym("Nat");
    const pi_type = try store.pi("x", nat_type, nat_type);
    const var_x = try store.sym("x");
    const lambda_id = try store.lambdaNative("x", var_x);
    
    var ctx = elab.TypingContext.init(allocator);
    defer ctx.deinit();
    
    var checker = elab.TypeChecker.init(allocator, &store);
    try checker.checkType(&ctx, lambda_id, pi_type);
}

test "application type inference" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const nat_type = try store.sym("Nat");
    const pi_type = try store.pi("x", nat_type, nat_type);
    const lambda_id = try store.lambdaNative("x", try store.sym("x"));
    const five = try store.int(5);
    const app_id = try store.apply(lambda_id, &.{five});
    
    var ctx = elab.TypingContext.init(allocator);
    defer ctx.deinit();
    
    var checker = elab.TypeChecker.init(allocator, &store);
    const result_type = try checker.inferType(&ctx, app_id);
    
    const result_node = store.get(result_type);
    try std.testing.expect(result_node.tag == .sym);
    const result_name = store.getSym(result_type) orelse return error.TestExpectedEqual;
    try std.testing.expect(std.mem.eql(u8, result_name, "Nat"));
}
