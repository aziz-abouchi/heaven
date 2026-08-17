const std = @import("std");
const Shell = @import("init.zig").Shell;
const cmd_list = @import("commands_list.zig");
const eval = @import("eval.zig");
const commands = @import("commands.zig");
const platform = @import("platform");
const expr_mod = @import("expr");
const mlcpd_mod = @import("mlcpd");
const mlcpd_equiv_mod = @import("mlcpd_equiv");

pub fn run(self: *Shell) !void {
    // Register global heaven pointer for green threads
    @import("utils.zig").global_heaven_ptr = self.heaven;
    const stdin_fd = platform.posix.STDIN_FILENO;
    var buf: [4096]u8 = undefined;

    main_loop: while (true) {
        platform.debug.print("heaven> ", .{});
        const bytes_read = platform.posix.read(stdin_fd, &buf) catch break;
        if (bytes_read == 0) break;
        const raw = buf[0..bytes_read];

        // Traiter chaque ligne séparément
        var line_it = std.mem.splitScalar(u8, raw, '\n');
        while (line_it.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \r\t");
            if (line.len < 1) continue;

            const had_colon = line[0] == ':';
            const rest_line = if (had_colon) std.mem.trim(u8, line[1..], " ") else line;
            if (rest_line.len < 1) continue;

            var it = std.mem.tokenizeAny(u8, rest_line, " ");
            const cmd = it.next() orelse continue;
            const args = it.rest();

            // ═══════════════════════════════════════════════════
            // FUSION REPL : Interception des commandes du REPL ici
            // ═══════════════════════════════════════════════════
            if (had_colon) {
                if (std.mem.eql(u8, cmd, "equiv") or std.mem.eql(u8, cmd, "prove")) {
                    try runMlcpdEquivCommand(self, args);
                    continue;
                }
                if (std.mem.eql(u8, cmd, "history")) {
                    platform.debug.print("  (Historique non géré dans le Shell unifié)\n", .{});
                    continue;
                }
                if (std.mem.eql(u8, cmd, "defs")) {
                    platform.debug.print("  (Définitions non gérées dans le Shell unifié)\n", .{});
                    continue;
                }
                if (std.mem.eql(u8, cmd, "clear")) {
                    platform.debug.print("  (Mémoire nettoyée)\n", .{});
                    continue;
                }
                // On laisse tomber :ast et :c pour l'instant car ils nécessitent
                // le parser tree-sitter complet que le Shell n'a pas sous la main.
                // On les ajoutera quand on fera le grand nettoyage de l'élaborateur.
            }

            // ═══════════════════════════════════════════════════
            // LOGIQUE SHEELL NORMAL (Table des commandes)
            // ═══════════════════════════════════════════════════
            var found = false;
            inline for (cmd_list.commands) |cmd_def| {
                if (std.mem.eql(u8, cmd, cmd_def.name) or
                    (cmd_def.shortcut != null and std.mem.eql(u8, cmd, cmd_def.shortcut.?)))
                {
                    found = true;
                    if (comptime std.mem.eql(u8, cmd_def.name, "exit")) {
                        platform.debug.print("[HEAVEN] Arrêt du noyau.\n", .{});
                        break :main_loop;
                    } else if (comptime std.mem.eql(u8, cmd_def.name, "run*")) {
                        commands.cmdRunStar(self, args, 20);
                    } else if (comptime std.mem.eql(u8, cmd_def.name, "load")) {
                        if (args.len > 0) {
                            const result = commands.cmdLoadFile(self, args) catch |err| {
                                platform.debug.print("Error loading file: {}\n", .{err});
                                continue;
                            };
                            defer self.allocator.free(result);
                            platform.debug.print("{s}\n", .{result});
                        } else {
                            platform.debug.print("Usage: load <file.hvn>\n", .{});
                        }
                    } else {
                        const func = @field(commands, cmd_def.method);
                        const info = @typeInfo(@TypeOf(func));
                        if (info.@"fn".params.len == 1) {
                            func(self);
                        } else {
                            func(self, args);
                        }
                    }
                }
            }

            if (!found) {
                if (had_colon) {
                    platform.debug.print("   commande inconnue: {s}\n", .{cmd});
                } else {
                    eval.evalHeavenCode(self, line);
                }
            }
        } // end line_it
    }
}

pub fn printHelp(self: *Shell) void {
    _ = self;
    const builtin = @import("builtin");
    const is_wasm = builtin.target.cpu.arch.isWasm();
    platform.debug.print("\n═══ Commandes Disponibles ═══\n", .{});
    inline for (cmd_list.commands) |cmd| {
        const skip = switch (cmd.target) {
            .both => false,
            .native_only => is_wasm,
            .wasm_only => !is_wasm,
        };
        if (!skip) {
            if (cmd.shortcut) |short| {
                platform.debug.print("    :{s}, :{s} \t- {s}\n", .{ cmd.name, short, cmd.description });
            } else {
                platform.debug.print("    :{s}    \t- {s}\n", .{ cmd.name, cmd.description });
            }
        }
    }
    platform.debug.print("    :equiv <f1> <f2> \t- Prouve l'équivalence de 2 fichiers MLCPD JSON\n", .{});
    platform.debug.print("═════════════════════════════\n\n", .{});
}

/// Exécute la commande :equiv sur deux fichiers
fn runMlcpdEquivCommand(self: *Shell, args: []const u8) !void {
    var iter = std.mem.splitSequence(u8, args, " ");
    const file1_path = iter.next() orelse {
        platform.debug.print("Usage: :equiv <file1.json> <file2.json>\n", .{});
        return;
    };
    const file2_path = iter.next() orelse {
        platform.debug.print("Usage: :equiv <file1.json> <file2.json>\n", .{});
        return;
    };

    const allocator = self.allocator;
    var local_store = expr_mod.Store.init(allocator);
    defer local_store.deinit();

    const file1_content = platform.fs.cwd().readFileAlloc(allocator, file1_path, 10 * 1024 * 1024) catch |err| {
        platform.debug.print("Error reading {s}: {}\n", .{ file1_path, err });
        return;
    };
    defer allocator.free(file1_content);

    const file2_content = platform.fs.cwd().readFileAlloc(allocator, file2_path, 10 * 1024 * 1024) catch |err| {
        platform.debug.print("Error reading {s}: {}\n", .{ file2_path, err });
        return;
    };
    defer allocator.free(file2_content);

    var parsed1 = mlcpd_mod.parseMlcpdJson(allocator, file1_content) catch |err| {
        platform.debug.print("Error parsing {s}: {}\n", .{ file1_path, err });
        return;
    };
    defer parsed1.deinit();
    parsed1.normalizeParsedFile();

    var parsed2 = mlcpd_mod.parseMlcpdJson(allocator, file2_content) catch |err| {
        platform.debug.print("Error parsing {s}: {}\n", .{ file2_path, err });
        return;
    };
    defer parsed2.deinit();
    parsed2.normalizeParsedFile();

    const ir1 = parsed1.toExprIr(&local_store) catch |err| {
        platform.debug.print("Error IR {s}: {}\n", .{ file1_path, err });
        return;
    };
    const ir2 = parsed2.toExprIr(&local_store) catch |err| {
        platform.debug.print("Error IR {s}: {}\n", .{ file2_path, err });
        return;
    };

    var result = mlcpd_equiv_mod.proveEquivalence(allocator, &local_store, ir1, ir2) catch |err| {
        platform.debug.print("Échec de la preuve: {}\n", .{err});
        return;
    };
    defer result.deinit(allocator);

    if (result.equivalent) {
        platform.debug.print("EQUIVALENT! (Stratégie: {s})\n", .{@tagName(result.strategy)});
    } else {
        platform.debug.print("❌ NOT EQUIVALENT.\n", .{});
    }
}
