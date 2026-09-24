const std = @import("std");
const testing = std.testing;
const Transformer = @import("transform.zig").Transformer;
const Term = @import("transform.zig").Term;

fn createVar(allocator: std.mem.Allocator, name: []const u8) !*Term {
    const t = try allocator.create(Term);
    t.* = .{ .kind = .{ .var_ref = name } };
    return t;
}

test "reduction iota : quot.lift f p (quot.mk T R x) -> f x" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var transformer = Transformer.init(allocator);

    // Termes de base : f, p, T, R, x
    const f = try createVar(allocator, "f");
    const p = try createVar(allocator, "p");
    const raw_type = try createVar(allocator, "Int");
    const relation = try createVar(allocator, "EqMod");
    const x = try createVar(allocator, "42");

    // Constructeur : quot.mk(Int, EqMod, 42)
    const quot_mk = try allocator.create(Term);
    quot_mk.* = .{ .kind = .{ .quot = .{ .mk = .{
        .raw_type = raw_type,
        .relation = relation,
        .value = x,
    } } } };

    // Éliminateur : quot.lift(f, p, quot.mk(...))
    const quot_lift = try allocator.create(Term);
    quot_lift.* = .{ .kind = .{ .quot = .{ .lift = .{
        .fn_term = f,
        .proof = p,
        .arg = quot_mk,
    } } } };

    // Transformation
    const result = try transformer.transformTerm(quot_lift);

    // Vérification de la réduction vers (f 42)
    try testing.expectEqual(result.kind, .app);
    try testing.expectEqualStrings(result.kind.app.func.kind.var_ref, "f");
    try testing.expectEqualStrings(result.kind.app.arg.kind.var_ref, "42");
}

test "pas de reduction iota si l'argument n'est pas un quot.mk" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var transformer = Transformer.init(allocator);

    const f = try createVar(allocator, "f");
    const p = try createVar(allocator, "p");
    const opaque_arg = try createVar(allocator, "q_var");

    const quot_lift = try allocator.create(Term);
    quot_lift.* = .{ .kind = .{ .quot = .{ .lift = .{
        .fn_term = f,
        .proof = p,
        .arg = opaque_arg,
    } } } };

    const result = try transformer.transformTerm(quot_lift);

    // Le terme doit rester un quot.lift inchangé
    try testing.expectEqual(result.kind, .quot);
    try testing.expectEqual(result.kind.quot, .lift);
}
