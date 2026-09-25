//! ExprParser — parseur d'expressions Heaven.
//!
//! Extrait de `heaven_expr.zig` pour préparer RFC-0001. Le parseur
//! ne dépend d'aucune méthode de `Heaven` ; il opère sur un `Store`,
//! un `Allocator`, et un `HoleState`. La gestion de `last_root_expr`
//! se fait via un pointeur vers le champ `Heaven.last_root_expr`.

const std = @import("std");
const expr = @import("expr");
const platform = @import("platform");
const hole_mod = @import("hole");

const Store = expr.Store;
const Id = expr.Id;

pub const ExprParser = struct {
    store: *Store,
    allocator: std.mem.Allocator,
    hole_state: *hole_mod.HoleState,
    /// Pointeur vers `Heaven.last_root_expr`. Mis à jour quand `_`
    /// est parsé au top-level.
    last_root_expr: *?Id,

    pub fn init(
        store: *Store,
        allocator: std.mem.Allocator,
        hole_state: *hole_mod.HoleState,
        last_root_expr: *?Id,
    ) ExprParser {
        return .{
            .store = store,
            .allocator = allocator,
            .hole_state = hole_state,
            .last_root_expr = last_root_expr,
        };
    }

    fn freshHole(self: *ExprParser) !Id {
        const id = try self.hole_state.fresh(self.store);
        self.hole_state.last_root_expr = self.last_root_expr.*;
        return id;
    }

    pub fn parseExpression(self: *ExprParser, input: []const u8) anyerror!Id {
        const trimmed = std.mem.trim(u8, input, " \t");
        if (trimmed.len == 0) return error.InvalidInput;

        // ─── Trou : `_` seul ───
        if (std.mem.eql(u8, trimmed, "_")) {
            const hole_node = try self.freshHole();
            self.last_root_expr.* = hole_node;
            return hole_node;
        }

        // ─── Syntaxe courte lambda : `λx.body` ou `\x.body` ───
        // `λ` en UTF-8 fait 2 bytes (0xCE 0xBB) — comparer avec startsWith,
        // JAMAIS avec `trimmed[0] == 'λ'` (Zig interprète 'λ' comme codepoint u21,
        // pas comme byte).
        const is_unicode_lambda = std.mem.startsWith(u8, trimmed, "λ");
        const is_ascii_lambda = trimmed.len > 0 and trimmed[0] == '\\';
        if (is_unicode_lambda or is_ascii_lambda) {
            const prefix_len: usize = if (is_unicode_lambda) 2 else 1;
            const dot_pos = std.mem.indexOfScalar(u8, trimmed, '.') orelse
                return error.InvalidLambda;
            if (dot_pos <= prefix_len) return error.InvalidLambda;
            const param = trimmed[prefix_len..dot_pos];
            const body_str = std.mem.trim(u8, trimmed[dot_pos + 1 ..], " \t");
            if (param.len == 0 or body_str.len == 0) return error.InvalidLambda;
            const body_id = try self.parseExpression(body_str);
            return try self.store.lambdaNative(&.{param}, body_id);
        }

        // Unicode : x² → x^2
        if (expr.containsSuperscript(trimmed)) {
            const normalized = try expr.normalizeUnicodePowers(trimmed, self.allocator);
            defer self.allocator.free(normalized);
            return self.parseExpression(normalized);
        }

        // SYNTAXE NATIVE : tout ce qui ne commence pas par '('
        if (trimmed[0] != '(') {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            const sexpr = expr.nativeToSExpr(trimmed, arena.allocator()) catch {
                // Fallback : "func arg1 arg2" non parsable en infixe → wrapper S-expr
                if (std.mem.indexOfScalar(u8, trimmed, ' ') != null) {
                    const wrapped = std.fmt.allocPrint(self.allocator, "({s})", .{trimmed}) catch
                        return self.store.sym(trimmed);
                    defer self.allocator.free(wrapped);
                    return self.parseExpression(wrapped) catch self.store.sym(trimmed);
                }
                return self.store.sym(trimmed);
            };
            if (sexpr.len > 0 and sexpr[0] == '(') {
                // Forme composée → re-parser en Lisp (récursion sûre)
                const owned = try self.allocator.dupe(u8, sexpr);
                defer self.allocator.free(owned);
                return self.parseExpression(owned);
            }
            // Atome (nombre, identifiant, string) — interner duplique la chaîne ✓
            if (std.fmt.parseInt(i64, sexpr, 10)) |val| {
                return self.store.int(val);
            } else |_| {}

            // Flottant : "3.14"
            if (std.fmt.parseFloat(f64, sexpr)) |val| {
                return self.store.float(val);
            } else |_| {}

            // Booléens : "true" / "false"
            if (std.mem.eql(u8, sexpr, "true")) return self.store.boolean(true);
            if (std.mem.eql(u8, sexpr, "false")) return self.store.boolean(false);

            // Chaîne : "..."
            if (sexpr.len >= 2 and sexpr[0] == '"' and sexpr[sexpr.len - 1] == '"') {
                const inner = sexpr[1 .. sexpr.len - 1];
                const s = try self.store.interner.intern(inner);
                return self.store.lit(.{ .str = s });
            }

            return self.store.sym(sexpr);
        }

        // 1. Entier
        if (std.fmt.parseInt(i64, trimmed, 10)) |val| {
            return self.store.int(val);
        } else |_| {}

        // 2. Si commence par '(' → S-expression
        if (trimmed[0] == '(') {
            var depth: usize = 0;
            var i: usize = 0;
            while (i < trimmed.len) {
                if (trimmed[i] == '(') {
                    depth += 1;
                } else if (trimmed[i] == ')') {
                    depth -= 1;
                    if (depth == 0) break;
                }
                i += 1;
            }
            if (i >= trimmed.len or trimmed[i] != ')') return error.InvalidSyntax;

            const trailing = std.mem.trim(u8, trimmed[i + 1 ..], " \t");
            if (trailing.len > 0) {
                // Cas opérateur infixe après parenthèses : (X)^Y, (X)+Y, ...
                // → déléguer au Pratt parser natif qui gère la précédence.
                const op_chars = "^*+-/<>=";
                if (std.mem.indexOfScalar(u8, op_chars, trailing[0]) != null) {
                    var arena = std.heap.ArenaAllocator.init(self.allocator);
                    defer arena.deinit();
                    const sexpr = expr.nativeToSExpr(trimmed, arena.allocator()) catch {
                        return error.InvalidSyntax;
                    };
                    const owned = try self.allocator.dupe(u8, sexpr);
                    defer self.allocator.free(owned);
                    return self.parseExpression(owned);
                }

                // Fallback : juxtaposition ((X) Y Z) → groupement
                const wrapped = try std.fmt.allocPrint(self.allocator, "({s} {s})", .{ trimmed[0 .. i + 1], trailing });
                defer self.allocator.free(wrapped);
                return self.parseExpression(wrapped);
            }

            const inner = trimmed[1..i];
            return self.parseSExpr(inner);
        }

        // 3. NOUVEAU : Détecter les opérateurs infixes (^, +, -, *, /)
        // Priorité : ^ > * = / > + = -

        // Chercher ^ (puissance) - priorité la plus haute
        if (std.mem.indexOfScalar(u8, trimmed, '^')) |pos| {
            const lhs_str = std.mem.trim(u8, trimmed[0..pos], " ");
            const rhs_str = std.mem.trim(u8, trimmed[pos + 1 ..], " ");
            if (lhs_str.len > 0 and rhs_str.len > 0) {
                const lhs = try self.parseExpression(lhs_str);
                const rhs = try self.parseExpression(rhs_str);
                const pow_sym = try self.store.sym("^");
                return self.store.apply(pow_sym, &.{ lhs, rhs });
            }
        }

        // Chercher + ou - (binaire) - priorité la plus basse
        // Attention : ne pas confondre avec - unaire (ex: -5)
        var depth: usize = 0;
        var plus_pos: ?usize = null;
        var minus_pos: ?usize = null;
        var i: usize = 0;
        while (i < trimmed.len) {
            switch (trimmed[i]) {
                '(' => depth += 1,
                ')' => depth -= 1,
                '+', '-' => {
                    if (depth == 0 and i > 0) {
                        // Pas en début de chaîne (sinon c'est unaire)
                        if (trimmed[i] == '+') plus_pos = i else minus_pos = i;
                    }
                },
                else => {},
            }
            i += 1;
        }

        // Préférer + ou - le plus à droite (associativité à gauche)
        if (minus_pos) |pos| {
            const lhs_str = std.mem.trim(u8, trimmed[0..pos], " ");
            const rhs_str = std.mem.trim(u8, trimmed[pos + 1 ..], " ");
            if (lhs_str.len > 0 and rhs_str.len > 0) {
                const lhs = try self.parseExpression(lhs_str);
                const rhs = try self.parseExpression(rhs_str);
                const op_sym = try self.store.sym("-");
                return self.store.apply(op_sym, &.{ lhs, rhs });
            }
        }
        if (plus_pos) |pos| {
            const lhs_str = std.mem.trim(u8, trimmed[0..pos], " ");
            const rhs_str = std.mem.trim(u8, trimmed[pos + 1 ..], " ");
            if (lhs_str.len > 0 and rhs_str.len > 0) {
                const lhs = try self.parseExpression(lhs_str);
                const rhs = try self.parseExpression(rhs_str);
                const op_sym = try self.store.sym("+");
                return self.store.apply(op_sym, &.{ lhs, rhs });
            }
        }

        // Chercher * ou /
        depth = 0;
        i = 0;
        var mul_pos: ?usize = null;
        var div_pos: ?usize = null;
        while (i < trimmed.len) {
            switch (trimmed[i]) {
                '(' => depth += 1,
                ')' => depth -= 1,
                '*' => {
                    if (depth == 0) mul_pos = i;
                },
                '/' => {
                    if (depth == 0) div_pos = i;
                },
                else => {},
            }
            i += 1;
        }

        if (div_pos) |pos| {
            const lhs_str = std.mem.trim(u8, trimmed[0..pos], " ");
            const rhs_str = std.mem.trim(u8, trimmed[pos + 1 ..], " ");
            if (lhs_str.len > 0 and rhs_str.len > 0) {
                const lhs = try self.parseExpression(lhs_str);
                const rhs = try self.parseExpression(rhs_str);
                const op_sym = try self.store.sym("/");
                return self.store.apply(op_sym, &.{ lhs, rhs });
            }
        }
        if (mul_pos) |pos| {
            const lhs_str = std.mem.trim(u8, trimmed[0..pos], " ");
            const rhs_str = std.mem.trim(u8, trimmed[pos + 1 ..], " ");
            if (lhs_str.len > 0 and rhs_str.len > 0) {
                const lhs = try self.parseExpression(lhs_str);
                const rhs = try self.parseExpression(rhs_str);
                const op_sym = try self.store.sym("*");
                return self.store.apply(op_sym, &.{ lhs, rhs });
            }
        }

        // 4. Sinon → symbole simple
        return self.store.sym(trimmed);
    }

    fn parseSExpr(self: *ExprParser, inner: []const u8) anyerror!Id {
        var tokens: std.ArrayListUnmanaged([]const u8) = .{};
        defer tokens.deinit(self.allocator);

        var depth: usize = 0;
        var start: usize = 0;
        var in_token = false;
        var in_str = false;
        for (inner, 0..) |ch, idx| {
            if (in_str) {
                if (ch == '"') in_str = false;
                continue;
            }
            switch (ch) {
                '"' => {
                    if (depth == 0 and !in_token) {
                        start = idx;
                        in_token = true;
                    }
                    in_str = true;
                },
                '(' => {
                    if (depth == 0 and !in_token) {
                        start = idx;
                        in_token = true;
                    }
                    depth += 1;
                },
                ')' => {
                    depth -= 1;
                    if (depth == 0 and in_token) {
                        try tokens.append(self.allocator, inner[start .. idx + 1]);
                        in_token = false;
                        start = idx + 1;
                    }
                },
                ' ' => {
                    if (depth == 0 and in_token) {
                        try tokens.append(self.allocator, inner[start..idx]);
                        in_token = false;
                        start = idx + 1;
                    }
                },
                else => {
                    if (depth == 0 and !in_token) {
                        start = idx;
                        in_token = true;
                    }
                },
            }
        }
        if (in_token and depth == 0) {
            try tokens.append(self.allocator, inner[start..]);
        }

        if (tokens.items.len == 0) return error.InvalidSyntax;

        const first = tokens.items[0];
        //platform.dbg("[parseSExpr] first token: '{s}' (len={d})\n", .{ first, first.len });

        // Un trou en position de tête : pas une application.
        if (std.mem.eql(u8, first, "_")) {
            if (tokens.items.len == 1) return self.freshHole();
            return error.InvalidSyntax;
        }

        // Lambda inline multi-token : `\x. body` (body sur 1+ tokens)
        // Cas `["\x.", "x", "+", "1"]` pour `\x. x + 1`.
        // Doit être AVANT la détection infixe (sinon `+` court-circuite).
        if (first.len > 0 and (first[0] == '\\' or std.mem.startsWith(u8, first, "λ"))) {
            if (std.mem.indexOfScalar(u8, first, '.')) |dot_pos| {
                const prefix_len: usize = if (std.mem.startsWith(u8, first, "λ")) 2 else 1;
                if (dot_pos > prefix_len) {
                    const param = first[prefix_len..dot_pos];
                    const body_head = first[dot_pos + 1 ..];
                    var body_buf = std.ArrayListUnmanaged(u8){};
                    defer body_buf.deinit(self.allocator);
                    try body_buf.appendSlice(self.allocator, body_head);
                    for (tokens.items[1..]) |t| {
                        try body_buf.append(self.allocator, ' ');
                        try body_buf.appendSlice(self.allocator, t);
                    }
                    if (body_buf.items.len > 0) {
                        const body_id = try self.parseExpression(body_buf.items);
                        return try self.store.lambdaNative(&.{param}, body_id);
                    }
                }
            }
        }

        // DÉTECTION INFIXE : un opérateur au milieu → syntaxe infixe
        // (x + 3) → apply(x, [+, 3]) serait faux → déléguer au parser natif
        if (tokens.items.len > 1) {
            for (tokens.items[1..]) |tok| {
                if (isInfixOp(tok)) {
                    var arena = std.heap.ArenaAllocator.init(self.allocator);
                    defer arena.deinit();
                    const sexpr = expr.nativeToSExpr(inner, arena.allocator()) catch {
                        return error.InvalidSyntax;
                    };
                    const owned = try self.allocator.dupe(u8, sexpr);
                    defer self.allocator.free(owned);
                    return self.parseExpression(owned);
                }
            }
        }

        // Cas 1 : le premier token est une sous‑expression entre parenthèses
        if (first.len > 0 and first[0] == '(') {
            const func_id = try self.parseExpression(first);
            var args = std.ArrayListUnmanaged(Id){};
            defer args.deinit(self.allocator);
            for (tokens.items[1..]) |arg_tok| {
                if (std.mem.eql(u8, arg_tok, "_")) {
                    try args.append(self.allocator, try self.freshHole());
                } else {
                    try args.append(self.allocator, try self.parseExpression(arg_tok));
                }
            }
            return self.store.apply(func_id, args.items);
        }

        // ─── Cas "λx.body" en un seul token (pas d'espace après λ) ───
        const is_unicode_lambda = std.mem.startsWith(u8, first, "λ");
        const is_ascii_lambda = first.len > 0 and first[0] == '\\';
        if ((is_unicode_lambda or is_ascii_lambda) and tokens.items.len == 1) {
            if (std.mem.indexOfScalar(u8, first, '.')) |dot_pos| {
                const prefix_len: usize = if (is_unicode_lambda) 2 else 1;
                if (dot_pos > prefix_len) {
                    const param = first[prefix_len..dot_pos];
                    const body_str = first[dot_pos + 1 ..];
                    if (param.len > 0 and body_str.len > 0) {
                        const body_id = try self.parseExpression(body_str);
                        return try self.store.lambdaNative(&.{param}, body_id);
                    }
                }
            }
        }

        // Cas 2 : lambda
        const is_lambda = std.mem.eql(u8, first, "λ") or
            std.mem.eql(u8, first, "\\") or
            std.mem.eql(u8, first, "lambda") or
            std.mem.eql(u8, first, "Lambda");

        if (is_lambda) {
            platform.dbg("[parseSExpr] detected lambda\n", .{});
            if (tokens.items.len < 3) return error.InvalidLambda;
            const body_str = tokens.items[tokens.items.len - 1];
            const body_id = try self.parseExpression(body_str);
            const params = tokens.items[1 .. tokens.items.len - 1];
            if (params.len == 0) return error.InvalidLambda;
            const param_name = params[0];
            const result = try self.store.lambdaNative(&.{param_name}, body_id);
            platform.dbg("[parseSExpr] created lambda id = {d}\n", .{result});
            return result;
        }

        // QTT : let avec multiplicité
        //   (let-linear x v b)       — 1 usage exact
        //   (let-erased x v b)       — 0 usage
        //   (let-many   x v b)       — aucune contrainte
        //   (let linear x = v in b)  — forme "native" injectée en S-expr
        //   (let erased x = v in b)
        //   (let many   x = v in b)
        {
            var kw: ?[]const u8 = null;
            var qtt_name: []const u8 = "";
            var qtt_val: []const u8 = "";
            var qtt_body: ?expr.Id = null;

            if (std.mem.eql(u8, first, "let-linear") and tokens.items.len == 4) {
                kw = "linear";
                qtt_name = tokens.items[1];
                qtt_val = tokens.items[2];
                qtt_body = try self.parseExpression(tokens.items[3]);
            } else if (std.mem.eql(u8, first, "let-erased") and tokens.items.len == 4) {
                kw = "erased";
                qtt_name = tokens.items[1];
                qtt_val = tokens.items[2];
                qtt_body = try self.parseExpression(tokens.items[3]);
            } else if (std.mem.eql(u8, first, "let-many") and tokens.items.len == 4) {
                kw = "many";
                qtt_name = tokens.items[1];
                qtt_val = tokens.items[2];
                qtt_body = try self.parseExpression(tokens.items[3]);
            } else if (std.mem.eql(u8, first, "let") and tokens.items.len >= 7) {
                const k = tokens.items[1];
                const is_kw = std.mem.eql(u8, k, "linear") or std.mem.eql(u8, k, "erased") or std.mem.eql(u8, k, "many");
                if (is_kw and std.mem.eql(u8, tokens.items[3], "=") and std.mem.eql(u8, tokens.items[5], "in")) {
                    kw = k;
                    qtt_name = tokens.items[2];
                    qtt_val = tokens.items[4];

                    var body_buf = std.ArrayListUnmanaged(u8){};
                    defer body_buf.deinit(self.allocator);
                    for (tokens.items[6..], 0..) |t, i| {
                        if (i > 0) try body_buf.append(self.allocator, ' ');
                        try body_buf.appendSlice(self.allocator, t);
                    }
                    qtt_body = try self.parseExpression(body_buf.items);
                }
            }

            if (kw) |k| {
                const b = qtt_body.?;
                const uses = expr.countSymUses(self.store, b, qtt_name);

                const ok = if (std.mem.eql(u8, k, "linear"))
                    uses == 1
                else if (std.mem.eql(u8, k, "erased"))
                    uses == 0
                else
                    true; // many : aucune contrainte

                if (!ok) return error.LinearViolation;

                const val_id = try self.parseExpression(qtt_val);
                const name_sym = try self.store.interner.intern(qtt_name);
                // Représentation Core : bind(name, val, body)
                return try self.store.bindSymWithBody(name_sym, val_id, b);
            }
        }

        // Cas 3 : application normale
        const func_id = try self.store.sym(first);
        var args = std.ArrayListUnmanaged(Id){};
        defer args.deinit(self.allocator);
        for (tokens.items[1..]) |arg_tok| {
            if (std.mem.eql(u8, arg_tok, "_")) {
                try args.append(self.allocator, try self.freshHole());
            } else {
                try args.append(self.allocator, try self.parseExpression(arg_tok));
            }
        }
        return self.store.apply(func_id, args.items);
    }

};

fn isInfixOp(tok: []const u8) bool {
    const ops = [_][]const u8{ "+", "-", "*", "/", "^", "%", "==", "!=", "<", ">", "<=", ">=", ">>>" };
    for (ops) |o| {
        if (std.mem.eql(u8, tok, o)) return true;
    }
    return false;
}
