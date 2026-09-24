const std = @import("std");
const Parser = @import("../frontend/parser.zig").Parser;
const TypeChecker = @import("../kernel/typechecker.zig").TypeChecker;

pub fn startRepl(allocator: std.mem.Allocator) !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    try stdout.print("Heaven REPL v0.1.0\nTapez :q pour quitter.\n\n", .{});

    var buf: [1024]u8 = undefined;
    while (true) {
        try stdout.print("hvn> ", .{});
        if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            const trimmed = std.mem.trim(u8, line, " \r\n");
            if (std.mem.eql(u8, trimmed, ":q")) break;
            if (trimmed.len == 0) continue;

            // Analyse et vérification de type instantanées
            if (parser.parseSource(trimmed)) |ast_term| {
                try stdout.print("AST: {v}\n", .{ast_term});
            } else |err| {
                try stdout.print("Erreur de syntaxe : {s}\n", .{@errorName(err)});
            }
        } else break;
    }
}
