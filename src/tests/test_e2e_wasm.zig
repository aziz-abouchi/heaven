const std = @import("std");
const ast = @import("../kernel/ast.zig");
const TypeChecker = @import("../kernel/typechecker.zig").TypeChecker;
const WasmBackend = @import("../backend/wasm.zig").WasmBackend;
const WasmOpcode = @import("../backend/wasm.zig").WasmOpcode;

test "Pipeline E2E - Compilation d'un terme Heaven vers .wasm" {
    const allocator = std.testing.allocator;

    var typechecker = TypeChecker.init(allocator);
    defer typechecker.deinit();

    var backend = WasmBackend.init(allocator, &typechecker);
    defer backend.deinit();

    const type_0 = ast.Term{ .sort = .{ .type_sort = .{ .concrete = 0 } } };
    const rel_r = ast.Term{ .sort = .prop };
    const quot = ast.Term{ .quot = .{ .type_a = &type_0, .relation_r = &rel_r } };
    const var_x = ast.Term{ .variable = 0 };

    const class_x = ast.Term{
        .class = .{
            .quot_type = &quot,
            .element = &var_x,
        },
    };

    const raw_ast = ast.Term{
        .lambda = .{
            .name = "x",
            .domain = &type_0,
            .body = &class_x,
        },
    };

    // Compilation & effacement Wasm
    try backend.compileTerm(raw_ast);

    // Validation du bytecode émis
    const code = backend.code.items;
    try std.testing.expect(code.len > 0);

    // L'enveloppe 'class' est effacée : émission directe de local.get (0x20) 0
    try std.testing.expectEqual(@intFromEnum(WasmOpcode.local_get), code[0]);
    try std.testing.expectEqual(@as(u8, 0), code[1]);
}
