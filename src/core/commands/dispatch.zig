//! dispatch.zig — Dispatcher eval de Commands (D4 batch 7, dernier).
//! Extrait de src/core/commands.zig. Voir docs/DECISIONS.md (D4).

const std = @import("std");
const expr = @import("expr");
const engine_expr = @import("engine_expr");
const canon_mod = @import("canon");
const platform = @import("platform");

const Store = expr.Store;
const Id = expr.Id;

pub fn eval(cmds: anytype, input: []const u8) anyerror![]u8 {
    const trimmed0 = std.mem.trim(u8, input, " \t\r\n");
    const actual = if (trimmed0.len > 0 and trimmed0[0] == ':') trimmed0[1..] else trimmed0;
    const trimmed = std.mem.trim(u8, actual, " \t\r\n");

    if (std.mem.startsWith(u8, trimmed, "module ") or
        std.mem.startsWith(u8, trimmed, "data ") or
        std.mem.startsWith(u8, trimmed, "zero :") or
        std.mem.startsWith(u8, trimmed, "succ :"))
    {
        return try cmds.allocator.dupe(u8, "()");
    }

    // Let : tout ce qui commence par "let " passe par un dispatch unifié.
    // - let actor X = ... with H
    // - let macro name(...) = ...
    // - let [linear|erased|many] x = v in b
    // - let x = v in b
    // - let x := v
    if (std.mem.startsWith(u8, trimmed, "let ")) {
        const after = trimmed["let ".len..];
        if (std.mem.startsWith(u8, after, "actor ")) {
            return cmds.evalActorDef(after["actor ".len..], cmds.env);
        }
        if (std.mem.startsWith(u8, after, "macro ")) {
            return cmds.evalMacroDef(after["macro ".len..]);
        }
        // let x = v in b, let linear x = v in b, let x := v
        if (std.mem.indexOf(u8, after, " in ") != null or
            std.mem.indexOf(u8, after, ":=") != null)
        {
            return cmds.evalLet(after);
        }
    }

    // === INTERCEPTION (simplify ...) avec parenthèses ===
    if (std.mem.startsWith(u8, trimmed, "(simplify ")) {
        const inner = trimmed["(simplify ".len .. trimmed.len - 1];
        return cmds.evalSimplify(inner);
    }

    if (std.mem.startsWith(u8, trimmed, "(test ") or std.mem.startsWith(u8, trimmed, "(assert_eq ")) {
        const id = try cmds.parser.parseSExpr(trimmed);
        cmds.engine.fuel = 1_000_000;
        const result = engine_expr.evaluate(cmds.store, cmds.env, cmds.engine, id, 0) catch id;
        return expr.toStringInfix(cmds.store, result, cmds.allocator);
    }

    if (std.mem.startsWith(u8, trimmed, "(handle ") or std.mem.startsWith(u8, trimmed, "(perform ")) {
        const id = try cmds.parser.parseSExpr(trimmed);
        cmds.engine.fuel = 1_000_000;
        const result = engine_expr.evaluate(cmds.store, cmds.env, cmds.engine, id, 0) catch id;
        return expr.toStringInfix(cmds.store, result, cmds.allocator);
    }

    // Dispatch spécial pour (let ...) et (letrec ...)
    if (trimmed.len >= 2 and trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')') {
        const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], " \t");
        if (std.mem.startsWith(u8, inner, "let ") or std.mem.startsWith(u8, inner, "letrec ")) {
            const id = try cmds.parser.parseSExpr(trimmed);
            cmds.engine.fuel = 1_000_000;
            const result = engine_expr.evaluate(cmds.store, cmds.env, cmds.engine, id, 0) catch id;
            return expr.toStringInfix(cmds.store, result, cmds.allocator);
        }
    }
    
    if (trimmed.len >= 2 and trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')') {
        const id = try cmds.bridge.importExpr(trimmed);
        cmds.engine.fuel = 1_000_000;
        const result = engine_expr.evaluate(cmds.store, cmds.env, cmds.engine, id, 0) catch |err| {
            return try std.fmt.allocPrint(cmds.allocator, "eval error: {s}", .{@errorName(err)});
        };
        return expr.toStringInfix(cmds.store, result, cmds.allocator);
    }

    if (std.mem.indexOf(u8, trimmed, ":=")) |walrus_pos| {
        const lhs = std.mem.trim(u8, trimmed[0..walrus_pos], " ");

        // Détecter si c'est une définition de fonction (LHS avec paramètres)
        var token_count: usize = 0;
        var tok_it = std.mem.tokenizeScalar(u8, lhs, ' ');
        while (tok_it.next()) |_| token_count += 1;

        if (token_count >= 2 or std.mem.indexOfScalar(u8, lhs, '(') != null) {
            // C'est une fonction : construire une nouvelle string avec = au lieu de :=
            const before = trimmed[0..walrus_pos];
            const after = trimmed[walrus_pos + 2 ..];
            const converted = try std.fmt.allocPrint(cmds.allocator, "{s}={s}", .{ before, after });
            defer cmds.allocator.free(converted);
            return cmds.evalFnDef(converted);
        }

        // Sinon c'est un binding simple
        return cmds.evalLet(trimmed);
    }

    const eq_idx = blk: {
        var i: usize = 0;
        while (i < trimmed.len) {
            if (trimmed[i] == '=') {
                if (i + 1 < trimmed.len and trimmed[i + 1] == '=') {
                    i += 2;
                    continue;
                }
                break :blk i;
            }
            i += 1;
        }
        break :blk null;
    };
    if (eq_idx) |eq_pos| {
        const is_lambda = std.mem.startsWith(u8, trimmed, "fun ") or
            std.mem.startsWith(u8, trimmed, "λ ") or
            std.mem.startsWith(u8, trimmed, "fn(") or
            std.mem.startsWith(u8, trimmed, "\\") or
            (trimmed.len > 0 and trimmed[0] == '|') or
            std.mem.indexOf(u8, trimmed, "=>") != null or
            std.mem.indexOf(u8, trimmed, "->") != null;

        if (!is_lambda and !std.mem.startsWith(u8, trimmed, "let ") and
            !std.mem.startsWith(u8, trimmed, "let macro ") and
            !std.mem.startsWith(u8, trimmed, "let actor ") and
            !std.mem.startsWith(u8, trimmed, "theorem ") and
            !std.mem.startsWith(u8, trimmed, "prove ") and
            !std.mem.startsWith(u8, trimmed, "simplify ") and
            !std.mem.startsWith(u8, trimmed, "transform ") and
            !std.mem.startsWith(u8, trimmed, "type ") and
            !std.mem.startsWith(u8, trimmed, "plot ") and
            !std.mem.startsWith(u8, trimmed, "latex ") and
            !std.mem.startsWith(u8, trimmed, "explain ") and
            !std.mem.startsWith(u8, trimmed, "expand ") and
            !std.mem.startsWith(u8, trimmed, "optimize ") and
            !std.mem.startsWith(u8, trimmed, "trace ") and
            !std.mem.startsWith(u8, trimmed, "qtt ") and
            !std.mem.startsWith(u8, trimmed, "mir ") and
            !std.mem.startsWith(u8, trimmed, "asm ") and
            !std.mem.startsWith(u8, trimmed, "solve ") and
            !std.mem.startsWith(u8, trimmed, "derive ") and
            !std.mem.startsWith(u8, trimmed, "integrate ") and
            !std.mem.startsWith(u8, trimmed, "skill ") and
            !std.mem.startsWith(u8, trimmed, "ask ") and
            !std.mem.startsWith(u8, trimmed, "js ") and
            !std.mem.startsWith(u8, trimmed, "quote "))
        {
            const lhs = std.mem.trim(u8, trimmed[0..eq_pos], " ");
            var token_count: usize = 0;
            var tok_it = std.mem.tokenizeScalar(u8, lhs, ' ');
            while (tok_it.next()) |_| token_count += 1;

            if (token_count >= 2 or std.mem.indexOfScalar(u8, lhs, '(') != null) {
                if (!is_lambda) {
                    return cmds.evalFnDef(trimmed);
                }
            }
        }
    }

    if (std.mem.startsWith(u8, trimmed, "send(") or
        std.mem.startsWith(u8, trimmed, "spawn(") or
        std.mem.startsWith(u8, trimmed, "state("))
    {
        const apply_id = cmds.parseCallExpr(trimmed) catch |err| {
            return try std.fmt.allocPrint(cmds.allocator, "actor parse error: {}", .{err});
        };
        cmds.engine.fuel = 1_000_000;
        const result = engine_expr.evaluate(cmds.store, cmds.env, cmds.engine, apply_id, 0) catch |err| {
            return try std.fmt.allocPrint(cmds.allocator, "actor error: {}", .{err});
        };
        return expr.toString(cmds.store, result, cmds.allocator);
    }

    if (std.mem.indexOfScalar(u8, trimmed, '(') == null) {
        if (cmds.tryFnCall(trimmed)) |result| return result;
    }

    if (std.mem.eql(u8, trimmed, "help")) return cmds.evalHelp();
    if (std.mem.eql(u8, trimmed, "stats")) return cmds.evalStats();
    if (std.mem.eql(u8, trimmed, "theorems")) return cmds.evalTheorems();
    if (std.mem.eql(u8, trimmed, "meta") or std.mem.eql(u8, trimmed, "rules")) return cmds.evalRules();

    if (std.mem.startsWith(u8, trimmed, "let ")) return cmds.evalLet(trimmed["let ".len..]);
    if (std.mem.startsWith(u8, trimmed, "transform ")) return try cmds.evalTransform(trimmed["transform ".len..]);
    if (std.mem.startsWith(u8, trimmed, "eval ")) return cmds.evalSExpr(trimmed["eval ".len..]);
    if (std.mem.startsWith(u8, trimmed, "theorem ")) return cmds.evalTheorem(trimmed["theorem ".len..]);
    if (std.mem.startsWith(u8, trimmed, "prove ")) return cmds.evalProve(trimmed["prove ".len..]);
    if (std.mem.startsWith(u8, trimmed, "skill ")) return cmds.evalSkill(trimmed["skill ".len..]);
    if (std.mem.startsWith(u8, trimmed, "type ")) return cmds.evalType(trimmed["type ".len..]);

    // === MODIFICATION : evalSimplify utilise désormais simplifyWithEGraph ===
    if (std.mem.startsWith(u8, trimmed, "simplify ")) return cmds.evalSimplify(trimmed["simplify ".len..]);

    if (std.mem.startsWith(u8, trimmed, "rewrite ")) {
        const rest = trimmed["rewrite ".len..];
        const arrow_pos = std.mem.indexOf(u8, rest, "=>") orelse {
            return cmds.allocator.dupe(u8, "syntax error: expected lhs => rhs");
        };
        const lhs_str = std.mem.trim(u8, rest[0..arrow_pos], " ");
        const rhs_str = std.mem.trim(u8, rest[arrow_pos + 2 ..], " ");
        const lhs = cmds.parseExpression(lhs_str) catch return cmds.allocator.dupe(u8, "parse error in lhs");
        const rhs = cmds.parseExpression(rhs_str) catch return cmds.allocator.dupe(u8, "parse error in rhs");

        const lhs_canon = try canon_mod.canonicalize(cmds.store, cmds.allocator, lhs);
        const rhs_canon = try canon_mod.canonicalize(cmds.store, cmds.allocator, rhs);

        const rule_id = cmds.store.relation("=>", &.{ lhs_canon, rhs_canon }, &.{}) catch return cmds.allocator.dupe(u8, "relation error");
        cmds.kb.rules.append(cmds.allocator, rule_id) catch return cmds.allocator.dupe(u8, "append error");
        return cmds.allocator.dupe(u8, "✓ rule added");
    }
    if (std.mem.startsWith(u8, trimmed, "plot ")) return cmds.evalPlot(trimmed["plot ".len..]);
    if (std.mem.startsWith(u8, trimmed, "latex ")) return cmds.evalLatex(trimmed["latex ".len..]);
    if (std.mem.startsWith(u8, trimmed, "explain ")) return cmds.evalExplain(trimmed["explain ".len..]);
    if (std.mem.startsWith(u8, trimmed, "expand ")) return cmds.evalExpand(trimmed["expand ".len..]);
    if (std.mem.startsWith(u8, trimmed, "optimize ")) return cmds.evalOptimize(trimmed["optimize ".len..]);
    if (std.mem.startsWith(u8, trimmed, "trace ")) return cmds.evalTrace(trimmed["trace ".len..]);
    if (std.mem.startsWith(u8, trimmed, "qtt ")) return cmds.evalQtt(trimmed["qtt ".len..]);
    if (std.mem.startsWith(u8, trimmed, "mir ")) return cmds.evalMir(trimmed["mir ".len..]);
    if (std.mem.startsWith(u8, trimmed, "solve ")) return try cmds.math.solve(trimmed["solve ".len..], "x");
    if (std.mem.startsWith(u8, trimmed, "derive ")) {
        const expr_str = trimmed["derive ".len..];
        const expr_id = cmds.parseExpression(expr_str) catch {
            return cmds.allocator.dupe(u8, "parse error in derive expression");
        };
        const var_id = cmds.store.sym("x") catch {
            return cmds.allocator.dupe(u8, "error: cannot create var sym");
        };
        const var_node = cmds.store.get(var_id);
        const var_sym = var_node.payload;
        const result = cmds.math.deriveExpr(expr_id, var_sym) catch |err| {
            switch (err) {
                error.UnsupportedPowerVarExp,
                error.UnsupportedPowerType,
                error.UnsupportedDeriveOp,
                => return cmds.allocator.dupe(u8, "error: unsupported derive operation"),
                else => return cmds.allocator.dupe(u8, "0"),
            }
        };
        // Simplifier le résultat
        const lowered = try cmds.store.lowerRec(result);
        const simplified = try cmds.simplify_eng.simplifyWithEGraph(lowered, null, null);
        return expr.toStringInfix(cmds.store, simplified, cmds.allocator);
    }
    if (std.mem.startsWith(u8, trimmed, "integrate ")) return try cmds.math.integrate(trimmed["integrate ".len..], "x");
    if (std.mem.startsWith(u8, trimmed, "asm ")) return cmds.evalAsm(trimmed["asm ".len..]);
    if (std.mem.startsWith(u8, trimmed, "ask ")) return cmds.evalAsk(trimmed["ask ".len..]);
    if (std.mem.startsWith(u8, trimmed, "js ")) return cmds.evalJs(trimmed["js ".len..]);
    if (std.mem.startsWith(u8, trimmed, "green ")) return cmds.evalGreen(trimmed["green ".len..]);

    if (std.mem.startsWith(u8, trimmed, "derive(")) {
        const rest = trimmed["derive(".len..];
        if (std.mem.endsWith(u8, rest, ")")) {
            const inner = rest[0 .. rest.len - 1];
            if (std.mem.indexOfScalar(u8, inner, ',')) |comma| {
                const expr_str = std.mem.trim(u8, inner[0..comma], " ");
                const var_str = std.mem.trim(u8, inner[comma + 1 ..], " ");
                return cmds.math.derive(expr_str, var_str) catch |err| {
                    switch (err) {
                        error.UnsupportedPowerVarExp,
                        error.UnsupportedPowerType,
                        error.UnsupportedDeriveOp,
                        => return error.UnsupportedExpr,
                        else => return error.EvaluationFailed,
                    }
                };
            }
        }
    }
    if (std.mem.startsWith(u8, trimmed, "solve(")) {
        const rest = trimmed["solve(".len..];
        if (std.mem.endsWith(u8, rest, ")")) {
            const inner = rest[0 .. rest.len - 1];
            if (std.mem.indexOfScalar(u8, inner, ',')) |comma| {
                const eq_str = std.mem.trim(u8, inner[0..comma], " ");
                const var_str = std.mem.trim(u8, inner[comma + 1 ..], " ");
                return try cmds.math.solve(eq_str, var_str);
            }
        }
    }
    if (std.mem.startsWith(u8, trimmed, "integrate(")) {
        const rest = trimmed["integrate(".len..];
        if (std.mem.endsWith(u8, rest, ")")) {
            const inner = rest[0 .. rest.len - 1];
            if (std.mem.indexOfScalar(u8, inner, ',')) |comma| {
                const expr_str = std.mem.trim(u8, inner[0..comma], " ");
                const var_str = std.mem.trim(u8, inner[comma + 1 ..], " ");
                return try cmds.math.integrate(expr_str, var_str);
            }
        }
    }

    // ─── Fallback : application de fonction utilisateur ───
    // "double 21" ou "add (succ zero) (succ zero)"
    // parseExpression internerait "double 21" comme un seul sym,
    // donc on split ici AVANT le chemin S-expr.
    {
        var head_tokens = std.mem.tokenizeScalar(u8, trimmed, ' ');
        if (head_tokens.next()) |head| {
            const rest = head_tokens.rest();
            if (rest.len > 0 and cmds.engine.fns.get(head) != null) {
                var args: std.ArrayListUnmanaged(Id) = .{};
                defer args.deinit(cmds.allocator);

                // Splitter au niveau 0 pour respecter les parenthèses
                var depth: usize = 0;
                var start: usize = 0;
                var i: usize = 0;
                while (i < rest.len) : (i += 1) {
                    switch (rest[i]) {
                        '(' => depth += 1,
                        ')' => if (depth > 0) {
                            depth -= 1;
                        },
                        ' ' => if (depth == 0) {
                            if (i > start) {
                                const tok = rest[start..i];
                                const id = cmds.parseExpression(tok) catch |err| switch (err) {
                                    error.OutOfMemory => return error.OutOfMemory,
                                    else => return try std.fmt.allocPrint(cmds.allocator, "parse error for arg: {s}", .{tok}),
                                };
                                try args.append(cmds.allocator, id);
                            }
                            start = i + 1;
                        },
                        else => {},
                    }
                }
                if (start < rest.len) {
                    const tok = rest[start..];
                    const id = cmds.parseExpression(tok) catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        else => return try std.fmt.allocPrint(cmds.allocator, "parse error for arg: {s}", .{tok}),
                    };
                    try args.append(cmds.allocator, id);
                }

                cmds.engine.fuel = 1_000_000;
                const result = cmds.engine.evalFunction(cmds.env, head, args.items) catch |err| {
                    return try std.fmt.allocPrint(cmds.allocator, "eval error: {}", .{err});
                };
                return expr.toStringInfix(cmds.store, result, cmds.allocator);
            }
        }
    }

    if (cmds.parseExpression(trimmed)) |expr_id| {
        const lowered = try cmds.store.lowerRec(expr_id);
        cmds.engine.fuel = 1_000_000;
        const result = engine_expr.evaluate(cmds.store, cmds.env, cmds.engine, lowered, 0) catch |err| {
            return try std.fmt.allocPrint(cmds.allocator, "eval error: {}", .{err});
        };
        return expr.toStringInfix(cmds.store, result, cmds.allocator);
    } else |_| {}

    cmds.engine.fuel = 1_000_000;
    const id0 = if (cmds.bridge.importExpr(input)) |id| id else |_| blk: {
        break :blk cmds.bridge.importExpr(input) catch {
            return try cmds.allocator.dupe(u8, "syntax error");
        };
    };
    const result = try engine_expr.evaluate(cmds.store, cmds.env, cmds.engine, id0, 0);
    const canon = if (platform.target.is_wasm)
        try canon_mod.canonicalize(cmds.store, cmds.allocator, result)
    else
        result;
    return expr.toStringInfix(cmds.store, canon, cmds.allocator);
}
