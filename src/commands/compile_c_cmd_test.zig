const std = @import("std");
const expr = @import("expr");
const compile_c_cmd = @import("compile_c_cmd");

fn stringLit(store: *expr.Store, value: []const u8) !expr.Id {
    return try store.lit(.{
        .str = try store.interner.intern(value),
    });
}


fn expectIntValue(store: *expr.Store, id: expr.Id, expected: i64) !void {
    const node = store.get(id);
    try std.testing.expectEqual(expr.Tag.lit, node.tag);
    try std.testing.expect(switch (store.getLit(node.aux)) {
        .int => |value| value == expected,
        else => false,
    });
}

test "compile-c lowering: HP.ELambda produit une vraie lambda" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const head = try store.sym("HP.ELambda");
    const param = try stringLit(&store, "x");
    const body = try store.sym("x");
    const hp_lambda = try store.apply(head, &.{ param, body });

    const lowered = try compile_c_cmd.lowerHpToStore(allocator, &store, hp_lambda);
    const node = store.get(lowered);

    try std.testing.expectEqual(expr.Tag.lambda, node.tag);
    try std.testing.expectEqualStrings("x", store.interner.resolve(node.payload));
    try std.testing.expectEqual(@as(u16, 1), node.span_a.len);

    const lowered_body = store.get(store.pool.items[node.span_a.start]);
    try std.testing.expectEqual(expr.Tag.sym, lowered_body.tag);
    try std.testing.expectEqualStrings("x", store.interner.resolve(lowered_body.payload));
}

test "compile-c lowering: HP.EApply préserve l'application d'une lambda" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const body = try store.sym("x");
    const lambda = try store.lambda(&.{"x"}, body);
    const arg = try store.int(42);
    const head = try store.sym("HP.EApply");
    const hp_apply = try store.apply(head, &.{ lambda, arg });

    const lowered = try compile_c_cmd.lowerHpToStore(allocator, &store, hp_apply);
    const node = store.get(lowered);

    try std.testing.expectEqual(expr.Tag.apply, node.tag);
    try std.testing.expectEqual(lambda, node.payload);
    const args = store.applyArgs(node);
    try std.testing.expectEqual(@as(usize, 1), args.len);
    try expectIntValue(&store, args[0], 42);
}

test "compile-c lowering: application native reste une application" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const func = try store.sym("f");
    const arg = try store.int(7);
    const native_apply = try store.apply(func, &.{arg});

    const lowered = try compile_c_cmd.lowerHpToStore(allocator, &store, native_apply);
    const node = store.get(lowered);

    try std.testing.expectEqual(expr.Tag.apply, node.tag);
    const lowered_func = store.get(node.payload);
    try std.testing.expectEqual(expr.Tag.sym, lowered_func.tag);
    try std.testing.expectEqualStrings("f", store.interner.resolve(lowered_func.payload));

    const args = store.applyArgs(node);
    try std.testing.expectEqual(@as(usize, 1), args.len);
    try expectIntValue(&store, args[0], 7);
}

test "compile-c lowering: application native préserve tous ses arguments" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const func = try store.sym("f");
    const arg1 = try store.int(7);
    const arg2 = try store.int(9);
    const native_apply = try store.apply(func, &.{ arg1, arg2 });

    const lowered = try compile_c_cmd.lowerHpToStore(allocator, &store, native_apply);
    const node = store.get(lowered);

    try std.testing.expectEqual(expr.Tag.apply, node.tag);
    const lowered_func = store.get(node.payload);
    try std.testing.expectEqual(expr.Tag.sym, lowered_func.tag);
    try std.testing.expectEqualStrings("f", store.interner.resolve(lowered_func.payload));

    const args = store.applyArgs(node);
    try std.testing.expectEqual(@as(usize, 2), args.len);
    try expectIntValue(&store, args[0], 7);
    try expectIntValue(&store, args[1], 9);
}

test "compile-c import: détecte les réponses en erreur" {
    try std.testing.expect(compile_c_cmd.isImportFailureMessage("✗ fichier introuvable"));
    try std.testing.expect(compile_c_cmd.isImportFailureMessage("  \t✗ cycle détecté"));
    try std.testing.expect(!compile_c_cmd.isImportFailureMessage("✓ import Inf"));
    try std.testing.expect(!compile_c_cmd.isImportFailureMessage("✓ import déjà importé"));
}
