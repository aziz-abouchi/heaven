//! Bridge entre le parseur MLCPD/Tree-sitter et le système Expr de Heaven

const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;

pub const MatrixBridge = struct {
    store: *Store,
    allocator: Allocator,

    pub fn init(store: *Store, allocator: Allocator) MatrixBridge {
        return .{
            .store = store,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MatrixBridge) void {
        _ = self;
    }

    /// Parse une expression textuelle en Expr
    pub fn importExpr(self: *MatrixBridge, text: []const u8) Allocator.Error!Id {
        const trimmed = std.mem.trim(u8, text, " \t\n\r");
        if (trimmed.len == 0) return self.store.unitLit();
        return self.parseAddSub(trimmed);
    }

    fn parseAddSub(self: *MatrixBridge, input: []const u8) Allocator.Error!Id {
        var depth: i32 = 0;
        var i: usize = input.len;

        while (i > 0) : (i -= 1) {
            const idx = i - 1;
            const ch = input[idx];

            switch (ch) {
                ')' => depth += 1,
                '(' => depth -= 1,
                '+', '-' => if (depth == 0 and idx > 0) {
                    const prev = input[idx - 1];
                    const is_arrow = (ch == '-' and idx + 1 < input.len and input[idx + 1] == '>');
                    if (prev != '(' and prev != ',' and !is_arrow) {
                        const lhs = try self.parseAddSub(std.mem.trim(u8, input[0..idx], " "));
                        const rhs = try self.parseMulDiv(std.mem.trim(u8, input[idx + 1 ..], " "));
                        const op_str = if (ch == '+') "+" else "-";
                        return self.store.binop(op_str, lhs, rhs);
                    }
                },
                else => {},
            }
        }

        return self.parseMulDiv(input);
    }

    fn parseMulDiv(self: *MatrixBridge, input: []const u8) Allocator.Error!Id {
        var depth: i32 = 0;
        var i: usize = input.len;

        while (i > 0) : (i -= 1) {
            const idx = i - 1;
            const ch = input[idx];

            switch (ch) {
                ')' => depth += 1,
                '(' => depth -= 1,
                '*', '/' => if (depth == 0 and idx > 0) {
                    const prev = input[idx - 1];
                    if (prev != '(' and prev != ',') {
                        const lhs = try self.parseMulDiv(std.mem.trim(u8, input[0..idx], " "));
                        const rhs = try self.parseComparison(std.mem.trim(u8, input[idx + 1 ..], " "));
                        const op_str = if (ch == '*') "*" else "/";
                        return self.store.binop(op_str, lhs, rhs);
                    }
                },
                else => {},
            }
        }

        return self.parseComparison(input);
    }

    fn parseComparison(self: *MatrixBridge, input: []const u8) Allocator.Error!Id {
        const ops = [_][]const u8{ "==", "!=", "<=", ">=", "<", ">" };
        var depth: i32 = 0;

        for (ops) |op| {
            var i: usize = 0;
            while (i + op.len <= input.len) : (i += 1) {
                const ch = input[i];
                if (ch == '(') {
                    depth += 1;
                } else if (ch == ')') {
                    depth -= 1;
                } else if (depth == 0 and std.mem.startsWith(u8, input[i..], op)) {
                    if (op.len == 1 and op[0] == '>' and i > 0 and (input[i - 1] == '=' or input[i - 1] == '-')) {
                        continue;
                    }
                    if (op.len == 1 and op[0] == '<' and i + 1 < input.len and input[i + 1] == '=') {
                        continue;
                    }
                    const lhs = try self.parseAtom(std.mem.trim(u8, input[0..i], " "));
                    const rhs = try self.parseAtom(std.mem.trim(u8, input[i + op.len ..], " "));
                    return self.store.binop(op, lhs, rhs);
                }
            }
        }
        return self.parseAtom(input);
    }

    fn parseAtom(self: *MatrixBridge, input: []const u8) Allocator.Error!Id {
        const trimmed = std.mem.trim(u8, input, " \t");

        // === EFFETS ALGÉBRIQUES ===
        if (std.mem.startsWith(u8, trimmed, "handle ") or std.mem.startsWith(u8, trimmed, "handle(")) {
            // On extrait le corps et le handler
            const start = std.mem.indexOfScalar(u8, trimmed, '(') orelse return self.store.sym(trimmed);
            const end = std.mem.lastIndexOfScalar(u8, trimmed, ')') orelse return self.store.sym(trimmed);
            if (end > start) {
                const inner = std.mem.trim(u8, trimmed[start + 1 .. end], " \t");
                // Trouver la séparation entre le corps et le handler
                // Le handler est le dernier argument (après le dernier espace à profondeur 0)
                var depth: i32 = 0;
                var split_pos: usize = 0;
                for (inner, 0..) |ch, i| {
                    switch (ch) {
                        '(' => depth += 1,
                        ')' => depth -= 1,
                        ' ' => if (depth == 0) {
                            split_pos = i;
                        },
                        else => {},
                    }
                }
                if (split_pos > 0) {
                    const body_str = std.mem.trim(u8, inner[0..split_pos], " \t");
                    const handler_str = std.mem.trim(u8, inner[split_pos + 1 ..], " \t");
                    const body_id = try self.parseAddSub(body_str);
                    const handler_id = try self.parseAddSub(handler_str);
                    return self.store.handle(body_id, handler_id);
                }
            }
            return self.store.sym(trimmed);
        }

        if (std.mem.startsWith(u8, trimmed, "perform ") or std.mem.startsWith(u8, trimmed, "perform(")) {
            const start = std.mem.indexOfScalar(u8, trimmed, '(') orelse return self.store.sym(trimmed);
            const end = std.mem.lastIndexOfScalar(u8, trimmed, ')') orelse return self.store.sym(trimmed);
            if (end > start) {
                const inner = std.mem.trim(u8, trimmed[start + 1 .. end], " \t");
                // Le premier mot est le nom de l'effet, le reste sont les arguments
                var it = std.mem.tokenizeAny(u8, inner, " ,");
                const effect_name = it.next() orelse return self.store.sym(trimmed);

                var args: std.ArrayListUnmanaged(Id) = .{};
                defer args.deinit(self.allocator);
                while (it.next()) |arg_str| {
                    try args.append(self.allocator, try self.parseAddSub(arg_str));
                }
                return self.store.perform(effect_name, args.items);
            }
            return self.store.sym(trimmed);
        }
        // ============================

        // Entier littéral
        if (std.fmt.parseInt(i64, trimmed, 10)) |v| return self.store.int(v) else |_| {}

        // Nombre à virgule (Float) - SEULEMENT s'il y a un point
        if (std.mem.indexOfScalar(u8, trimmed, '.') != null) {
            if (std.fmt.parseFloat(f64, trimmed)) |v| {
                return self.store.float(v);
            } else |_| {}
        }

        if (trimmed.len == 0) return self.store.unitLit();

        // Parenthesized expression
        if (trimmed.len >= 2 and trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')') {
            const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], " ");
            if (inner.len == 0) return self.store.unitLit();

            // Lambda detection
            if (std.mem.startsWith(u8, inner, "fun ") or std.mem.startsWith(u8, inner, "fn") or
                std.mem.startsWith(u8, inner, "λ") or std.mem.startsWith(u8, inner, "\\") or
                (inner.len > 0 and inner[0] == '|'))
            {
                var arrow_pos: ?usize = null;
                if (std.mem.indexOf(u8, inner, "=>")) |pos| {
                    arrow_pos = pos;
                } else if (std.mem.indexOf(u8, inner, "->")) |pos| {
                    arrow_pos = pos;
                }

                if (arrow_pos) |ap| {
                    var params_str: []const u8 = undefined;

                    if (std.mem.startsWith(u8, inner, "fun ")) {
                        params_str = std.mem.trim(u8, inner[4..ap], " ");
                    } else if (std.mem.startsWith(u8, inner, "fn")) {
                        const rest = inner[2..ap];
                        if (rest.len >= 2 and rest[0] == '(' and rest[rest.len - 1] == ')') {
                            params_str = std.mem.trim(u8, rest[1 .. rest.len - 1], " ");
                        } else {
                            params_str = std.mem.trim(u8, rest, " ");
                        }
                    } else if (std.mem.startsWith(u8, inner, "λ")) {
                        const rest = inner[2..ap];
                        if (rest.len >= 2 and rest[0] == '(' and rest[rest.len - 1] == ')') {
                            params_str = std.mem.trim(u8, rest[1 .. rest.len - 1], " ");
                        } else {
                            params_str = std.mem.trim(u8, rest, " ");
                        }
                    } else if (std.mem.startsWith(u8, inner, "\\")) {
                        const rest = inner[2..ap];
                        if (rest.len >= 2 and rest[0] == '(' and rest[rest.len - 1] == ')') {
                            params_str = std.mem.trim(u8, rest[1 .. rest.len - 1], " ");
                        } else {
                            params_str = std.mem.trim(u8, rest, " ");
                        }
                    } else if (inner[0] == '|') {
                        if (std.mem.indexOfScalar(u8, inner[1..], '|')) |end_pipe| {
                            params_str = std.mem.trim(u8, inner[1 .. end_pipe + 1], " ");
                        } else {
                            params_str = "";
                        }
                    } else {
                        params_str = "";
                    }

                    const body_str = std.mem.trim(u8, inner[ap + 2 ..], " ");

                    var params: std.ArrayListUnmanaged([]const u8) = .{};
                    defer params.deinit(self.allocator);
                    var pit = std.mem.tokenizeAny(u8, params_str, " ,");
                    while (pit.next()) |p| {
                        try params.append(self.allocator, p);
                    }

                    const body_id = try self.parseAddSub(body_str);
                    return self.store.lambda(params.items, body_id);
                }
            }

            // Lisp list parsing
            var parts: [16][]const u8 = undefined;
            var num_parts: usize = 0;
            var part_depth: i32 = 0;
            var part_start: usize = 0;

            for (inner, 0..) |ch, i| {
                switch (ch) {
                    '(' => part_depth += 1,
                    ')' => part_depth -= 1,
                    ' ', '\t' => if (part_depth == 0) {
                        const part = std.mem.trim(u8, inner[part_start..i], " ");
                        if (part.len > 0 and num_parts < 16) {
                            parts[num_parts] = part;
                            num_parts += 1;
                        }
                        part_start = i + 1;
                    },
                    else => {},
                }
            }
            const last_part = std.mem.trim(u8, inner[part_start..], " ");
            if (last_part.len > 0 and num_parts < 16) {
                parts[num_parts] = last_part;
                num_parts += 1;
            }

            if (num_parts >= 2) {
                const func_id = try self.parseAddSub(parts[0]);
                var arg_ids: std.ArrayListUnmanaged(Id) = .{};
                defer arg_ids.deinit(self.allocator);
                for (parts[1..num_parts]) |p| {
                    try arg_ids.append(self.allocator, try self.parseAddSub(p));
                }
                return self.store.apply(func_id, arg_ids.items);
            }

            return self.parseAddSub(inner);
        }

        // Integer
        if (std.fmt.parseInt(i64, trimmed, 10)) |v| return self.store.int(v) else |_| {}

        // Float - SEULEMENT s'il y a un point
        if (std.mem.indexOfScalar(u8, trimmed, '.') != null) {
            if (std.fmt.parseFloat(f64, trimmed)) |v| {
                return self.store.float(v);
            } else |_| {}
        }

        // Booleans
        if (std.mem.eql(u8, trimmed, "true")) return self.store.boolean(true);
        if (std.mem.eql(u8, trimmed, "false")) return self.store.boolean(false);

        // Lambda: fun x => body
        if (std.mem.startsWith(u8, trimmed, "fun ")) {
            const rest = trimmed[4..];
            if (std.mem.indexOf(u8, rest, "=>")) |arrow| {
                const params_str = std.mem.trim(u8, rest[0..arrow], " ");
                const body_str = std.mem.trim(u8, rest[arrow + 2 ..], " ");

                var params: std.ArrayListUnmanaged([]const u8) = .{};
                defer params.deinit(self.allocator);
                var pit = std.mem.tokenizeAny(u8, params_str, " ,");
                while (pit.next()) |p| {
                    try params.append(self.allocator, p);
                }

                const body_id = try self.parseAddSub(body_str);
                return self.store.lambda(params.items, body_id);
            }
        }

        // Lambda: fn(x) => body
        if (std.mem.startsWith(u8, trimmed, "fn(")) {
            if (std.mem.indexOfScalar(u8, trimmed, ')')) |close_paren| {
                const params_str = std.mem.trim(u8, trimmed[3..close_paren], " ");
                const after_paren = trimmed[close_paren + 1 ..];
                if (std.mem.indexOf(u8, after_paren, "=>")) |arrow| {
                    const body_str = std.mem.trim(u8, after_paren[arrow + 2 ..], " ");

                    var params: std.ArrayListUnmanaged([]const u8) = .{};
                    defer params.deinit(self.allocator);
                    var pit = std.mem.tokenizeAny(u8, params_str, " ,");
                    while (pit.next()) |p| {
                        try params.append(self.allocator, p);
                    }

                    const body_id = try self.parseAddSub(body_str);
                    return self.store.lambda(params.items, body_id);
                }
            }
        }

        // Lambda: λx => body or λ(x) => body
        if (trimmed.len > 0 and trimmed[0] == 'λ') {
            var params_str: []const u8 = undefined;
            var body_str: []const u8 = undefined;

            if (trimmed.len > 1 and trimmed[1] == '(') {
                if (std.mem.indexOfScalar(u8, trimmed, ')')) |close_paren| {
                    params_str = std.mem.trim(u8, trimmed[2..close_paren], " ");
                    const after_paren = trimmed[close_paren + 1 ..];
                    if (std.mem.indexOf(u8, after_paren, "=>")) |arrow| {
                        body_str = std.mem.trim(u8, after_paren[arrow + 2 ..], " ");
                    } else {
                        return self.store.sym(trimmed);
                    }
                } else {
                    return self.store.sym(trimmed);
                }
            } else {
                if (std.mem.indexOf(u8, trimmed, "=>")) |arrow| {
                    params_str = std.mem.trim(u8, trimmed[1..arrow], " ");
                    body_str = std.mem.trim(u8, trimmed[arrow + 2 ..], " ");
                } else {
                    return self.store.sym(trimmed);
                }
            }

            var params: std.ArrayListUnmanaged([]const u8) = .{};
            defer params.deinit(self.allocator);
            var pit = std.mem.tokenizeAny(u8, params_str, " ,");
            while (pit.next()) |p| {
                try params.append(self.allocator, p);
            }

            const body_id = try self.parseAddSub(body_str);
            return self.store.lambda(params.items, body_id);
        }

        // Lambda: |x| body
        if (trimmed.len > 0 and trimmed[0] == '|') {
            if (std.mem.indexOfScalar(u8, trimmed[1..], '|')) |close_pipe| {
                const params_str = std.mem.trim(u8, trimmed[1 .. close_pipe + 1], " ");
                const body_str = std.mem.trim(u8, trimmed[close_pipe + 2 ..], " ");

                var params: std.ArrayListUnmanaged([]const u8) = .{};
                defer params.deinit(self.allocator);
                var pit = std.mem.tokenizeAny(u8, params_str, " ,");
                while (pit.next()) |p| {
                    try params.append(self.allocator, p);
                }

                const body_id = try self.parseAddSub(body_str);
                return self.store.lambda(params.items, body_id);
            }
        }

        // Lambda: \x -> body (Haskell style)
        if (trimmed.len > 0 and trimmed[0] == '\\') {
            if (std.mem.indexOf(u8, trimmed, "->")) |arrow| {
                const params_str = std.mem.trim(u8, trimmed[1..arrow], " ");
                const body_str = std.mem.trim(u8, trimmed[arrow + 2 ..], " ");

                var params: std.ArrayListUnmanaged([]const u8) = .{};
                defer params.deinit(self.allocator);
                var pit = std.mem.tokenizeAny(u8, params_str, " ,");
                while (pit.next()) |p| {
                    try params.append(self.allocator, p);
                }

                const body_id = try self.parseAddSub(body_str);
                return self.store.lambda(params.items, body_id);
            }
        }

        // Quote: quote expr or 'expr
        if (std.mem.startsWith(u8, trimmed, "quote ")) {
            const expr_str = std.mem.trim(u8, trimmed[6..], " ");
            const expr_id = try self.parseFullExpr(expr_str);
            return self.store.quote(expr_id);
        }
        if (trimmed.len > 1 and trimmed[0] == '\'') {
            const expr_str = std.mem.trim(u8, trimmed[1..], " ");
            const expr_id = try self.parseFullExpr(expr_str);
            return self.store.quote(expr_id);
        }

        // Unquote: unquote expr or ,expr
        if (std.mem.startsWith(u8, trimmed, "unquote ")) {
            const expr_str = std.mem.trim(u8, trimmed[8..], " ");
            const expr_id = try self.parseFullExpr(expr_str);
            return self.store.unquote(expr_id);
        }
        if (trimmed.len > 1 and trimmed[0] == ',') {
            const expr_str = std.mem.trim(u8, trimmed[1..], " ");
            const expr_id = try self.parseFullExpr(expr_str);
            return self.store.unquote(expr_id);
        }

        // let x expr (Lisp format) or let x = expr
        if (std.mem.startsWith(u8, trimmed, "let ")) {
            const rest = trimmed[4..];

            if (std.mem.indexOfScalar(u8, rest, ' ')) |space_pos| {
                const name = std.mem.trim(u8, rest[0..space_pos], " ");
                const val_text = std.mem.trim(u8, rest[space_pos + 1 ..], " ");
                const val = try self.parseAddSub(val_text);
                return self.store.bind(name, val);
            }

            if (std.mem.indexOfScalar(u8, rest, '=')) |eq_pos| {
                const name = std.mem.trim(u8, rest[0..eq_pos], " ");
                const val_text = std.mem.trim(u8, rest[eq_pos + 1 ..], " ");
                const val = try self.parseAddSub(val_text);
                return self.store.bind(name, val);
            }
        }

        // Symbol
        return self.store.sym(trimmed);
    }

    fn parseFullExpr(self: *MatrixBridge, input: []const u8) Allocator.Error!Id {
        const trimmed = std.mem.trim(u8, input, " \t");
        if (trimmed.len == 0) return self.store.unitLit();

        // Pour quote, on veut juste parser la structure, pas évaluer
        if (trimmed.len >= 2 and trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')') {
            const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], " ");
            if (inner.len == 0) return self.store.unitLit();

            var parts: [16][]const u8 = undefined;
            var num_parts: usize = 0;
            var depth: i32 = 0;
            var start: usize = 0;

            for (inner, 0..) |ch, i| {
                if (ch == '(') {
                    depth += 1;
                } else if (ch == ')') {
                    depth -= 1;
                } else if ((ch == ' ' or ch == '\t') and depth == 0) {
                    const part = std.mem.trim(u8, inner[start..i], " ");
                    if (part.len > 0 and num_parts < 16) {
                        parts[num_parts] = part;
                        num_parts += 1;
                    }
                    start = i + 1;
                }
            }
            const last = std.mem.trim(u8, inner[start..], " ");
            if (last.len > 0 and num_parts < 16) {
                parts[num_parts] = last;
                num_parts += 1;
            }

            // Parser récursivement chaque partie
            if (num_parts >= 2) {
                const func_id = try self.parseFullExpr(parts[0]);
                var arg_ids: std.ArrayListUnmanaged(Id) = .{};
                defer arg_ids.deinit(self.allocator);
                for (parts[1..num_parts]) |p| {
                    try arg_ids.append(self.allocator, try self.parseFullExpr(p));
                }
                return self.store.apply(func_id, arg_ids.items);
            } else if (num_parts == 1) {
                return self.parseFullExpr(parts[0]);
            }
        }

        // Pour les atomes, utiliser parseAtom directement (pas parseAddSub)
        return self.parseAtom(trimmed);
    }
};
