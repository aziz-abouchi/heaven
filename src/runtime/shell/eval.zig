const std = @import("std");
const Shell = @import("init.zig").Shell;
const platform = @import("platform");
const commands = @import("commands.zig");
const commands_list = @import("commands_list.zig");
const Heaven = @import("heaven_expr").Heaven;


const PROOF_DEBUG = true;

pub fn bridgeTheoremToProofEnv(self: *Shell, name: []const u8, stmt: []const u8) void {
    if (PROOF_DEBUG) platform.debug.print("DEBUG: bridging theorem name='{s}'\n", .{name});
    if (self.heaven.proof_core.theorems.get(name)) |thm| {
        if (PROOF_DEBUG) platform.debug.print("DEBUG: found in proof_core, lhs={d} rhs={d}\n", .{ thm.lhs, thm.rhs });
        self.proofs.theorem(name, stmt, thm.lhs, thm.rhs) catch |err| {
            if (PROOF_DEBUG) platform.debug.print("DEBUG: self.proofs.theorem failed: {s}\n", .{@errorName(err)});
        };
    } else {
        if (PROOF_DEBUG) platform.debug.print("DEBUG: NOT found in heaven.proof_core.theorems for name='{s}'\n", .{name});
    }
}

pub fn evalHeavenCode(self: *Shell, code: []const u8) void {
    const trimmed = std.mem.trim(u8, code, " \t\r\n");
    if (trimmed.len == 0) return;

    // === INTERCEPTION DES COMMANDES DE FICHIERS (IO) ===
    if (std.mem.startsWith(u8, trimmed, "load ")) {
        const result = commands.cmdLoadFile(self, trimmed["load ".len..]) catch |err| {
            platform.debug.print("Error loading file: {}\n", .{err});
            return;
        };

        platform.debug.print("{s}\n", .{result});
        return;
    }

    if (std.mem.startsWith(u8, trimmed, "parseFileWithLanguage ")) {
        const result = commands.cmdParseFileWithLanguage(self, trimmed["parseFileWithLanguage ".len..]) catch |err| {
            platform.debug.print("Error parsing file: {}\n", .{err});
            return;
        };

        platform.debug.print("{s}\n", .{result});
        return;
    }
    // ===================================================

    // Évaluation standard pour tout le reste
    const result = self.heaven.eval(trimmed) catch |err| {
        platform.debug.print("[EVAL ERROR] {}\n", .{err},);
        self.ingestor.ingest("repl.hvn", trimmed) catch {};
        return;
    };

    // DEBUG
    platform.debug.print("[DEBUG] result = '{s}'\n", .{result});
}

// Fonctions requises par commands.zig — redirigent toutes vers Heaven.eval
pub fn exprEval(self: *Shell, input: []const u8) void {
    const result = self.heaven.eval(input) catch return;

    if (PROOF_DEBUG) platform.debug.print("\xe2\x86\x92 {s}\n", .{result});
}

pub fn exprSimplify(self: *Shell, input: []const u8) void {
    const result = self.heaven.simplify(input) catch |err| {
        platform.debug.print("Simplify error: {}\n", .{err});
        return;
    };

    if (PROOF_DEBUG) platform.debug.print("{s}\n", .{result});
}

pub fn exprFact(self: *Shell, input: []const u8) void {
    const result = self.heaven.eval(input) catch return;

    if (PROOF_DEBUG) platform.debug.print("\xe2\x86\x92 {s}\n", .{result});
}

pub fn exprRule(self: *Shell, input: []const u8) void {
    const result = self.heaven.eval(input) catch return;

    if (PROOF_DEBUG) platform.debug.print("\xe2\x86\x92 {s}\n", .{result});
}

pub fn exprQuery(self: *Shell, input: []const u8) void {
    const result = self.heaven.eval(input) catch return;

    if (PROOF_DEBUG) platform.debug.print("\xe2\x86\x92 {s}\n", .{result});
}

pub fn exprRewrite(self: *Shell, input: []const u8) void {
    const result = self.heaven.eval(input) catch return;

    if (PROOF_DEBUG) platform.debug.print("\xe2\x86\x92 {s}\n", .{result});
}

pub const CompletionItem = struct {
    label: []const u8,
    kind: enum {
        function,
        variable,
        constructor,
        type,
        macro,
        theorem,
        axiom,
        command,
    },
};

pub fn getCompletions(allocator: std.mem.Allocator, heaven: *Heaven, prefix: []const u8) ![]CompletionItem {
    var list = std.ArrayListUnmanaged(CompletionItem){};
    errdefer {
        for (list.items) |item| allocator.free(item.label);
        list.deinit(allocator);
    }

    // 1. Commandes REPL
    for (commands_list.commands) |cmd| {
        if (std.mem.startsWith(u8, cmd.name, prefix)) {
            const label = try allocator.dupe(u8, cmd.name);
            try list.append(allocator, .{ .label = label, .kind = .command });
        }
        if (cmd.shortcut) |s| {
            if (std.mem.startsWith(u8, s, prefix)) {
                const label = try allocator.dupe(u8, s);
                try list.append(allocator, .{ .label = label, .kind = .command });
            }
        }
    }

    // 2. Fonctions enregistrées dans engine.fns (clés = chaînes)
    var it = heaven.engine.fns.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        if (std.mem.startsWith(u8, name, prefix)) {
            const label = try allocator.dupe(u8, name);
            try list.append(allocator, .{ .label = label, .kind = .function });
        }
    }

    // 3. Variables de l'environnement (Env.bindings) : clés = Sym (u32)
    var env_it = heaven.env.bindings.iterator();
    while (env_it.next()) |kv| {
        const sym = kv.key_ptr.*;
        const name = heaven.store.interner.resolve(sym);
        if (std.mem.startsWith(u8, name, prefix)) {
            const label = try allocator.dupe(u8, name);
            try list.append(allocator, .{ .label = label, .kind = .variable });
        }
    }

    // 4. Constructeurs intégrés (chaînes)
    const builtin_constructors = [_][]const u8{ "Zero", "Succ", "Nil", "Cons", "True", "False" };
    for (builtin_constructors) |c| {
        if (std.mem.startsWith(u8, c, prefix)) {
            const label = try allocator.dupe(u8, c);
            try list.append(allocator, .{ .label = label, .kind = .constructor });
        }
    }

    // 5. Théorèmes (heaven.proof_core.theorems) : StringHashMapUnmanaged (clés = chaînes)
    var thm_it = heaven.proof_core.theorems.iterator();
    while (thm_it.next()) |entry| {
        const name = entry.key_ptr.*;
        if (std.mem.startsWith(u8, name, prefix)) {
            const label = try allocator.dupe(u8, name);
            try list.append(allocator, .{ .label = label, .kind = .theorem });
        }
    }

    // 6. Axiomes (heaven.proof_core.axioms) : ArrayListUnmanaged (items avec champ .name)
    for (heaven.proof_core.axioms.items) |ax| {
        const name = ax.name;
        if (std.mem.startsWith(u8, name, prefix)) {
            const label = try allocator.dupe(u8, name);
            try list.append(allocator, .{ .label = label, .kind = .axiom });
        }
    }

    return list.toOwnedSlice(allocator);
}

pub fn cmdComplete(self: *Shell, prefix: []const u8) void {
    const items = getCompletions(self.allocator, self.heaven, prefix) catch |err| {
        platform.debug.print("Erreur de complétion : {}\n", .{err});
        return;
    };
    defer {
        for (items) |item| self.allocator.free(item.label);
        self.allocator.free(items);
    }
    if (items.len == 0) {
        platform.debug.print("  Aucune suggestion\n", .{});
        return;
    }
    platform.debug.print("  Suggestions :\n", .{});
    for (items) |item| {
        platform.debug.print("    {s} ({s})\n", .{ item.label, @tagName(item.kind) });
    }
}