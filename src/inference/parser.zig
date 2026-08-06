const std = @import("std");
const platform = @import("platform");
const matrix_lib = @import("../core/matrix.zig");
const dispatch = @import("../core/dispatch.zig");
const reasoning = @import("reasoning.zig");

pub const Parser = struct {
    allocator: std.mem.Allocator,
    matrix: *matrix_lib.Matrix,

    pub fn parseFile(self: *Parser, path: []const u8) !void {
        const file = try platform.fs.cwd().openFile(path, .{});
        defer file.close();
        const size = (try file.stat()).size;
        const content = try self.allocator.alloc(u8, size);
        defer self.allocator.free(content);
        _ = try file.readAll(content);

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            // Support des commentaires '#' et '//'
            if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "//") or std.mem.startsWith(u8, trimmed, "#")) continue;

            if (std.mem.startsWith(u8, trimmed, "fact ")) {
                const content_fact = std.mem.trimEnd(u8, std.mem.trimStart(u8, trimmed[5..], " "), ".");
                _ = try self.parseTypeExpression(content_fact);
            } else if (std.mem.startsWith(u8, trimmed, "rule ")) {
                const content_rule = std.mem.trimEnd(u8, std.mem.trimStart(u8, trimmed[5..], " "), ".");
                // On sépare la tête et le corps de la règle au niveau du ':-'
                if (std.mem.indexOf(u8, content_rule, " :- ")) |pos| {
                    const head = std.mem.trim(u8, content_rule[0..pos], " ");
                    const body = std.mem.trim(u8, content_rule[pos + 4 ..], " ");
                    const head_id = try self.parseTypeExpression(head);
                    const body_id = try self.parseTypeExpression(body);
                    try self.matrix.addEdge(head_id, body_id, "implies");
                } else {
                    _ = try self.parseTypeExpression(content_rule);
                }
            } else if (std.mem.indexOf(u8, trimmed, " IS ")) |pos| {
                const left = std.mem.trim(u8, trimmed[0..pos], " ");
                const right = std.mem.trim(u8, trimmed[pos + 4 ..], " .");
                const s_id = try self.matrix.addUniqueSymbol(left);
                const t_id = try self.parseTypeExpression(right);
                try self.matrix.addEdge(s_id, t_id, "IS");
            } else if (std.mem.indexOfScalar(u8, trimmed, ':')) |pos| {
                const left = std.mem.trim(u8, trimmed[0..pos], " ");
                const right = std.mem.trim(u8, trimmed[pos + 1 ..], " .");
                const s_id = try self.matrix.addUniqueSymbol(left);
                const t_id = try self.parseTypeExpression(right);
                try self.matrix.addEdge(s_id, t_id, "has_type");
            } else if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_pos| {
                try self.handleBindAndApply(trimmed[0..eq_pos], trimmed[eq_pos + 1 ..]);
            } else if (std.mem.startsWith(u8, trimmed, "?-")) {
                const query_content = std.mem.trim(u8, trimmed[2..], " ");
                const tmp = try std.mem.concat(self.allocator, u8, &[_][]const u8{ "QUERY:", query_content });
                defer self.allocator.free(tmp);
                _ = try self.matrix.addUniqueSymbol(tmp);
            } else if (std.mem.startsWith(u8, trimmed, "execute ")) {
                try self.queueCommand(std.mem.trim(u8, trimmed[8..], " "));
            }
        }
    }

    pub fn unifyEverything(self: *Parser) !void {
        _ = try reasoning.Reasoner.process(self.matrix);
        platform.debug.print("[PARSER] Unification globale terminée.\n", .{});
    }

    fn parseTypeExpression(self: *Parser, expr_str: []const u8) !matrix_lib.BobId {
        const trimmed = std.mem.trim(u8, expr_str, " \t");

        // --- Sucre syntaxique pour le parsing de listes [X | Tail] ou [] ---
        if (std.mem.startsWith(u8, trimmed, "[") and std.mem.endsWith(u8, trimmed, "]")) {
            const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], " ");
            if (inner.len == 0) {
                return try self.matrix.addUniqueSymbol("nil");
            }
            if (std.mem.indexOfScalar(u8, inner, '|')) |bar_pos| {
                const head_str = std.mem.trim(u8, inner[0..bar_pos], " ");
                const tail_str = std.mem.trim(u8, inner[bar_pos + 1 ..], " ");

                const head_id = try self.parseTypeExpression(head_str);
                const tail_id = try self.parseTypeExpression(tail_str);

                const args = try self.allocator.alloc(matrix_lib.BobId, 2);
                args[0] = head_id;
                args[1] = tail_id;
                return try self.matrix.addNode(.{ .Apply = .{ .func = try self.matrix.addUniqueSymbol("cons"), .args = args } });
            }
        }

        // Parsing classique des applications fonctionnelles ex: member(A, B)
        if (std.mem.indexOfScalar(u8, trimmed, '(')) |open_paren| {
            if (std.mem.endsWith(u8, trimmed, ")")) {
                const head = trimmed[0..open_paren];
                const tail = trimmed[open_paren + 1 .. trimmed.len - 1];
                const func_id = try self.matrix.addUniqueSymbol(head);

                // Gestion basique de la séparation des arguments par virgule
                if (std.mem.indexOfScalar(u8, tail, ',')) |comma_pos| {
                    const arg1_str = std.mem.trim(u8, tail[0..comma_pos], " ");
                    const arg2_str = std.mem.trim(u8, tail[comma_pos + 1 ..], " ");
                    const arg1 = try self.parseTypeExpression(arg1_str);
                    const arg2 = try self.parseTypeExpression(arg2_str);

                    const args = try self.allocator.alloc(matrix_lib.BobId, 2);
                    args[0] = arg1;
                    args[1] = arg2;
                    return try self.matrix.addNode(.{ .Apply = .{ .func = func_id, .args = args } });
                } else {
                    const arg_id = try self.parseTypeExpression(tail);
                    const args = try self.allocator.alloc(matrix_lib.BobId, 1);
                    args[0] = arg_id;
                    return try self.matrix.addNode(.{ .Apply = .{ .func = func_id, .args = args } });
                }
            }
        }
        return try self.matrix.addUniqueSymbol(trimmed);
    }

    fn handleBindAndApply(self: *Parser, target: []const u8, expr: []const u8) !void {
        const var_name = std.mem.trim(u8, target, " ");
        const body = std.mem.trim(u8, expr, " ");
        const var_id = try self.matrix.addUniqueSymbol(var_name);

        if (std.mem.indexOfAny(u8, body, "+-*/")) |op_pos| {
            const op = body[op_pos .. op_pos + 1];
            const v1_s = std.mem.trim(u8, body[0..op_pos], " ");
            const v2_s = std.mem.trim(u8, body[op_pos + 1 ..], " ");
            const val1 = std.fmt.parseFloat(f64, v1_s) catch null;
            const val2 = std.fmt.parseFloat(f64, v2_s) catch null;

            if (val1 != null and val2 != null) {
                const n1 = try self.matrix.addNode(.{ .Scalar = val1.? });
                const n2 = try self.matrix.addNode(.{ .Scalar = val2.? });
                self.matrix.unify(var_id, n1);
                try self.matrix.addEdge(n1, n2, if (op[0] == '+') "PLUS" else "OP");
            }
        }
    }

    fn queueCommand(self: *Parser, action: []const u8) !void {
        const action_owned = try self.allocator.dupe(u8, action);
        const cmd_node = try self.allocator.create(dispatch.CommandNode);
        cmd_node.* = .{ .data = .{ .AddSymbol = action_owned }, .next = null };
        dispatch.command_queue.put(cmd_node);
    }
};
