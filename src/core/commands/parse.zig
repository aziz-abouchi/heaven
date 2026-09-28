//! parse.zig — Helpers de parsing de Commands (D4 batch 2).
//! Extraits de src/core/commands.zig. Voir docs/DECISIONS.md (D4).

const std = @import("std");
const expr = @import("expr");
const engine_expr = @import("engine_expr");
const bridge_expr = @import("bridge_expr");

const Store = expr.Store;
const Id = expr.Id;

pub fn isIdent(s: []const u8) bool {
    if (s.len == 0) return false;
    const c = s[0];
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

pub fn isOperatorTok(s: []const u8) bool {
    const ops = [_][]const u8{ "+", "-", "*", "/", "=", "<", ">", "==", "!=", ":=", "->", "&&", "||" };
    for (ops) |op| {
        if (std.mem.eql(u8, s, op)) return true;
    }
    return false;
}

pub fn hasErrorNode(cmds: anytype, node: *const @import("bridge_expr").Matrix) bool {
    if (node.kind == .err_node) {
        return true;
    }
    for (node.children) |*child| {
        if (hasErrorNode(cmds, child)) return true;
    }
    return false;
}

pub fn tryFnCall(cmds: anytype, input: []const u8) ?[]u8 {
    if (input.len == 0 or input[0] == '(' or std.ascii.isDigit(input[0])) return null;
    if (std.mem.indexOfScalar(u8, input, '(')) |paren_idx| {
        const before_paren = input[0..paren_idx];
        if (std.mem.indexOfScalar(u8, before_paren, ' ') == null) {
            const potential_name = std.mem.trim(u8, input[0..paren_idx], " ");
            if (potential_name.len == 0) return null;
            for (potential_name) |c| {
                if (!std.ascii.isAlphanumeric(c) and c != '_') return null;
            }
            if (cmds.engine.fns.getEntry(potential_name) == null) return null;
            const end_paren = std.mem.lastIndexOfScalar(u8, input, ')') orelse return null;
            if (end_paren <= paren_idx) return null;
            const inner_args = std.mem.trim(u8, input[paren_idx + 1 .. end_paren], " ");
            if (inner_args.len == 0) return null;
            var args_list: [16][]const u8 = undefined;
            var num_args: usize = 0;
            var depth: i32 = 0;
            var start: usize = 0;
            for (inner_args, 0..) |ch, i| {
                switch (ch) {
                    '(' => depth += 1,
                    ')' => depth -= 1,
                    ',' => {
                        if (depth == 0) {
                            if (num_args < 16) {
                                args_list[num_args] = std.mem.trim(u8, inner_args[start..i], " ");
                                num_args += 1;
                            }
                            start = i + 1;
                        }
                    },
                    else => {},
                }
            }
            if (start < inner_args.len and num_args < 16) {
                args_list[num_args] = std.mem.trim(u8, inner_args[start..], " ");
                num_args += 1;
            }
            if (num_args == 0) return null;
            var eval_args: [16]Id = undefined;
            for (0..num_args) |i| {
                const expr_id = parseExpression(cmds, args_list[i]) catch return null;
                eval_args[i] = expr_id;
            }
            cmds.engine.fuel = 1000_000;
            const sym_id = cmds.store.sym(potential_name) catch return null;
            const call_id = cmds.store.apply(sym_id, eval_args[0..num_args]) catch return null;
            const result = engine_expr.evaluate(cmds.store, cmds.env, cmds.engine, call_id, 0) catch return null;
            return expr.toString(cmds.store, result, cmds.allocator) catch return null;
        }
    }
    const space_idx = std.mem.indexOfScalar(u8, input, ' ') orelse return null;
    const name = input[0..space_idx];
    if (cmds.engine.fns.getEntry(name) == null) {
        return null;
    }

    const args_str = std.mem.trim(u8, input[space_idx..], " ");
    if (args_str.len == 0) return null;
    var args_list: [16][]const u8 = undefined;
    var num_args: usize = 0;
    var depth: i32 = 0;
    var start: usize = 0;
    for (args_str, 0..) |ch, i| {
        switch (ch) {
            '(' => depth += 1,
            ')' => depth -= 1,
            ' ' => {
                if (depth == 0 and i > start) {
                    if (num_args < 16) {
                        args_list[num_args] = std.mem.trim(u8, args_str[start..i], " ");
                        num_args += 1;
                    }
                    start = i + 1;
                }
            },
            else => {},
        }
    }
    if (start < args_str.len and num_args < 16) {
        args_list[num_args] = std.mem.trim(u8, args_str[start..], " ");
        num_args += 1;
    }
    if (num_args == 0) return null;
    var eval_args: [16]Id = undefined;
    for (0..num_args) |i| {
        const expr_id = parseExpression(cmds, args_list[i]) catch return null;
        eval_args[i] = expr_id;
    }
    cmds.engine.fuel = 1000_000;
    const sym_id = cmds.store.sym(name) catch return null;
    const call_id = cmds.store.apply(sym_id, eval_args[0..num_args]) catch return null;
    const result = engine_expr.evaluate(cmds.store, cmds.env, cmds.engine, call_id, 0) catch return null;
    return expr.toString(cmds.store, result, cmds.allocator) catch return null;
}

pub fn parseApp(cmds: anytype, input: []const u8) !Id {
    const trimmed = std.mem.trim(u8, input, " \t");
    if (trimmed.len == 0) return error.InvalidLambda;

    var s = trimmed;
    while (s.len >= 2 and s[0] == '(' and s[s.len - 1] == ')') {
        const inner = s[1 .. s.len - 1];
        const inner_trim = std.mem.trim(u8, inner, " \t");
        if (inner_trim.len == 0) break;
        s = inner_trim;
    }

    if (std.mem.startsWith(u8, s, "λ") or std.mem.startsWith(u8, s, "\\")) {
        const wrapped = try std.fmt.allocPrint(cmds.allocator, "({s})", .{s});
        defer cmds.allocator.free(wrapped);
        return try parseLambda(cmds, wrapped);
    }

    var start: ?usize = null;
    if (std.mem.indexOf(u8, trimmed, "(λ")) |pos| {
        start = pos;
    } else if (std.mem.indexOf(u8, trimmed, "(\\")) |pos| start = pos;
    if (start == null) return error.InvalidLambda;
    const pos = start.?;

    var depth: usize = 1;
    var i = pos + 2;
    while (i < trimmed.len) : (i += 1) {
        if (trimmed[i] == '(') {
            depth += 1;
        } else if (trimmed[i] == ')') {
            depth -= 1;
            if (depth == 0) break;
        }
    }
    if (depth != 0) return error.InvalidLambda;
    const lambda_end = i + 1;
    const lambda_part = trimmed[pos..lambda_end];
    const rest = trimmed[lambda_end..];

    const lambda_id = try parseLambda(cmds, lambda_part);
    const rest_trim = std.mem.trim(u8, rest, " \t");
    if (rest_trim.len == 0) return lambda_id;

    var arg_str = rest_trim;
    if (arg_str.len > 0 and arg_str[0] == ')') {
        arg_str = arg_str[1..];
    }
    arg_str = std.mem.trim(u8, arg_str, " \t");
    if (arg_str.len > 0 and arg_str[arg_str.len - 1] == ')') {
        arg_str = arg_str[0 .. arg_str.len - 1];
    }
    arg_str = std.mem.trim(u8, arg_str, " \t");

    const arg_id = try cmds.bridge.importExpr(arg_str);
    return try cmds.store.apply(lambda_id, &.{arg_id});
}

pub fn parseApplication(cmds: anytype, input: []const u8) anyerror!Id {
    const trimmed = std.mem.trim(u8, input, " \t");
    if (trimmed.len == 0) return error.InvalidSyntax;

    if (std.mem.indexOfScalar(u8, trimmed, '(')) |open| {
        if (std.mem.lastIndexOfScalar(u8, trimmed, ')')) |close| {
            if (close > open) {
                const name = std.mem.trim(u8, trimmed[0..open], " \t");
                if (name.len > 0 and isIdent(name)) {
                    const inner = std.mem.trim(u8, trimmed[open + 1 .. close], " \t");
                    var args: std.ArrayListUnmanaged(Id) = .{};
                    defer args.deinit(cmds.allocator);
                    if (inner.len > 0) {
                        var it = std.mem.splitScalar(u8, inner, ',');
                        while (it.next()) |part| {
                            const p = std.mem.trim(u8, part, " \t");
                            if (p.len > 0) {
                                const arg_id = parseExpression(cmds, p) catch return error.InvalidSyntax;
                                try args.append(cmds.allocator, arg_id);
                            }
                        }
                    }
                    const func_id = try cmds.store.sym(name);
                    return try cmds.store.apply(func_id, args.items);
                }
            }
        }
    }

    var tokens: [16][]const u8 = undefined;
    var num_tokens: usize = 0;
    var tok_it = std.mem.tokenizeScalar(u8, trimmed, ' ');
    while (tok_it.next()) |tok| {
        if (num_tokens < 16) {
            tokens[num_tokens] = tok;
            num_tokens += 1;
        }
    }
    if (num_tokens < 2) return error.InvalidSyntax;
    if (!isIdent(tokens[0])) return error.InvalidSyntax;
    for (tokens[0..num_tokens]) |tok| {
        if (isOperatorTok(tok)) return error.InvalidSyntax;
    }

    const func_id = try cmds.store.sym(tokens[0]);
    var args: std.ArrayListUnmanaged(Id) = .{};
    defer args.deinit(cmds.allocator);
    for (tokens[1..num_tokens]) |tok| {
        const arg_id = parseExpression(cmds, tok) catch return error.InvalidSyntax;
        try args.append(cmds.allocator, arg_id);
    }
    return try cmds.store.apply(func_id, args.items);
}

pub fn parseCallExpr(cmds: anytype, input: []const u8) !Id {
    const open = std.mem.indexOfScalar(u8, input, '(') orelse return error.InvalidSyntax;
    const close = std.mem.lastIndexOfScalar(u8, input, ')') orelse return error.InvalidSyntax;
    if (close <= open) return error.InvalidSyntax;

    const name = std.mem.trim(u8, input[0..open], " \t");
    const inner = std.mem.trim(u8, input[open + 1 .. close], " \t");

    const func_id = try cmds.store.sym(name);

    var args: std.ArrayListUnmanaged(Id) = .{};
    defer args.deinit(cmds.allocator);

    if (inner.len > 0) {
        var depth: i32 = 0;
        var start: usize = 0;
        for (inner, 0..) |ch, i| {
            switch (ch) {
                '(' => depth += 1,
                ')' => depth -= 1,
                ',' => {
                    if (depth == 0) {
                        const part = std.mem.trim(u8, inner[start..i], " \t");
                        if (part.len > 0) {
                            const arg_id = try cmds.bridge.importExpr(part);
                            try args.append(cmds.allocator, arg_id);
                        }
                        start = i + 1;
                    }
                },
                else => {},
            }
        }
        const last = std.mem.trim(u8, inner[start..], " \t");
        if (last.len > 0) {
            const arg_id = try cmds.bridge.importExpr(last);
            try args.append(cmds.allocator, arg_id);
        }
    }

    return cmds.store.apply(func_id, args.items);
}

pub fn parseLambda(cmds: anytype, input: []const u8) !Id {
    const trimmed = std.mem.trim(u8, input, " \t");
    if (trimmed.len == 0) return error.InvalidLambda;

    var s = trimmed;
    while (s.len >= 2 and s[0] == '(' and s[s.len - 1] == ')') {
        const inner = s[1 .. s.len - 1];
        const inner_trim = std.mem.trim(u8, inner, " \t");
        if (inner_trim.len == 0) break;
        s = inner_trim;
    }
    if (s.len == 0) return error.InvalidLambda;

    if (!std.mem.startsWith(u8, s, "λ") and !std.mem.startsWith(u8, s, "\\")) {
        return error.InvalidLambda;
    }

    var rest = if (std.mem.startsWith(u8, s, "λ")) s["λ".len..] else s["\\".len..];
    rest = std.mem.trimLeft(u8, rest, " \t");
    if (rest.len == 0) return error.InvalidLambda;

    var param_end: usize = 0;
    while (param_end < rest.len) {
        const c = rest[param_end];
        if (c == '.' or c == ' ' or c == '\t') break;
        param_end += 1;
    }
    if (param_end == 0) return error.InvalidLambda;
    const param_name = rest[0..param_end];
    rest = rest[param_end..];
    rest = std.mem.trimLeft(u8, rest, " \t");
    if (rest.len == 0 or rest[0] != '.') return error.InvalidLambda;
    rest = rest[1..];
    rest = std.mem.trimLeft(u8, rest, " \t");
    if (rest.len == 0) return error.InvalidLambda;

    const body_end = if (rest[rest.len - 1] == ')') rest.len - 1 else rest.len;
    const body_str = rest[0..body_end];
    if (body_str.len == 0) return error.InvalidLambda;

    const body_id = try cmds.bridge.importExpr(body_str);
    return try cmds.store.lambdaNative(&.{param_name}, body_id);
}

pub fn parseExpression(cmds: anytype, input: []const u8) anyerror!Id {
    const trimmed = std.mem.trim(u8, input, " \t");
    if (trimmed.len == 0) return error.InvalidInput;

    // Unicode : x² → x^2
    if (expr.containsSuperscript(trimmed)) {
        const normalized = try expr.normalizeUnicodePowers(trimmed, cmds.allocator);
        defer cmds.allocator.free(normalized);
        return parseExpression(cmds, normalized);
    }

    // SYNTAXE NATIVE : tout ce qui ne commence pas par '('
    if (trimmed[0] != '(') {
        var arena = std.heap.ArenaAllocator.init(cmds.allocator);
        defer arena.deinit();
        const sexpr = expr.nativeToSExpr(trimmed, arena.allocator()) catch {
            // Fallback : atome simple (ex: "+", identifiant exotique)
            return cmds.store.sym(trimmed);
        };
        if (sexpr.len > 0 and sexpr[0] == '(') {
            // Forme composée → re-parser en Lisp (récursion sûre)
            const owned = try cmds.allocator.dupe(u8, sexpr);
            defer cmds.allocator.free(owned);
            return parseExpression(cmds, owned);
        }
        // Atome (nombre, identifiant, string) — interner duplique la chaîne ✓
        if (std.fmt.parseInt(i64, sexpr, 10)) |val| {
            return cmds.store.int(val);
        } else |_| {}
        return cmds.store.sym(sexpr);
    }

    if (cmds.shell_parser.parse(input)) |matrix| {
        defer cmds.shell_parser.reset();

        if (!hasErrorNode(cmds, &matrix)) {
            const actual_node = if (matrix.kind == .program and matrix.children.len > 0)
                &matrix.children[0]
            else
                &matrix;

            var bridge = @import("bridge_expr").Bridge.init(cmds.store, cmds.allocator);
            if (bridge.translateOne(actual_node)) |id| {
                return id;
            } else |_| {}
        }
    } else |_| {}

    if (trimmed.len >= 2 and trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')') {
        return cmds.bridge.importExpr(trimmed);
    }

    if (std.mem.indexOfScalar(u8, trimmed, ' ')) |space1| {
        if (space1 + 1 < trimmed.len) {
            const op_start = space1 + 1;
            if (std.mem.indexOfScalar(u8, trimmed[op_start..], ' ')) |space2_rel| {
                const space2 = op_start + space2_rel;
                const lhs_str = trimmed[0..space1];
                const op_str = trimmed[op_start..space2];
                const rhs_str = trimmed[space2 + 1 ..];
                if (isOperatorTok(op_str)) {
                    const lhs_id = try parseExpression(cmds, lhs_str);
                    const rhs_id = try parseExpression(cmds, rhs_str);
                    return cmds.store.binop(op_str, lhs_id, rhs_id);
                }
            }
        }
    }

    if (parseApplication(cmds, input)) |id| {
        return id;
    } else |_| {}

    if (std.fmt.parseInt(i64, trimmed, 10)) |val| {
        return cmds.store.int(val);
    } else |_| {}
    return cmds.store.sym(trimmed);
}

