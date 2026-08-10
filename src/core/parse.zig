//! Parser S-expression et syntaxes alternatives pour Heaven
//! Extrait de heaven_expr.zig pour modularité

const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const engine_expr = @import("engine_expr");
const Engine = engine_expr.Engine;

pub const Parser = struct {
    store: *Store,
    engine: *Engine,
    env: *engine_expr.Env,
    allocator: Allocator,

    pub fn init(store: *Store, engine: *Engine, env: *engine_expr.Env, allocator: std.mem.Allocator) Parser {
        return .{
            .store = store,
            .engine = engine,
            .env = env,
            .allocator = allocator,
        };
    }

    /// Cherche un mot-clé à la racine (profondeur parenthèses = 0)
    pub fn findKeywordAtRoot(text: []const u8, kw: []const u8) ?usize {
        var depth: i32 = 0;
        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            if (text[i] == '(') depth += 1 else if (text[i] == ')') depth -= 1;
            if (depth == 0 and i + kw.len <= text.len) {
                if (std.mem.startsWith(u8, text[i..], kw)) {
                    const after = if (i + kw.len < text.len) text[i + kw.len] else ' ';
                    if (after == ' ' or after == '\t' or after == '(') return i;
                }
            }
        }
        return null;
    }

    pub fn parseSExpr(self: *Parser, input: []const u8) !Id {
        const trimmed = std.mem.trim(u8, input, " \t");
        if (trimmed.len == 0) return self.store.unitLit();

        // === INTERCEPTION QUOTE / UNQUOTE ===
        if (std.mem.startsWith(u8, trimmed, "quote ") or std.mem.startsWith(u8, trimmed, "quote(")) {
            if (std.mem.indexOfScalar(u8, trimmed, '(')) |start| {
                if (std.mem.lastIndexOfScalar(u8, trimmed, ')')) |end| {
                    if (end > start) {
                        // On garde les parenthèses autour de l'expression intérieure
                        const inner_str = trimmed[start .. end + 1];
                        const inner_id = try self.parseSExpr(inner_str);
                        return self.store.quote(inner_id);
                    }
                }
            }
        }
        if (std.mem.startsWith(u8, trimmed, "unquote ") or std.mem.startsWith(u8, trimmed, "unquote(")) {
            if (std.mem.indexOfScalar(u8, trimmed, '(')) |start| {
                if (std.mem.lastIndexOfScalar(u8, trimmed, ')')) |end| {
                    if (end > start) {
                        // On garde les parenthèses
                        const inner_str = trimmed[start .. end + 1];
                        const inner_id = try self.parseSExpr(inner_str);
                        return self.store.unquote(inner_id);
                    }
                }
            }
        }
        // =====================================

        // Syntaxe fn(x) => body ou fn(x) body
        if (std.mem.startsWith(u8, trimmed, "fn(")) {
            const close = std.mem.indexOfScalar(u8, trimmed, ')') orelse return self.store.sym(trimmed);
            const params_str = trimmed[3..close];
            const rest = std.mem.trim(u8, trimmed[close + 1 ..], " \t");

            const body_str = if (std.mem.startsWith(u8, rest, "=>"))
                std.mem.trim(u8, rest[2..], " \t")
            else
                rest;

            var param_ids: std.ArrayListUnmanaged(Id) = .{};
            defer param_ids.deinit(self.allocator);
            var it = std.mem.tokenizeAny(u8, params_str, " ,");
            while (it.next()) |p| {
                try param_ids.append(self.allocator, try self.store.sym(p));
            }
            const body_id = try self.parseSExpr(body_str);
            try param_ids.append(self.allocator, body_id);
            return self.store.call("λ", param_ids.items);
        }

        // Chaîne de caractères (String)
        if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
            const str_val = trimmed[1 .. trimmed.len - 1];
            const sym = try self.store.interner.intern(str_val);
            return self.store.lit(.{ .str = sym });
        }

        // Entier littéral
        if (std.fmt.parseInt(i64, trimmed, 10)) |v| return self.store.int(v) else |_| {}

        // Float littéral
        if (std.mem.indexOfScalar(u8, trimmed, '.') != null) {
            if (std.fmt.parseFloat(f64, trimmed)) |v| return self.store.float(v) else |_| {}
        }

        // Syntaxe fun x => expr ou fun x y => expr (ou λ)
        if (std.mem.startsWith(u8, trimmed, "fun ") or std.mem.startsWith(u8, trimmed, "λ ")) {
            const keyword_len = if (std.mem.startsWith(u8, trimmed, "fun ")) "fun ".len else "λ ".len;
            const rest = trimmed[keyword_len..];
            if (std.mem.indexOf(u8, rest, "=>")) |arrow_pos| {
                const params_str = std.mem.trim(u8, rest[0..arrow_pos], " \t");
                const body_str = std.mem.trim(u8, rest[arrow_pos + 2 ..], " \t");
                var param_ids: std.ArrayListUnmanaged(Id) = .{};
                defer param_ids.deinit(self.allocator);
                var it = std.mem.tokenizeScalar(u8, params_str, ' ');
                while (it.next()) |p| {
                    if (p.len > 0) try param_ids.append(self.allocator, try self.store.sym(p));
                }
                const body_id = try self.parseSExpr(body_str);
                try param_ids.append(self.allocator, body_id);
                return self.store.call("λ", param_ids.items);
            }
        }

        // Syntaxe let x = expr ou let x := expr
        if (std.mem.startsWith(u8, trimmed, "let ")) {
            const rest = trimmed["let ".len..];
            if (std.mem.indexOfScalar(u8, rest, '=')) |eq_pos| {
                const name = std.mem.trim(u8, rest[0..eq_pos], " \t");
                const after_eq = rest[eq_pos + 1 ..];
                const expr_str = if (after_eq.len > 0 and after_eq[0] == ':')
                    std.mem.trim(u8, after_eq[1..], " \t")
                else
                    std.mem.trim(u8, after_eq, " \t");
                if (std.mem.indexOf(u8, expr_str, " in ")) |in_pos| {
                    const bound_expr = std.mem.trim(u8, expr_str[0..in_pos], " \t");
                    const body = std.mem.trim(u8, expr_str[in_pos + 4 ..], " \t");
                    const lambda = try self.store.call("λ", &.{ try self.store.sym(name), try self.parseSExpr(body) });
                    return self.store.apply(lambda, &.{try self.parseSExpr(bound_expr)});
                }
                const sym = try self.store.interner.intern(name);
                const body_id = try self.parseSExpr(expr_str);
                return self.store.bindSym(sym, body_id);
            }
        }

        // Appels explicites : f(a,b,c)
        if (trimmed.len > 0 and std.ascii.isAlphabetic(trimmed[0])) {
            var paren: ?usize = null;
            for (trimmed, 0..) |c, i| {
                if (c == '(') {
                    paren = i;
                    break;
                }
                if (c == ' ' or c == '\t') break;
            }
            if (paren) |p| {
                const func_name = std.mem.trim(u8, trimmed[0..p], " \t");
                if (func_name.len == 0) return self.store.sym(trimmed);

                // === INTERCEPTION QUOTE/UNQUOTE ===
                if (std.mem.eql(u8, func_name, "quote")) {
                    const end = std.mem.lastIndexOfScalar(u8, trimmed, ')') orelse return self.store.sym(trimmed);
                    const args_str = std.mem.trim(u8, trimmed[p + 1 .. end], " \t");
                    if (args_str.len > 0) {
                        const inner_id = try self.parseSExpr(args_str);
                        return self.store.quote(inner_id);
                    }
                }
                if (std.mem.eql(u8, func_name, "unquote")) {
                    const end = std.mem.lastIndexOfScalar(u8, trimmed, ')') orelse return self.store.sym(trimmed);
                    const args_str = std.mem.trim(u8, trimmed[p + 1 .. end], " \t");
                    if (args_str.len > 0) {
                        const inner_id = try self.parseSExpr(args_str);
                        return self.store.unquote(inner_id);
                    }
                }
                // ===================================

                // ✅ On cherche la parenthèse fermante qui correspond à la bonne profondeur
                var depth: i32 = 1;
                var end: usize = 0;
                for (trimmed[p + 1 ..], 0..) |c, i| {
                    if (c == '(') depth += 1;
                    if (c == ')') {
                        depth -= 1;
                        if (depth == 0) {
                            end = p + 1 + i;
                            break;
                        }
                    }
                }
                if (end == 0) return self.store.sym(trimmed);

                const args_str = std.mem.trim(u8, trimmed[p + 1 .. end], " \t");
                var arg_ids: std.ArrayListUnmanaged(Id) = .{};
                defer arg_ids.deinit(self.allocator);
                var d: i32 = 0;
                var start: usize = 0;
                for (args_str, 0..) |ch, i| {
                    switch (ch) {
                        '(' => d += 1,
                        ')' => d -= 1,
                        ',' => if (d == 0) {
                            const part = std.mem.trim(u8, args_str[start..i], " \t");
                            if (part.len > 0) try arg_ids.append(self.allocator, try self.parseSExpr(part));
                            start = i + 1;
                        },
                        else => {},
                    }
                }
                const last = std.mem.trim(u8, args_str[start..], " \t");
                if (last.len > 0) try arg_ids.append(self.allocator, try self.parseSExpr(last));
                return self.store.call(func_name, arg_ids.items);
            }
        }

        // Syntaxe let x := expr
        if (std.mem.startsWith(u8, trimmed, "let ")) {
            const rest = trimmed["let ".len..];
            const eq_pos = std.mem.indexOfScalar(u8, rest, ':') orelse return self.store.sym(trimmed);
            const name = std.mem.trim(u8, rest[0..eq_pos], " \t");
            const after_colon = std.mem.trim(u8, rest[eq_pos + 1 ..], " \t");
            if (!std.mem.startsWith(u8, after_colon, "=")) return self.store.sym(trimmed);
            const expr_str = std.mem.trim(u8, after_colon["=".len..], " \t");
            const sym = try self.store.interner.intern(name);
            const body_id = try self.parseSExpr(expr_str);
            return self.store.bindSym(sym, body_id);
        }

        // Liste entre parenthèses (syntaxe Lisp)
        if (trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')') {
            const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], " ");
            if (inner.len == 0) return self.store.unitLit();
            var parts: [16][]const u8 = undefined;
            var num_parts: usize = 0;
            var depth: i32 = 0;
            var start: usize = 0;
            for (inner, 0..) |ch, i| {
                switch (ch) {
                    '(' => depth += 1,
                    ')' => depth -= 1,
                    ' ', '\t', ',' => if (depth == 0) {
                        const part = std.mem.trim(u8, inner[start..i], " ");
                        if (part.len > 0 and num_parts < 16) {
                            parts[num_parts] = part;
                            num_parts += 1;
                        }
                        start = i + 1;
                    },
                    else => {},
                }
            }
            const last = std.mem.trim(u8, inner[start..], " ");
            if (last.len > 0 and num_parts < 16) {
                parts[num_parts] = last;
                num_parts += 1;
            }
            if (num_parts == 0) return self.store.unitLit();
            if (num_parts == 1) return self.parseSExpr(parts[0]);
            const op = parts[0];

            // === NOUVEAU CODE QUOTE/UNQUOTE ===
            if (std.mem.eql(u8, op, "quote") and num_parts > 1) {
                const inner_id = try self.parseSExpr(parts[1]);
                return self.store.quote(inner_id);
            }
            if (std.mem.eql(u8, op, "unquote") and num_parts > 1) {
                const inner_id = try self.parseSExpr(parts[1]);
                return self.store.unquote(inner_id);
            }
            // ==================================

            // === EFFETS ALGÉBRIQUES ===
            if (std.mem.eql(u8, op, "perform") and num_parts >= 2) {
                const effect_name = parts[1];
                var args: std.ArrayListUnmanaged(Id) = .{};
                defer args.deinit(self.allocator);
                for (parts[2..num_parts]) |p| {
                    try args.append(self.allocator, try self.parseSExpr(p));
                }
                return self.store.perform(effect_name, args.items);
            }
            if (std.mem.eql(u8, op, "handle") and num_parts == 3) {
                const body_id = try self.parseSExpr(parts[1]);
                const handler_id = try self.parseSExpr(parts[2]);
                return self.store.handle(body_id, handler_id);
            }
            // ============================

            if (std.mem.eql(u8, op, "eval") and num_parts > 1) {
                const inner_id = try self.parseSExpr(parts[1]);
                return engine_expr.evaluate(self.store, self.env, self.engine, inner_id, 0) catch inner_id;
            }
            if (std.mem.eql(u8, op, "let") and num_parts >= 3) {
                const sym = try self.store.interner.intern(parts[1]);
                const val_id = try self.parseSExpr(parts[2]);
                if (num_parts == 3) return self.store.bindSym(sym, val_id);
                const body_id = try self.parseSExpr(parts[3]);
                return self.store.bindSymWithBody(sym, val_id, body_id);
            }
            if (std.mem.eql(u8, op, "while") and num_parts == 3) return self.store.binop("while", try self.parseSExpr(parts[1]), try self.parseSExpr(parts[2]));
            if (std.mem.eql(u8, op, "if") and num_parts == 4) return self.store.call("if", &.{ try self.parseSExpr(parts[1]), try self.parseSExpr(parts[2]), try self.parseSExpr(parts[3]) });
            if (std.mem.eql(u8, op, "break") and num_parts == 2) return self.store.call("break", &.{try self.parseSExpr(parts[1])});
            if (num_parts == 3) {
                if (std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "-") or std.mem.eql(u8, op, "*") or
                    std.mem.eql(u8, op, "/") or std.mem.eql(u8, op, "^") or std.mem.eql(u8, op, "<") or
                    std.mem.eql(u8, op, "=") or
                    std.mem.eql(u8, op, "=="))
                {
                    return self.store.binop(op, try self.parseSExpr(parts[1]), try self.parseSExpr(parts[2]));
                }
            }
            var arg_ids: [15]Id = undefined;
            var ai: usize = 0;
            for (parts[1..num_parts]) |p| {
                arg_ids[ai] = try self.parseSExpr(p);
                ai += 1;
            }

            const op_sym = try self.store.sym(op);
            return self.store.apply(op_sym, arg_ids[0..ai]);
        }

        // Syntaxe if algébrique
        if (std.mem.startsWith(u8, trimmed, "if ")) {
            const rest = trimmed["if ".len..];
            if (findKeywordAtRoot(rest, " then ")) |then_pos| {
                const cond_str = std.mem.trim(u8, rest[0..then_pos], " ");
                const after_then = rest[then_pos + " then ".len ..];
                if (findKeywordAtRoot(after_then, " else ")) |else_pos| {
                    const then_str = std.mem.trim(u8, after_then[0..else_pos], " ");
                    const else_str = std.mem.trim(u8, after_then[else_pos + " else ".len ..], " ");
                    return self.store.call("if", &.{ try self.parseSExpr(cond_str), try self.parseSExpr(then_str), try self.parseSExpr(else_str) });
                }
            }
            return self.store.sym(trimmed);
        }

        // Opérateur ==
        if (std.mem.indexOf(u8, trimmed, "==")) |idx| {
            if (idx > 0 and idx + 2 < trimmed.len) {
                const lhs = std.mem.trim(u8, trimmed[0..idx], " ");
                const rhs = std.mem.trim(u8, trimmed[idx + 2 ..], " ");
                if (lhs.len > 0 and rhs.len > 0) return self.store.binop("==", try self.parseSExpr(lhs), try self.parseSExpr(rhs));
            }
        }

        // Opérateurs binaires sans parenthèses
        const binary_ops = [_][]const u8{ "<", "=", "+", "-", "*", "/", "^" };
        for (binary_ops) |op| {
            if (std.mem.indexOfScalar(u8, trimmed, op[0])) |idx| {
                if (idx > 0 and idx < trimmed.len - 1) {
                    const lhs = std.mem.trim(u8, trimmed[0..idx], " ");
                    const rhs = std.mem.trim(u8, trimmed[idx + 1 ..], " ");
                    if (lhs.len > 0 and rhs.len > 0) return self.store.binop(op, try self.parseSExpr(lhs), try self.parseSExpr(rhs));
                }
            }
        }

        // Juxtaposition : "f x y" -> apply(f, [x, y]) si f est une fonction enregistrée
        if (std.mem.indexOfScalar(u8, trimmed, ' ')) |space| {
            const func_name = trimmed[0..space];
            const arg_str = std.mem.trim(u8, trimmed[space + 1 ..], " ");
            if (func_name.len > 0 and arg_str.len > 0) {
                const is_registered = self.engine.fns.getEntry(func_name) != null;
                if (is_registered) {
                    var arg_ids: std.ArrayListUnmanaged(Id) = .{};
                    defer arg_ids.deinit(self.allocator);
                    var depth: i32 = 0;
                    var start: usize = 0;
                    for (arg_str, 0..) |ch, i| {
                        switch (ch) {
                            '(' => depth += 1,
                            ')' => depth -= 1,
                            ' ' => {
                                if (depth == 0 and i > start) {
                                    const part = std.mem.trim(u8, arg_str[start..i], " ");
                                    if (part.len > 0) try arg_ids.append(self.allocator, try self.parseSExpr(part));
                                    start = i + 1;
                                }
                            },
                            else => {},
                        }
                    }
                    if (start < arg_str.len) {
                        const part = std.mem.trim(u8, arg_str[start..], " ");
                        if (part.len > 0) try arg_ids.append(self.allocator, try self.parseSExpr(part));
                    }
                    if (arg_ids.items.len > 0) {
                        const func_id = try self.store.sym(func_name);
                        return self.store.apply(func_id, arg_ids.items);
                    }
                } else {
                    const func_id = try self.store.sym(func_name);
                    const arg_id = try self.parseSExpr(arg_str);
                    return self.store.apply(func_id, &.{arg_id});
                }
            }
        }

        // Symbole simple
        return self.store.sym(trimmed);
    }

    pub fn parseLambda(self: *Parser, input: []const u8) (std.mem.Allocator.Error || error{NotALambda})!Id {
        var work = std.mem.trim(u8, input, " \t");
        if (work.len == 0) return error.NotALambda;
        const is_backslash = work[0] == '\\';
        const is_lambda_char = work[0] == 'λ';
        const arrow_pos = blk: {
            var i: usize = 0;
            while (i < work.len - 1) : (i += 1) {
                if ((work[i] == '-' or work[i] == '=') and work[i + 1] == '>') break :blk i;
            }
            break :blk null;
        };
        var param_str: []const u8 = undefined;
        var body_str: []const u8 = undefined;
        if (is_backslash or is_lambda_char) {
            const after_prefix = if (is_backslash) work[1..] else work[3..];
            const trimmed_prefix = std.mem.trimLeft(u8, after_prefix, " \t");
            const delim_pos: usize = 0;
            var punct_pos: usize = 0;
            var found = false;
            for (trimmed_prefix, 0..) |c, i| {
                if (found) break;
                // On cherche le premier '.' ou '=>' qui n'est PAS suivi d'un '\' ou 'λ'
                if (c == '.' or (c == '=' and i + 1 < trimmed_prefix.len and trimmed_prefix[i + 1] == '>')) {
                    punct_pos = i;
                    found = true;
                } else if (c == ' ' or c == '\t') {
                    // Si c'est un espace, vérifier que ce n'est pas "\x " ou "λ "
                    const prev = if (i > 0) trimmed_prefix[i - 1] else 0;
                    if (prev != '\\' and prev != 'λ') {
                        punct_pos = i;
                        found = true;
                    }
                } else {
                    punct_pos = i + 1;
                }
            }
            param_str = std.mem.trim(u8, trimmed_prefix[0..delim_pos], " \t");
            var body_start = punct_pos;
            if (body_start < trimmed_prefix.len and (trimmed_prefix[body_start] == '-' or trimmed_prefix[body_start] == '=')) {
                body_start += 2; // skip -> ou =>
            } else if (body_start < trimmed_prefix.len and trimmed_prefix[body_start] == '.') {
                body_start += 1; // skip .
            }
            body_str = std.mem.trimLeft(u8, trimmed_prefix[body_start..], " \t");
        } else if (arrow_pos) |apos| {
            param_str = std.mem.trim(u8, work[0..apos], " \t");
            body_str = std.mem.trimLeft(u8, work[apos + 2 ..], " \t");
            for (param_str) |c| {
                if (!std.ascii.isAlphanumeric(c) and c != '_') return error.NotALambda;
            }
        } else return error.NotALambda;
        if (param_str.len == 0 or body_str.len == 0) return error.NotALambda;
        const body_id = self.parseLambda(body_str) catch |err| {
            if (err == error.NotALambda) return self.parseLetExpr(body_str);
            return err;
        };
        return self.store.lambdaNative(&.{param_str}, body_id);
    }

    pub fn parseLetExpr(self: *Parser, input: []const u8) (std.mem.Allocator.Error || error{NotALambda})!Id {
        var work = input;
        if (std.mem.startsWith(u8, work, "let ")) work = std.mem.trimLeft(u8, work[4..], " \t");
        if (std.mem.indexOf(u8, work, " in ")) |pos| {
            const lhs_str = std.mem.trim(u8, work[0..pos], " \t");
            const body_str = std.mem.trim(u8, work[pos + 4 ..], " \t");
            var eq_pos: ?usize = null;
            var i: usize = lhs_str.len;
            while (i > 0) : (i -= 1) {
                if (lhs_str[i - 1] == '=') {
                    const next_c = if (i < lhs_str.len) lhs_str[i] else ' ';
                    const prev_c = if (i >= 2) lhs_str[i - 2] else ' ';
                    if (next_c != '=' and prev_c != '!' and prev_c != '<' and prev_c != '>') {
                        eq_pos = i - 1;
                        break;
                    }
                }
            }
            if (eq_pos) |eq| {
                const name = std.mem.trim(u8, lhs_str[0..eq], " \t");
                const rhs_str = std.mem.trim(u8, lhs_str[eq + 1 ..], " \t");
                const rhs_id = if (self.parseLambda(rhs_str)) |id| id else |_| try self.parseSExpr(rhs_str);
                const body_id = try self.parseLetExpr(body_str);
                return self.store.letIn(name, rhs_id, body_id);
            }
        }
        return self.store.sym(work);
    }

    pub fn preprocessCallSyntax(self: *Parser, input: []const u8) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(self.allocator);
        var i: usize = 0;
        while (i < input.len) {
            if (input[i] == '(') {
                var start = i;
                while (start > 0 and input[start - 1] != ' ' and input[start - 1] != '(') start -= 1;
                const func_name = input[start..i];
                try buf.append(self.allocator, '(');
                try buf.appendSlice(self.allocator, func_name);
                try buf.append(self.allocator, ' ');
                i += 1;
                var depth: u32 = 1;
                var arg_start = i;
                while (i < input.len and depth > 0) {
                    switch (input[i]) {
                        '(' => depth += 1,
                        ')' => depth -= 1,
                        ',' => {
                            if (depth == 1) {
                                const arg = input[arg_start..i];
                                const processed = try self.preprocessCallSyntax(arg);
                                defer self.allocator.free(processed);
                                try buf.appendSlice(self.allocator, processed);
                                try buf.append(self.allocator, ' ');
                                arg_start = i + 1;
                            }
                        },
                        else => {},
                    }
                    i += 1;
                }
                if (arg_start < i - 1) {
                    const arg = input[arg_start .. i - 1];
                    const processed = try self.preprocessCallSyntax(arg);
                    defer self.allocator.free(processed);
                    try buf.appendSlice(self.allocator, processed);
                }
                try buf.append(self.allocator, ')');
            } else {
                try buf.append(self.allocator, input[i]);
                i += 1;
            }
        }
        return buf.toOwnedSlice(self.allocator);
    }

    pub fn commasToLisp(self: *Parser, input: []const u8) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(self.allocator);
        var i: usize = 0;
        var depth: u32 = 0;
        var in_paren = false;
        while (i < input.len) {
            switch (input[i]) {
                '(' => {
                    try buf.append(self.allocator, '(');
                    depth += 1;
                    if (depth == 1) in_paren = true;
                    i += 1;
                },
                ')' => {
                    try buf.append(self.allocator, ')');
                    if (depth > 0) depth -= 1;
                    if (depth == 0) in_paren = false;
                    i += 1;
                },
                ',' => {
                    if (in_paren) try buf.append(self.allocator, ' ') else try buf.append(self.allocator, ',');
                    i += 1;
                },
                else => {
                    try buf.append(self.allocator, input[i]);
                    i += 1;
                },
            }
        }
        return buf.toOwnedSlice(self.allocator);
    }
};
