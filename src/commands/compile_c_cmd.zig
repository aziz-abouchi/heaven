const std = @import("std");
const platform = @import("platform");
const heaven_expr = @import("heaven_expr");

pub fn runCompileC(allocator: std.mem.Allocator, src_path: []const u8, out_path: []const u8) !void {
    // 1. Lire le fichier source .hvn
    const file = platform.fs.cwd().openFile(src_path, .{}) catch |err| {
        platform.debug.print("Erreur : impossible d'ouvrir {s} ({})\n", .{ src_path, err });
        return err;
    };
    defer file.close();
    const src_code = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(src_code);

    // 2. Initialiser Heaven
    var heaven = try heaven_expr.Heaven.init(allocator);
    defer heaven.deinit();

    // 3. Importer les modules auto-hébergés
    _ = heaven.eval("import \"lib/parse/infix.hvn\" as Inf") catch {};
    _ = heaven.eval("import \"lib/codegen/c.hvn\" as CG") catch {};

    // 4. Parser l'expression infixe vers l'AST
    const parse_cmd = try std.fmt.allocPrint(allocator, "Inf.parse_infix \"{s}\"", .{src_code});
    defer allocator.free(parse_cmd);
    const ast = try heaven.eval(parse_cmd);

    // 5. Générer le code C depuis l'AST
    const gen_cmd = try std.fmt.allocPrint(allocator, "CG.emit_c_program ({s})", .{ast});
    defer allocator.free(gen_cmd);
    var c_code = try heaven.eval(gen_cmd);

    if (c_code.len >= 2 and c_code[0] == '"' and c_code[c_code.len - 1] == '"') {
        c_code = c_code[1 .. c_code.len - 1];
    }

    // 6. Écrire le C temporaire et compiler avec gcc
    const tmp_c_path = "/tmp/heaven_gen.c";
    const tmp_file = try platform.fs.cwd().createFile(tmp_c_path, .{});
    try tmp_file.writeAll(c_code);
    tmp_file.close();

    var child = std.process.Child.init(&[_][]const u8{ "gcc", "-O2", tmp_c_path, "-o", out_path }, allocator);
    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                platform.debug.print("Erreur lors de la compilation avec gcc (code {d}).\n", .{code});
                return error.CompilationFailed;
            }
        },
        else => {
            platform.debug.print("Erreur lors de la compilation avec gcc.\n", .{});
            return error.CompilationFailed;
        },
    }

    platform.debug.print("✓ Binaire natif généré avec succès : {s}\n", .{out_path});
}
