const std = @import("std");
const Shell = @import("init.zig").Shell;
const cmd_list = @import("commands_list.zig");
const eval = @import("eval.zig");
const commands = @import("commands.zig");
const platform = @import("platform");
const expr_mod = @import("expr");
const mlcpd_mod = @import("mlcpd");
const mlcpd_equiv_mod = @import("mlcpd_equiv");
const history_mod = @import("history.zig");
const interactive = @import("interactive.zig");

pub fn run(self: *Shell) !void {
    @import("utils.zig").global_heaven_ptr = self.heaven;

    var history = history_mod.History.init(self.allocator, 100);
    defer history.deinit();

    const history_path = try std.fs.path.join(self.allocator, &[_][]const u8{ "." });
    defer self.allocator.free(history_path);
    const history_file = try std.fs.path.join(self.allocator, &[_][]const u8{ history_path, ".heaven_history" });
    defer self.allocator.free(history_file);
    history.loadFromFile(history_file) catch {};

    var reader = try interactive.Reader.init(self.allocator, self.heaven, &history);
    defer reader.deinit();

    outer: while (true) {
        const line = reader.readLine("heaven> ") catch |err| {
            if (err == error.EndOfStream) break;
            platform.debug.print("Erreur de lecture : {}\n", .{err});
            continue;
        };
        if (line.len == 0) continue;

        // Commande !n
        if (line.len > 1 and line[0] == '!') {
            const num_str = line[1..];
            const num = std.fmt.parseInt(usize, num_str, 10) catch {
                platform.debug.print("  Syntaxe : !<numéro> (ex: !3)\n", .{});
                continue;
            };
            if (num == 0 or num > history.items.items.len) {
                platform.debug.print("  Commande historique {d} introuvable\n", .{num});
                continue;
            }
            const cmd = history.items.items[num - 1];
            platform.debug.print("{s}\n", .{cmd});
            if (!try processLine(self, cmd, &history)) break :outer;
            continue;
        }

        // Stocker dans l'historique (sauf commandes spéciales)
        if (line[0] != ':') {
            try history.push(line);
        }

        // Traiter la ligne
        if (!try processLine(self, line, &history)) break :outer;
    }

    history.saveToFile(history_file) catch {};
}

fn processLine(self: *Shell, line: []const u8, history: *history_mod.History) !bool {
    const had_colon = line[0] == ':';
    const rest_line = if (had_colon) std.mem.trim(u8, line[1..], " ") else line;
    if (rest_line.len < 1) return true;

    var it = std.mem.tokenizeAny(u8, rest_line, " ");
    const cmd = it.next() orelse return true;
    const args = it.rest();

    if (had_colon) {
        // ─── QUITTER ───
        if (std.mem.eql(u8, cmd, "q") or std.mem.eql(u8, cmd, "quit")) {
            return false;
        }
        if (std.mem.eql(u8, cmd, "history")) {
            for (history.items.items, 0..) |item, i| {
                platform.debug.print("{d}: {s}\n", .{ i+1, item });
            }
            return true;
        }
        if (std.mem.eql(u8, cmd, "save-history")) {
            // déjà sauvegardé à la sortie
            platform.debug.print("  Historique sauvegardé dans .heaven_history\n", .{});
            return true;
        }
        if (std.mem.eql(u8, cmd, "equiv") or std.mem.eql(u8, cmd, "prove")) {
            try runMlcpdEquivCommand(self, args);
            return true;
        }
        if (std.mem.eql(u8, cmd, "defs")) {
            platform.debug.print("  (Définitions non gérées)\n", .{});
            return true;
        }
        if (std.mem.eql(u8, cmd, "clear")) {
            platform.debug.print("  (Mémoire nettoyée)\n", .{});
            return true;
        }
        if (std.mem.eql(u8, cmd, "complete")) {
            eval.cmdComplete(self, args);
            return true;
        }
        // Commande inconnue
        platform.debug.print("   commande inconnue: {s}\n", .{cmd});
        return true;
    }

    // Commandes natives
    var found = false;
    inline for (cmd_list.commands) |cmd_def| {
        if (std.mem.eql(u8, cmd, cmd_def.name) or
            (cmd_def.shortcut != null and std.mem.eql(u8, cmd, cmd_def.shortcut.?)))
        {
            found = true;
            if (comptime std.mem.eql(u8, cmd_def.name, "exit")) {
                platform.debug.print("[HEAVEN] Arrêt du noyau.\n", .{});
                // On sortira par le haut
                return false;
            } else if (comptime std.mem.eql(u8, cmd_def.name, "run*")) {
                commands.cmdRunStar(self, args, 20);
            } else if (comptime std.mem.eql(u8, cmd_def.name, "load")) {
                if (args.len > 0) {
                    const result = commands.cmdLoadFile(self, args) catch |err| {
                        platform.debug.print("Error loading file: {}\n", .{err});
                        return true;
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
        if (std.mem.startsWith(u8, line, "(simplify ")) {
            const inner = line["(simplify ".len .. line.len - 1];
            eval.exprSimplify(self, inner);
            return true;
        }
        eval.evalHeavenCode(self, line);
    }
    return true;
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
    platform.debug.print("    !<num> \t- Répète une commande de l'historique\n", .{});
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