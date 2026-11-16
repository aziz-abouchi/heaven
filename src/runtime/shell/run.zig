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

    const history_path = try std.fs.path.join(self.allocator, &[_][]const u8{"."});
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
        defer self.allocator.free(line);
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

        // ─── Mode preuve interactif : `prove X by {` sans `}` sur la ligne ───
        {
            const check: []const u8 = if (line.len > 0 and line[0] == ':') line[1..] else line;
            const check_t = std.mem.trim(u8, check, " \t");
            if (std.mem.startsWith(u8, check_t, "prove ") and
                std.mem.indexOf(u8, check_t, " by {") != null and
                std.mem.lastIndexOfScalar(u8, check_t, '}') == null)
            {
                try runProofInteractive(self, &reader, check_t);
                continue :outer;
            }
        }

        // Continuation multiligne (parenthèses ouvertes ou fin par =, in, then, else, ->)
        if (isIncompleteInput(line)) {
            var buf = std.ArrayListUnmanaged(u8){};
            defer buf.deinit(self.allocator);
            try buf.appendSlice(self.allocator, line);
            while (isIncompleteInput(buf.items)) {
                const cont = reader.readLine("... ") catch |err| {
                    if (err == error.EndOfStream) break;
                    return err;
                };
                defer self.allocator.free(cont);
                const cont_t = std.mem.trim(u8, cont, " \t\r");
                if (cont_t.len == 0) break;
                try buf.append(self.allocator, ' ');
                try buf.appendSlice(self.allocator, cont_t);
            }
            if (!try processLine(self, buf.items, &history)) break :outer;
            continue :outer;
        }

        // Traiter la ligne
        if (!try processLine(self, line, &history)) break :outer;
    }

    history.saveToFile(history_file) catch {};
}

fn runProofInteractive(
    self: *Shell,
    reader: *interactive.Reader,
    line: []const u8,
) !void {
    // Extrait `<name>` de `prove <name> by {`
    const by_pos = std.mem.indexOf(u8, line, " by {") orelse return;
    const name = std.mem.trim(u8, line["prove ".len..by_pos], " \t");
    if (name.len == 0) {
        platform.debug.print("  Usage : prove <nom> by {{\n", .{});
        return;
    }

    const session = self.heaven.startProof(name) catch |err| {
        platform.debug.print("  impossible de démarrer la preuve : {}\n", .{err});
        return;
    };
    defer session.deinit();

    const initial = session.pp() catch null;
    if (initial) |pp| {
        defer self.allocator.free(pp);
        platform.debug.print("{s}", .{pp});
    }
    platform.debug.print("(tactiques : simplify, reflexivity, induction x, rewrite H, ...)\n", .{});
    platform.debug.print("Tapez '}}' ou 'qed' pour valider, 'abort' pour annuler.\n", .{});

    while (true) {
        const tactic_line = reader.readLine("> ") catch |err| {
            if (err == error.EndOfStream) {
                platform.debug.print("\n✗ EOF, preuve abandonnée.\n", .{});
                return;
            }
            platform.debug.print("  erreur de lecture : {}\n", .{err});
            return;
        };
        defer self.allocator.free(tactic_line);
        const trimmed = std.mem.trim(u8, tactic_line, " \t\r\n");
        if (trimmed.len == 0) continue;

        if (std.mem.eql(u8, trimmed, "}") or std.mem.eql(u8, trimmed, "qed")) {
            if (try session.finish()) {
                platform.debug.print("✓ [{s}] proved (interactive)\n", .{name});
            } else {
                platform.debug.print("✗ preuve incomplète.\n", .{});
            }
            return;
        }
        if (std.mem.eql(u8, trimmed, "abort")) {
            platform.debug.print("✗ preuve abandonnée.\n", .{});
            return;
        }

        const report = session.applyLine(trimmed) catch |err| {
            platform.debug.print("  erreur : {}\n", .{err});
            continue;
        };
        defer self.allocator.free(report);
        platform.debug.print("{s}", .{report});
    }
}

/// Détecte une équation / définition : un `=` à depth 0 qui n'est pas
/// un opérateur de comparaison (`==`, `!=`, `<=`, `>=`).
/// Utilisé pour éviter que `c x = 1` soit intercepté par la commande
/// courte `c`, ou `io x = ...` par `:io`.
fn hasTopLevelEqual(line: []const u8) bool {
    var depth: usize = 0;
    var in_str = false;
    for (line, 0..) |ch, i| {
        if (in_str) {
            if (ch == '"') in_str = false;
            continue;
        }
        switch (ch) {
            '"' => in_str = true,
            '(', '[', '{' => depth += 1,
            ')', ']', '}' => if (depth > 0) { depth -= 1; },
            '=' => {
                if (depth != 0) continue;
                // Rejette ==, !=, <=, >= (comparaisons).
                const prev: u8 = if (i > 0) line[i - 1] else 0;
                const next: u8 = if (i + 1 < line.len) line[i + 1] else 0;
                if (prev == '=' or prev == '!' or prev == '<' or prev == '>') continue;
                if (next == '=') continue;
                return true;
            },
            else => {},
        }
    }
    return false;
}

/// Vrai si la ligne commence par un identifiant qui correspond à une
/// fonction déjà enregistrée dans `engine.fns` (via équation `f x = ...`)
/// ou à un nom qualifié `M.foo` importé. Sert à ne PAS router
/// `c 5` vers la commande `c` si `c` a été défini comme fonction.
fn isCallToKnownFn(self: *Shell, line: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, line, " \t");
    const first = it.next() orelse return false;
    if (first.len == 0) return false;

    // Cas `M.foo` : la clé exacte est dans engine.fns.
    if (self.heaven.engine.fns.get(first) != null) return true;

    // Cas `f(...)` collé : on re-découpe à la parenthèse.
    if (std.mem.indexOfScalar(u8, first, '(')) |pos| {
        if (pos > 0) {
            const head = first[0..pos];
            if (self.heaven.engine.fns.get(head) != null) return true;
        }
    }
    return false;
}

fn processLine(self: *Shell, line: []const u8, history: *history_mod.History) !bool {
    // Commandes Prolog : `?- goal`
    {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (std.mem.startsWith(u8, trimmed, "?- ")) {
            const goal_str = std.mem.trim(u8, trimmed["?- ".len..], " \t");
            if (self.prolog.parseAtom(goal_str)) |atom| {
                var solutions = self.prolog.solve(atom, self.allocator);
                defer solutions.deinit(self.allocator);
                if (solutions.items.len == 0) {
                    platform.debug.print("false.\n", .{});
                } else {
                    for (solutions.items) |sub| {
                        sub.printClean();
                        platform.debug.print("\n", .{});
                    }
                }
            } else {
                platform.debug.print("parse error\n", .{});
            }
            return true;
        }
    }

    const had_colon = line[0] == ':';
    const rest_line = if (had_colon) std.mem.trim(u8, line[1..], " ") else line;
    if (rest_line.len < 1) return true;

    var it = std.mem.tokenizeAny(u8, rest_line, " ");
    var cmd = it.next() orelse return true;
    var args = it.rest();

    // Cas `cmd(...)` collés : `rewrite(x, y)` arrive en un seul token
    // "rewrite(x,". On re-découpe à la première parenthèse pour que
    // cmd="rewrite" et args="(x, y)".
    if (std.mem.indexOfScalar(u8, cmd, '(')) |paren_pos| {
        if (paren_pos > 0) {
            args = rest_line[paren_pos..];
            cmd = rest_line[0..paren_pos];
        }
    }

    if (had_colon) {
        // ─── QUITTER ───
        if (std.mem.eql(u8, cmd, "q") or std.mem.eql(u8, cmd, "quit")) {
            return false;
        }
        if (std.mem.eql(u8, cmd, "history")) {
            for (history.items.items, 0..) |item, i| {
                platform.debug.print("{d}: {s}\n", .{ i + 1, item });
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
        // Fallthrough : pas un cas spécial à colon, on laisse la
        // boucle table-driven ci-dessous le traiter (hole, refine, io,
        // help, stats, etc.).
    }

    // Commandes natives.
    // On ne cherche une commande QUE si ce n'est pas une équation.
    // Sinon `c x = 1`, `io x = ...`, `ask y = ...`, etc. seraient
    // interceptés par les commandes courtes (c, io, ask, ...).
    var found = false;
    const is_equation = !had_colon and hasTopLevelEqual(rest_line);
    const is_fn_call  = !had_colon and !is_equation and isCallToKnownFn(self, rest_line);
    if (!is_equation and !is_fn_call) {
    inline for (cmd_list.commands) |cmd_def| {
        // Le nom complet matche avec ou sans `:`.
        // Le raccourci ne matche QUE préfixé par `:` — sinon `f x = x + 1`
        // serait intercepté par le raccourci `f` de `:fact`, et `s x = ...`
        // par `:s` (stats). C'est la source du bug où l'équation perdait
        // son nom (le shell routait vers la commande au lieu d'evalEquation).
        const matches_name = std.mem.eql(u8, cmd, cmd_def.name);
        const matches_shortcut = had_colon and
            cmd_def.shortcut != null and
            std.mem.eql(u8, cmd, cmd_def.shortcut.?);
        if (matches_name or matches_shortcut) {
            found = true;
            if (comptime std.mem.eql(u8, cmd_def.name, "exit")) {
                platform.debug.print("[HEAVEN] Arrêt du noyau.\n", .{});
                // On sortira par le haut
                return false;
            } else if (comptime std.mem.eql(u8, cmd_def.name, "run*")) {
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
    const is_wasm = platform.target.is_wasm;
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

fn isIncompleteInput(text: []const u8) bool {
    const trimmed = std.mem.trimRight(u8, text, " \t\r\n");
    if (trimmed.len == 0) return false;
    if (trimmed[0] == ':') return false;

    var paren: i32 = 0;
    var brace: i32 = 0;
    var bracket: i32 = 0;
    var in_str = false;
    var escape = false;

    for (trimmed) |c| {
        if (in_str) {
            if (escape) {
                escape = false;
            } else if (c == '\\') {
                escape = true;
            } else if (c == '"') {
                in_str = false;
            }
            continue;
        }
        switch (c) {
            '"' => in_str = true,
            '(' => paren += 1,
            ')' => paren -= 1,
            '{' => brace += 1,
            '}' => brace -= 1,
            '[' => bracket += 1,
            ']' => bracket -= 1,
            else => {},
        }
    }

    if (in_str or paren > 0 or brace > 0 or bracket > 0) return true;

    if (std.mem.endsWith(u8, trimmed, "=") and
        !std.mem.endsWith(u8, trimmed, "==") and
        !std.mem.endsWith(u8, trimmed, "!=") and
        !std.mem.endsWith(u8, trimmed, "<=") and
        !std.mem.endsWith(u8, trimmed, ">="))
    {
        return true;
    }
    if (std.mem.endsWith(u8, trimmed, "->") or std.mem.endsWith(u8, trimmed, "=>")) return true;

    const kws = [_][]const u8{ "in", "then", "else", "do", "where", "of" };
    for (kws) |kw| {
        if (std.mem.endsWith(u8, trimmed, kw)) {
            if (trimmed.len == kw.len) return true;
            const prev = trimmed[trimmed.len - kw.len - 1];
            if (prev == ' ' or prev == '\t' or prev == '\n' or prev == ')') return true;
        }
    }
    return false;
}

// --- Tests isIncompleteInput (2026-11-16) ---

test "isIncompleteInput: simple complete = false" {
    try std.testing.expect(!isIncompleteInput("f x = 5"));
    try std.testing.expect(!isIncompleteInput("42"));
    try std.testing.expect(!isIncompleteInput("(cons 1 nil)"));
}

test "isIncompleteInput: trailing = is incomplete" {
    try std.testing.expect(isIncompleteInput("f x ="));
    try std.testing.expect(isIncompleteInput("hanoi n from to via ="));
}

test "isIncompleteInput: open parens is incomplete" {
    try std.testing.expect(isIncompleteInput("(cons 1"));
    try std.testing.expect(isIncompleteInput("(if x"));
    try std.testing.expect(isIncompleteInput("(foo (bar"));
}

test "isIncompleteInput: closed parens complete" {
    try std.testing.expect(!isIncompleteInput("(cons 1 (cons 2 nil))"));
    try std.testing.expect(!isIncompleteInput("(foo (bar) baz)"));
}

test "isIncompleteInput: comparison operators not confused" {
    try std.testing.expect(!isIncompleteInput("x == y"));
    try std.testing.expect(!isIncompleteInput("x != y"));
    try std.testing.expect(!isIncompleteInput("x <= y"));
    try std.testing.expect(!isIncompleteInput("x >= y"));
}

test "isIncompleteInput: string with open paren ignored" {
    try std.testing.expect(!isIncompleteInput("\"hello (world\""));
}

test "isIncompleteInput: keywords at EOL" {
    try std.testing.expect(isIncompleteInput("if x then"));
    try std.testing.expect(isIncompleteInput("if x then 1 else"));
    try std.testing.expect(!isIncompleteInput("then"));
}

test "isIncompleteInput: commands start with colon skipped" {
    try std.testing.expect(!isIncompleteInput(":help"));
    try std.testing.expect(!isIncompleteInput(":type ("));
}

