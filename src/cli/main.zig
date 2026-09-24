const std = @import("std");
const Parser = @import("../frontend/parser.zig").Parser;
const EGraph = @import("../opt/egraph.zig").EGraph;
const WasmBackend = @import("../backend/wasm.zig").WasmBackend;
const Guppy = @import("../pkg/guppy.zig").Guppy;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        usage();
        return;
    }

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "build")) {
        try buildFile(allocator, args[2..]);
    } else if (std.mem.eql(u8, cmd, "run")) {
        try runFile(allocator, args[2..]);
    } else if (std.mem.eql(u8, cmd, "pkg")) {
        try Guppy.handleCli(allocator, args[2..]);
    } else {
        usage();
    }
}

fn usage() void {
    std.debug.print(
        \\Heaven Compiler (hvn) & Package Manager (guppy)
        \\Usage:
        \\  hvn build <file.hvn> [-o out.wasm]
        \\  hvn run   <file.hvn>
        \\  hvn pkg   <init|fetch|add <url>>
        \\
    , .{});
}

fn buildFile(allocator: std.mem.Allocator, args: [][]const u8) !void {
    if (args.len < 1) return error.MissingInputFile;
    const input_path = args[0];

    // 1. Parsing Tree-sitter
    const source = try std.fs.cwd().readFileAllocOptions(allocator, input_path, 1024 * 1024, null, @alignOf(u8), 0);
    defer allocator.free(source);

    var parser = try Parser.init(allocator);
    defer parser.deinit();
    const ast_root = try parser.parseSource(source);

    // 2. Optimization E-Graph (Equality Saturation)
    var egraph = EGraph.init(allocator);
    defer egraph.deinit();
    const opt_ast = try egraph.optimize(ast_root);

    // 3. Backend Wasm
    var backend = WasmBackend.init(allocator, null);
    defer backend.deinit();
    const wasm_bytes = try backend.emitFullModule(opt_ast);
    defer allocator.free(wasm_bytes);

    // Write output
    try std.fs.cwd().makePath("zig-out");
    try std.fs.cwd().writeFile(.{ .sub_path = "zig-out/main.wasm", .data = wasm_bytes });
    std.debug.print("Compilé avec succès -> zig-out/main.wasm\n", .{});
}

fn runFile(allocator: std.mem.Allocator, args: [][]const u8) !void {
    try buildFile(allocator, args);
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "node", "-e",
            \\const fs = require('fs');
            \\const bytes = fs.readFileSync('zig-out/main.wasm');
            \\WebAssembly.instantiate(bytes).then(obj => {
            \\    console.log("Résultat:", obj.instance.exports.main());
            \\});
        },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    std.debug.print("{s}", .{result.stdout});
}
