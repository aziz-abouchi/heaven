const std = @import("std");
const platform = @import("platform");

pub fn runRun(alloc: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) return error.ExecutionFailed;

    // Relance le binaire courant avec --eval-file : evalue le fichier
    // et affiche le resultat de la derniere expression. Isole le fichier
    // dans un sous-processus (panic/abort = echec local).
    const exe_path = try std.fs.selfExePathAlloc(alloc);
    defer alloc.free(exe_path);

    const result = try platform.spawnProcess(alloc, &.{ exe_path, "--eval-file", args[0] });
    if (result.exit_code != 0) {
        return error.ExecutionFailed;
    }
}
