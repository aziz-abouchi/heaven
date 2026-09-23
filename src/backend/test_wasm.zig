const std = @import("std");
const ast = @import("../kernel/ast.zig");
const WasmBackend = @import("wasm.zig").WasmBackend;
const WasmOpcode = @import("wasm.zig").WasmOpcode;

test "WasmBackend - Effacement des quotients et émission bytecode" {
    const allocator = std.testing.allocator;
    var backend = WasmBackend.init(allocator, null);
    defer backend.deinit();

    // Variable index 2
    const var_2 = ast.Term{ .variable = 2 };

    // class(var_2) doit s'effacer et émettre uniquement local.get 2
    const type_0 = ast.Term{ .sort = .{ .type_sort = .{ .concrete = 0 } } };
    const rel_r = ast.Term{ .sort = .prop };
    const quot = ast.Term{ .quot = .{ .type_a = &type_0, .relation_r = &rel_r } };

    const class_elem = ast.Term{
        .class = .{
            .quot_type = &quot,
            .element = &var_2,
        },
    };

    try backend.compileTerm(class_elem);

    // Vérification du bytecode généré : [local.get (0x20), index (0x02)]
    try std.testing.expectEqual(@as(usize, 2), backend.code.items.len);
    try std.testing.expectEqual(@intFromEnum(WasmOpcode.local_get), backend.code.items[0]);
    try std.testing.expectEqual(@as(u8, 2), backend.code.items[1]);
}

test "WasmBackend - Effacement de la preuve dans lift(f, p)" {
    const allocator = std.testing.allocator;
    var backend = WasmBackend.init(allocator, null);
    defer backend.deinit();

    const func = ast.Term{ .variable = 1 };
    const proof = ast.Term{ .variable = 99 }; // Preuve fictive à ignorer

    const type_0 = ast.Term{ .sort = .{ .type_sort = .{ .concrete = 0 } } };
    const rel_r = ast.Term{ .sort = .prop };
    const quot = ast.Term{ .quot = .{ .type_a = &type_0, .relation_r = &rel_r } };

    const lift_term = ast.Term{
        .lift = .{
            .quot_type = &quot,
            .target_b = &type_0,
            .func_f = &func,
            .proof = &proof,
        },
    };

    try backend.compileTerm(lift_term);

    // Seule la fonction (variable 1) doit être émise, la preuve (variable 99) est effacée
    try std.testing.expectEqual(@as(usize, 2), backend.code.items.len);
    try std.testing.expectEqual(@intFromEnum(WasmOpcode.local_get), backend.code.items[0]);
    try std.testing.expectEqual(@as(u8, 1), backend.code.items[1]);
}
