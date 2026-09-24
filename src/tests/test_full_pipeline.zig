const std = @import("std");
const ast = @import("../kernel/ast.zig");
const WasmBackend = @import("../backend/wasm.zig").WasmBackend;

test "Pipeline Intégral : Code .hvn vers .wasm et exécution via Node.js" {
    const allocator = std.testing.allocator;

    var backend = WasmBackend.init(allocator, null);
    defer backend.deinit();

    // Directement instancier le terme
    const dummy_term = ast.Term{ .variable = 42 };

    const full_wasm = try backend.emitFullModule(dummy_term);
    defer allocator.free(full_wasm);

    // Création explicite du dossier de sortie s'il n'existe pas encore
    try std.fs.cwd().makePath("zig-out");

    const wasm_path = "zig-out/run_test.wasm";
    try std.fs.cwd().writeFile(.{
        .sub_path = wasm_path,
        .data = full_wasm,
    });
    defer std.fs.cwd().deleteFile(wasm_path) catch {};

    const runner_script =
        \\const fs = require('fs');
        \\const bytes = fs.readFileSync('zig-out/run_test.wasm');
        \\WebAssembly.instantiate(bytes).then(obj => {
        \\    const res = obj.instance.exports.main();
        \\    if (res !== 42) process.exit(1);
        \\}).catch(err => {
        \\    console.error(err);
        \\    process.exit(1);
        \\});
    ;

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "node", "-e", runner_script },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);
}
