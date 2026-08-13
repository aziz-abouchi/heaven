const std = @import("std");
//const Shell = @import("../runtime/shell.zig").Shell;
const shell_lib = @import("../runtime/shell/mod.zig");
const Shell = shell_lib.Shell;
const platform = @import("platform");
const ts = platform.ts;
const commands = @import("../runtime/shell/commands.zig");

pub const DirectiveType = enum {
    axiom,
    skill,
    spawn,
    hook,
};

pub const Directive = struct {
    type: DirectiveType,
    name: []const u8,
    extra: []const u8,
};

/// Charge le fichier Markdown spécifié, le parse et applique les directives au Kernel.
pub fn loadFromFile(path: []const u8, kernel: *Shell) !void {
    const allocator = kernel.allocator;

    // 1. Lecture sûre du fichier HEAVEN.md
    const file_text = platform.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch |err| {
        if (err == error.FileNotFound) {
            // platform.debug.print("[HEAVEN.MD] Aucun fichier '{s}' trouvé au point de montage courant. Configuration ignorée.\n", .{path});
            return;
        }
        return err;
    };
    defer allocator.free(file_text);

    // 2. Initialisation du parser Tree-sitter
    const parser = ts.ts_parser_new() orelse return error.TreeSitterInitFailed;
    defer ts.ts_parser_delete(parser);

    _ = ts.ts_parser_set_language(parser, platform.tree_sitter_heaven());

    const tree = ts.ts_parser_parse_string(parser, null, file_text.ptr, @intCast(file_text.len)) orelse return error.ParsingFailed;
    defer ts.ts_tree_delete(tree);

    // 3. Extraction des directives via la liste non-managée
    const directives = try parseDirectives(allocator, tree, file_text);
    defer allocator.free(directives);

    // 4. Dispatching vers le Kernel
    for (directives) |dir| {
        dispatchDirective(dir, kernel) catch |err| {
            // platform.debug.print("[HEAVEN.MD] Échec de l'application du dispatch ({s}): {s}\n", .{ @tagName(dir.type), @errorName(err) });
        };
    }
}

/// Parcourt l'AST généré par Tree-sitter pour extraire toutes les configurations valides.
pub fn parseDirectives(allocator: std.mem.Allocator, tree: ?*ts.TSTree, source: []const u8) ![]Directive {
    // Initialisation explicite sans stockage d'allocateur
    var directives_list = std.ArrayListUnmanaged(Directive){};
    errdefer directives_list.deinit(allocator);

    const root = ts.ts_tree_root_node(tree);
    try walkTree(allocator, root, source, &directives_list);

    return try directives_list.toOwnedSlice(allocator);
}

/// Exploration récursive de l'arbre Tree-sitter
fn walkTree(allocator: std.mem.Allocator, node: ts.TSNode, source: []const u8, list: *std.ArrayListUnmanaged(Directive)) !void {
    const node_type = std.mem.span(ts.ts_node_type(node));

    if (std.mem.eql(u8, node_type, "config_directive") or std.mem.indexOf(u8, node_type, "directive") != null) {
        const start = ts.ts_node_start_byte(node);
        const end = ts.ts_node_end_byte(node);

        if (end <= source.len) {
            const raw_text = std.mem.trim(u8, source[start..end], " \r\n\t");
            if (parseDirectiveText(raw_text)) |dir| {
                // L'allocateur est passé à l'allocation/insertion
                try list.append(allocator, dir);
            }
        }
    }

    const child_count = ts.ts_node_child_count(node);
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        try walkTree(allocator, ts.ts_node_child(node, i), source, list);
    }
}

fn parseDirectiveText(text: []const u8) ?Directive {
    if (text.len == 0 or text[0] != ':') return null;

    var it = std.mem.tokenizeAny(u8, text, " \t\r\n");
    const op = it.next() orelse return null;

    if (std.mem.eql(u8, op, ":axiom")) {
        const name = it.next() orelse return null;
        const colon = it.next() orelse return null;
        if (!std.mem.eql(u8, colon, ":")) return null;
        const type_expr = it.rest();
        return Directive{ .type = .axiom, .name = name, .extra = std.mem.trim(u8, type_expr, " ") };
    } else if (std.mem.eql(u8, op, ":skill")) {
        const name = it.rest();
        return Directive{ .type = .skill, .name = std.mem.trim(u8, name, " "), .extra = "" };
    } else if (std.mem.eql(u8, op, ":spawn")) {
        const name = it.rest();
        return Directive{ .type = .spawn, .name = std.mem.trim(u8, name, " "), .extra = "" };
    } else if (std.mem.eql(u8, op, ":hook")) {
        const rest = it.rest();
        if (std.mem.indexOf(u8, rest, "=>")) |pos| {
            const event = std.mem.trim(u8, rest[0..pos], " ");
            const agent = std.mem.trim(u8, rest[pos + 2 ..], " ");
            return Directive{ .type = .hook, .name = event, .extra = agent };
        }
    }
    return null;
}

pub fn dispatchDirective(directive: Directive, kernel: *Shell) !void {
    switch (directive.type) {
        .axiom => {
            // :axiom add_zero : a + 0 = a
            // Pour l'instant on délègue à cmdAxiom qui parse "name : lhs = rhs"
            var buf: [256]u8 = undefined;
            const input = std.fmt.bufPrint(&buf, "{s} : {s}", .{ directive.name, directive.extra }) catch return;
            commands.cmdAxiom(kernel, input);
            // cmdAxiom affiche déjà ✓ axiom assumed
        },
        .skill => {
            // :skill algebra → active le skill builtin ou enregistre
            kernel.skills.register(directive.name, &.{ .normalize, .simplify, .exact }) catch {};
            // platform.debug.print("[BOOT] Skill activé ➜ {s}\n", .{directive.name});
        },
        .spawn => {
            // :spawn proof_agent → green thread nommé
            commands.cmdSpawn(kernel, directive.name);
        },
        .hook => {
            // :hook theorem_added => consistency_check
            // platform.debug.print("[BOOT] Hook lié ➜ Event '{s}' ⚡ Agent '{s}'\n", .{ directive.name, directive.extra });
            // kernel.green.registerHook(directive.name, directive.extra) quand l'API sera prête
        },
    }
}
