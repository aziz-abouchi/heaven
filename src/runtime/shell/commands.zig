const std = @import("std");
const Shell = @import("init.zig").Shell;
const session_lib = @import("../../core/session.zig");
const eval = @import("eval.zig");
const utils = @import("utils.zig");
const ontology_lib = @import("ontology");
const cmd_list = @import("commands_list.zig");
const platform = @import("platform");
const engine_expr = @import("engine_expr");

const QV = struct { name: []const u8, id: u32 };

pub fn cmdAsk(self: *Shell, query_str: []const u8) void {
    if (query_str.len == 0) return;
    self.prolog.loadFromMatrix(self.matrix);
    const parsed = self.prolog.parseAtom(query_str) orelse return;

    var solutions = self.prolog.solve(parsed, self.allocator);
    defer solutions.deinit(self.allocator);

    if (solutions.items.len == 0) {
        platform.debug.print("  Aucune solution.\n", .{});
        return;
    }

    // Deduplicate
    var seen: [64][256]u8 = undefined;
    var seen_len: [64]usize = undefined;
    var num_seen: usize = 0;

    var displayed: u32 = 0;
    for (solutions.items) |sol| {
        // Build result string
        var res_buf: [256]u8 = undefined;
        var res_pos: usize = 0;
        var first = true;
        var vi: u8 = 0;
        while (vi < parsed.arity) : (vi += 1) {
            const arg2 = parsed.args[vi];
            if (arg2.len > 0 and arg2[0] >= 'A' and arg2[0] <= 'Z') {
                const resolved2 = sol.resolve(arg2);
                if (resolved2.len > 0 and resolved2[0] >= 'A' and resolved2[0] <= 'Z') continue;
                if (!first and res_pos < 254) {
                    res_buf[res_pos] = ',';
                    res_buf[res_pos + 1] = ' ';
                    res_pos += 2;
                }
                const entry = std.fmt.bufPrint(res_buf[res_pos..], "{s}={s}", .{ arg2, resolved2 }) catch break;
                res_pos += entry.len;
                first = false;
            }
        }
        if (first) {
            const t = "true";
            @memcpy(res_buf[0..t.len], t);
            res_pos = t.len;
        }

        // Check duplicate
        var is_dup = false;
        for (0..num_seen) |si| {
            if (seen_len[si] == res_pos and std.mem.eql(u8, seen[si][0..seen_len[si]], res_buf[0..res_pos])) {
                is_dup = true;
                break;
            }
        }
        if (is_dup) continue;
        if (num_seen < 64) {
            @memcpy(seen[num_seen][0..res_pos], res_buf[0..res_pos]);
            seen_len[num_seen] = res_pos;
            num_seen += 1;
        }

        displayed += 1;
        platform.debug.print(" #{d}: {s}\n", .{ displayed, res_buf[0..res_pos] });
        if (displayed >= 20) break;
    }
}
pub fn cmdRunStar(self: *Shell, query_str: []const u8, max_results: u32) void {
    const kanren_mod = @import("kanren");

    if (!self.kanren.relations.contains("append")) {
        var snapshot = self.matrix.snapshotSymbols(self.allocator) catch |err| {
            platform.debug.print("[ERROR] Failed to snapshot symbols: {s}\n", .{@errorName(err)});
            return;
        };
        defer snapshot.deinit();
        self.kanren.loadFromSymbols(snapshot);
    }
    const paren_start = std.mem.indexOf(u8, query_str, "(") orelse return;
    const paren_end = std.mem.lastIndexOf(u8, query_str, ")") orelse return;
    const pred = std.mem.trim(u8, query_str[0..paren_start], " ");
    const args_str = query_str[paren_start + 1 .. paren_end];

    var args_buf: [8]kanren_mod.Term = undefined;
    var arity: usize = 0;
    var query_vars: [8]QV = undefined;
    var num_qv: usize = 0;

    // Split par virgule en respectant les crochets
    var depth: u32 = 0;
    var start: usize = 0;
    for (args_str, 0..) |ch, idx| {
        if (ch == '[') depth += 1 else if (ch == ']') {
            if (depth > 0) depth -= 1;
        } else if (ch == ',' and depth == 0) {
            if (arity < 8) {
                args_buf[arity] = parseKanrenArg(self, std.mem.trim(u8, args_str[start..idx], " "), &query_vars, &num_qv);
                arity += 1;
            }
            start = idx + 1;
        }
    }
    if (start <= args_str.len and arity < 8) {
        const trimmed = std.mem.trim(u8, args_str[start..], " ");
        if (trimmed.len > 0) {
            args_buf[arity] = parseKanrenArg(self, trimmed, &query_vars, &num_qv);
            arity += 1;
        }
    }

    const results = self.kanren.solve(pred, args_buf[0..arity], max_results);
    if (results.items.items.len == 0) {
        platform.debug.print("  Aucune solution.\n", .{});
        return;
    }

    for (results.items.items, 0..) |sub, idx| {
        platform.debug.print("  #{d}: ", .{idx + 1});
        var first = true;
        for (query_vars[0..num_qv]) |qv| {
            const resolved = sub.walkDeep(.{ .Var = qv.id });
            if (!first) platform.debug.print(", ", .{});
            var buf: [256]u8 = undefined;
            platform.debug.print("{s} = {s}", .{ qv.name, resolved.format(&buf) });
            first = false;
        }
        if (first) platform.debug.print("true", .{});
        platform.debug.print("\n", .{});
        if (idx >= max_results - 1) break;
    }
}
pub fn cmdHandleLine(self: *Shell, line: []const u8) void {
    self.ingestor.ingest("repl.hvn", line) catch {};
}
pub fn cmdMemo(self: *Shell, subcmd: []const u8) void {
    if (std.mem.eql(u8, subcmd, "clear")) self.memo.clearAndFree();
}
pub fn cmdInfer(self: *Shell, input: []const u8) void {
    if (input.len == 0) return;
    const result = self.heaven.typeOf(input) catch {
        platform.debug.print(" cannot infer type\n", .{});
        return;
    };
    defer self.allocator.free(result);
    platform.debug.print("{s} : {s} (inferred)\n", .{ input, result });
}
pub fn cmdSkill(self: *Shell, input: []const u8) void {
    const result = self.heaven.evalSkill(input) catch return;
    defer self.allocator.free(result);
    platform.debug.print("{s}\n", .{result});
}
pub fn cmdProve(self: *Shell, input: []const u8) void {
    const result = self.heaven.evalProve(input) catch return;
    defer self.allocator.free(result);
    platform.debug.print("{s}\n", .{result});
}
pub fn cmdType(self: *Shell, input: []const u8) void {
    if (input.len == 0) return;
    const result = self.heaven.typeOf(input) catch {
        platform.debug.print(" type error\n", .{});
        return;
    };
    defer self.allocator.free(result);
    platform.debug.print("{s} : {s}\n", .{ input, result });
}
pub fn cmdStats(self: *Shell) void {
    const s = self.matrix.getStats();
    platform.debug.print("Matrix: {d} nodes, {d} symbols | Prolog: {d} clauses\n", .{ s.nodes, s.symbols, self.prolog.clauses.items.len });
}
pub fn cmdTrace(self: *Shell, name: []const u8) void {
    if (name.len == 0) return;
    if (self.matrix.findSymbol(name)) |id| {
        self.matrix.printTrace(id);
    }
}
pub fn cmdQuery(self: *Shell, name: []const u8) void {
    _ = self;
    _ = name;
}
pub fn cmdLoad(self: *Shell, arg: ?[]const u8) void {
    const path = arg orelse return;
    self.ingestor.ingest(path, "") catch return;
    self.prolog.loaded = false;
}
pub fn cmdRun(self: *Shell, arg: ?[]const u8) void {
    _ = self;
    _ = arg;
}
pub fn cmdInject(self: *Shell, code: []const u8) void {
    _ = self;
    _ = code;
}
pub fn cmdTranspile(self: *Shell, arg: []const u8) void {
    const codegen_c = @import("codegen_c");
    var gen = codegen_c.CCodegen.init(self.allocator, self.matrix);
    defer gen.deinit();
    const code = if (arg.len > 0)
        gen.generateForFunction(arg) catch return
    else
        gen.generate() catch return;
    platform.debug.print("{s}\n", .{code});
}
pub fn cmdCompile(self: *Shell, arg: []const u8) void {
    const codegen_c = @import("codegen_c");
    var gen = codegen_c.CCodegen.init(self.allocator, self.matrix);
    defer gen.deinit();
    const fname = if (arg.len > 0) arg else "main";
    const code = if (arg.len > 0)
        gen.generateForFunction(fname) catch return
    else
        gen.generate() catch return;
    const out_file = platform.fs.cwd().createFile("heaven_out.c", .{}) catch return;
    defer out_file.close();
    out_file.writeAll(code) catch return;
}
pub fn cmdQuote(self: *Shell, input: []const u8) void {
    if (input.len == 0) return;
    const result = self.heaven.dumpAst(input) catch {
        platform.debug.print(" parse error\n", .{});
        return;
    };
    defer self.allocator.free(result);
    platform.debug.print("{s}", .{result});
}
pub fn cmdLaTeX(self: *Shell, input: []const u8) void {
    if (input.len == 0) return;
    self.heaven.ensureInit();
    const id = self.heaven.importExpr(input) catch {
        platform.debug.print(" parse error\n", .{});
        return;
    };
    const latex = self.heaven.toLaTeXInline(id) catch {
        platform.debug.print(" latex error\n", .{});
        return;
    };
    defer self.allocator.free(latex);
    platform.debug.print("$$ {s} $$\n", .{latex});
}
pub fn cmdExplain(self: *Shell, input: []const u8) void {
    if (input.len == 0) return;
    const result = self.heaven.explain(input) catch {
        platform.debug.print(" explain error\n", .{});
        return;
    };
    defer self.allocator.free(result);
    platform.debug.print("{s}", .{result});
}
pub fn cmdDoc(self: *Shell) void {
    platform.debug.print("\n \xe2\x95\x90\xe2\x95\x90\xe2\x95\x90 Heaven Knowledge Base \xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\n", .{});
    const kb_desc = self.heaven.describeKB() catch "?";
    defer self.allocator.free(kb_desc);
    platform.debug.print("{s}", .{kb_desc});
    platform.debug.print(" {d} Prolog clauses\n", .{self.prolog.clauses.items.len});
    platform.debug.print(" {d} Kanren relations\n", .{self.kanren.relations.count()});
    const s = self.matrix.getStats();
    platform.debug.print(" {d} Matrix nodes, {d} symbols\n\n", .{ s.nodes, s.symbols });
}
pub fn cmdLet(self: *Shell, input: []const u8) void {
    const full_input = std.fmt.allocPrint(self.allocator, "let {s}", .{input}) catch return;
    defer self.allocator.free(full_input);
    const result = self.heaven.eval(full_input) catch return;
    defer self.allocator.free(result);
    platform.debug.print("{s}\n", .{result});
}
pub fn cmdToC(self: *Shell, input: []const u8) void {
    if (input.len == 0) return;
    self.heaven.ensureInit();

    // Wrapper dans un let pour que le codegen le traite
    var wrap_buf: [512]u8 = undefined;
    const wrapped = std.fmt.bufPrint(&wrap_buf, "_result = {s}", .{input}) catch return;
    _ = wrapped;

    const id = self.heaven.importExpr(input) catch {
        platform.debug.print("  parse error\n", .{});
        return;
    };

    // Créer un binding temporaire
    const bind_id = self.heaven.store.bind("_expr", id) catch {
        platform.debug.print("  bind error\n", .{});
        return;
    };

    var ids_buf = [1]u32{bind_id};
    const code = self.heaven.toC(&ids_buf) catch {
        platform.debug.print("  codegen error\n", .{});
        return;
    };
    defer self.allocator.free(code);
    platform.debug.print("{s}\n", .{code});
}

/// Sépare "expression variable" en respectant les parenthèses équilibrées
fn splitExprVar(input: []const u8) struct { expr: []const u8, varname: []const u8 } {
    var depth: i32 = 0;
    var last_space_outside: ?usize = null;
    for (input, 0..) |ch, idx| {
        switch (ch) {
            '(' => depth += 1,
            ')' => depth -= 1,
            ' ' => {
                if (depth == 0 and idx > 0) last_space_outside = idx;
            },
            else => {},
        }
    }
    if (last_space_outside) |idx| {
        const potential_var = std.mem.trim(u8, input[idx + 1 ..], " ");
        if (potential_var.len > 0) {
            return .{
                .expr = std.mem.trim(u8, input[0..idx], " "),
                .varname = potential_var,
            };
        }
    }
    return .{ .expr = input, .varname = "x" };
}

pub fn cmdDerive(self: *Shell, input: []const u8) void {
    if (input.len == 0) return;
    const parts = splitExprVar(input);
    const result = self.heaven.derive(parts.expr, parts.varname) catch {
        platform.debug.print(" derive error\n", .{});
        return;
    };
    defer self.allocator.free(result);
    platform.debug.print("d/d{s}({s}) = {s}\n", .{ parts.varname, parts.expr, result });
}
pub fn cmdSolve(self: *Shell, input: []const u8) void {
    if (input.len == 0) return;
    const parts = splitExprVar(input);
    const result = self.heaven.solve(parts.expr, parts.varname) catch {
        platform.debug.print(" solve error\n", .{});
        return;
    };
    defer self.allocator.free(result);
    platform.debug.print("{s}\n", .{result});
}
pub fn cmdExpand(self: *Shell, input: []const u8) void {
    if (input.len == 0) return;
    const result = self.heaven.expand(input) catch {
        platform.debug.print("  expand error\n", .{});
        return;
    };
    defer self.allocator.free(result);
    platform.debug.print("\xe2\x86\x92 {s}\n", .{result});
}
pub fn cmdIntegrate(self: *Shell, input: []const u8) void {
    if (input.len == 0) return;
    const parts = splitExprVar(input);
    const result = self.heaven.integrate(parts.expr, parts.varname) catch {
        platform.debug.print(" integrate error\n", .{});
        return;
    };
    defer self.allocator.free(result);
    platform.debug.print("\xe2\x88\xab({s})dx = {s}\n", .{ input, result });
}
pub fn cmdPlot(self: *Shell, input: []const u8) void {
    if (input.len == 0) return;
    const result = self.heaven.plot(input, "x") catch {
        platform.debug.print("  plot error\n", .{});
        return;
    };
    defer self.allocator.free(result);
    platform.debug.print("{s}", .{result});
}

pub fn cmdTheorem(self: *Shell, input: []const u8) void {
    const result = self.heaven.evalTheorem(input) catch return;
    defer self.allocator.free(result);
    platform.debug.print("{s}\n", .{result});

    const colon_pos = std.mem.indexOfScalar(u8, input, ':') orelse return;
    const name = std.mem.trim(u8, input[0..colon_pos], " ");
    const stmt = std.mem.trim(u8, input[colon_pos + 1 ..], " ");
    eval.bridgeTheoremToProofEnv(self, name, stmt);
}

pub fn cmdAxiom(self: *Shell, input: []const u8) void {
    // :axiom add_zero : a + 0 = a
    if (std.mem.indexOf(u8, input, " : ")) |colon| {
        const name = std.mem.trim(u8, input[0..colon], " ");
        const stmt = std.mem.trim(u8, input[colon + 3 ..], " ");
        if (std.mem.indexOf(u8, stmt, " = ")) |eq| {
            const lhs_str = std.mem.trim(u8, stmt[0..eq], " ");
            const rhs_str = std.mem.trim(u8, stmt[eq + 3 ..], " ");
            self.heaven.ensureInit();
            const lhs = self.heaven.importExpr(lhs_str) catch return;
            const rhs = self.heaven.importExpr(rhs_str) catch return;
            self.proofs.axiom(name, stmt, lhs, rhs) catch return;
            session_lib.save(self.proofs, self.allocator) catch {};
            platform.debug.print("  \xe2\x9c\x93 axiom {s} assumed\n", .{name});
            return;
        }
    }
    platform.debug.print("  Usage: :axiom name : lhs = rhs\n", .{});
}
pub fn cmdProof(self: *Shell, input: []const u8) void {
    self.heaven.ensureInit();
    // :proof add_comm by eval
    // :proof add_comm by simplify
    // :proof sum_formula by induction n
    var tokens = std.mem.tokenizeScalar(u8, input, ' ');
    const name = tokens.next() orelse {
        platform.debug.print("  Usage: :proof <name> by [eval|simplify|induction <var>]\n", .{});
        return;
    };
    const by = tokens.next();
    if (by == null or !std.mem.eql(u8, by.?, "by")) {
        platform.debug.print("  Usage: :proof {s} by [eval|simplify|induction <var>]\n", .{name});
        return;
    }
    const method = tokens.next() orelse "eval";

    if (std.mem.eql(u8, method, "eval")) {
        const ok = self.proofs.verifyByEval(name, &self.heaven.engine, &self.heaven.store) catch false;
        if (ok) {
            platform.debug.print("  \xe2\x9c\x93 {s} proved by evaluation\n", .{name});
            session_lib.save(self.proofs, self.allocator) catch {};
        } else {
            platform.debug.print("  \xe2\x9c\x97 {s} NOT proved by evaluation\n", .{name});
        }
    } else if (std.mem.eql(u8, method, "simplify")) {
        const ok = self.proofs.verifyBySimplify(name, self.heaven) catch false;
        if (ok) {
            platform.debug.print("  \xe2\x9c\x93 {s} proved by simplification\n", .{name});
            session_lib.save(self.proofs, self.allocator) catch {};
        } else {
            platform.debug.print("  \xe2\x9c\x97 {s} NOT proved by simplification\n", .{name});
        }
    } else if (std.mem.eql(u8, method, "induction")) {
        const var_name = tokens.next() orelse "n";
        const ok = self.heaven.proof_core.verifyByInduction(name, var_name, self.heaven, &self.heaven.store) catch |err| {
            platform.debug.print("  [ERROR] verifyByInduction failed: {s}\n", .{@errorName(err)});
            return;
        };
        if (ok) {
            platform.debug.print("  \xe2\x9c\x93 {s} proved by induction on {s}\n", .{ name, var_name });
            if (self.proofs.theorems.getPtr(name)) |thm| thm.verified = true;
            session_lib.save(self.proofs, self.allocator) catch {};
        } else {
            platform.debug.print("  \xe2\x9c\x97 {s} NOT proved by induction on {s}\n", .{ name, var_name });
        }
    } else {
        platform.debug.print("  Unknown method: {s}. Try: eval, simplify, induction\n", .{method});
    }
}
fn cmdSkillWithInduction(self: *Shell, skill_name: []const u8, induction_var: []const u8) void {
    const target = self.active_theorem orelse {
        platform.debug.print("  Aucun théorème actif.\n", .{});
        return;
    };

    const result = self.skills.apply(
        skill_name,
        target,
        induction_var,
        self.proofs,
        &self.heaven.engine,
        self.heaven,
        &self.heaven.store,
    ) catch |err| {
        platform.debug.print("  Erreur skill: {s}\n", .{@errorName(err)});
        return;
    };

    if (result.proved) {
        session_lib.save(self.proofs, self.allocator) catch {};
        platform.debug.print("✓ [{s}] Théorème '{s}' prouvé ({d} tactiques)\n", .{ skill_name, target, result.tactics_run });
    } else {
        platform.debug.print("✗ [{s}] Échec sur '{s}' ({d} tactiques)\n", .{ skill_name, target, result.tactics_run });
    }
}
pub fn cmdTheorems(self: *Shell) void {
    const s = self.proofs.formatAll(self.allocator) catch return;
    defer self.allocator.free(s);
    platform.debug.print("{s}", .{s});
}
pub fn cmdSpawn(self: *Shell, input: []const u8) void {
    if (input.len == 0) {
        platform.debug.print(" Usage: :spawn <expr> e.g. :spawn fib 30\n", .{});
        return;
    }
    // Set up eval function if not done
    if (self.green.eval_fn == null) {
        self.green.eval_fn = &utils.greenEvalAdapter;
    }
    const id = self.green.spawn(input) catch {
        platform.debug.print(" (spawn error)\n", .{});
        return;
    };
    platform.debug.print(" [GT-{d}] spawned: {s}\n", .{ id, input });
}
pub fn cmdThreads(self: *Shell, _: []const u8) void {
    const status = self.green.formatStatus(self.allocator) catch return;
    defer self.allocator.free(status);
    platform.debug.print("{s}", .{status});
}
pub fn cmdAwait(self: *Shell, input: []const u8) void {
    const id = std.fmt.parseInt(u32, std.mem.trim(u8, input, " "), 10) catch {
        platform.debug.print("  Usage: :await <id>\n", .{});
        return;
    };
    if (self.green.await(id)) |result| {
        platform.debug.print("  \xe2\x86\x92 {s}\n", .{result});
    } else {
        platform.debug.print("  (no result or not found)\n", .{});
    }
}
pub fn cmdSwarm(self: *Shell, input: []const u8) void {
    const swarm_proto = @import("../../scut/swarm/protocol_swarm.zig");
    _ = swarm_proto;

    if (input.len == 0) {
        const stats = self.swarm.formatStats(self.allocator) catch return;
        defer self.allocator.free(stats);
        platform.debug.print("{s}", .{stats});
        return;
    }

    // :swarm solve <expr>
    if (std.mem.startsWith(u8, input, "solve ")) {
        const expr = std.mem.trim(u8, input[6..], " ");
        _ = self.swarm.broadcastTask(.solve, expr) catch {};
        return;
    }
    // :swarm simplify <expr>
    if (std.mem.startsWith(u8, input, "simplify ")) {
        const expr = std.mem.trim(u8, input[9..], " ");
        _ = self.swarm.broadcastTask(.simplify, expr) catch {};
        return;
    }
    // :swarm derive <expr>
    if (std.mem.startsWith(u8, input, "derive ")) {
        const expr = std.mem.trim(u8, input[7..], " ");
        _ = self.swarm.broadcastTask(.derive, expr) catch {};
        return;
    }
    // :swarm prove <expr>
    if (std.mem.startsWith(u8, input, "prove ")) {
        const expr = std.mem.trim(u8, input[6..], " ");
        _ = self.swarm.broadcastTask(.prove, expr) catch {};
        return;
    }
    // :swarm log
    if (std.mem.eql(u8, input, "log")) {
        const stats = self.swarm.formatStats(self.allocator) catch return;
        defer self.allocator.free(stats);
        platform.debug.print("{s}", .{stats});
        return;
    }
    platform.debug.print("  Usage: :swarm [solve|simplify|derive|prove] <expr>\n", .{});
    platform.debug.print("         :swarm              (status)\n", .{});
    platform.debug.print("         :swarm log          (history)\n", .{});
}
pub fn cmdDep(self: *Shell, input: []const u8) void {
    const types = @import("types");
    var dc = types.DependentChecker.init(self.allocator);
    defer dc.deinit();

    // Parse dependent type expressions
    const trimmed = std.mem.trim(u8, input, " ");

    // Vec type: \"Vec 3 Int\" or \"Vec(3, Int)\"
    if (std.mem.startsWith(u8, trimmed, "Vec")) {
        var iter = std.mem.tokenizeAny(u8, trimmed, " (,)");
        _ = iter.next(); // skip \"Vec\"
        const n_str = iter.next() orelse "0";
        const n = std.fmt.parseInt(i64, n_str, 10) catch 0;
        const elem_str = iter.next() orelse "Int";
        const elem_type: types.Type = if (std.mem.eql(u8, elem_str, "Int")) 1 else if (std.mem.eql(u8, elem_str, "Bool")) 2 else 3;
        const vt = dc.vecType(n, elem_type) catch return;
        const s = types.DependentChecker.formatJudgment(vt, self.allocator) catch return;
        defer self.allocator.free(s);
        platform.debug.print("  {s}\n", .{s});
        return;
    }

    // Pi type: \"Pi x Nat Int\"
    if (std.mem.startsWith(u8, trimmed, "Pi ") or std.mem.startsWith(u8, trimmed, "pi ")) {
        var iter = std.mem.tokenizeAny(u8, trimmed, " ");
        _ = iter.next(); // skip \"Pi\"
        const param = iter.next() orelse "x";
        const dom_str = iter.next() orelse "Nat";
        const cod_str = iter.next() orelse "Int";
        const dom: types.Type = if (std.mem.eql(u8, dom_str, "Nat")) 0 else if (std.mem.eql(u8, dom_str, "Int")) 1 else 0;
        const cod: types.Type = if (std.mem.eql(u8, cod_str, "Int")) 1 else if (std.mem.eql(u8, cod_str, "Bool")) 2 else 0;
        const pt = dc.piType(param, dom, cod) catch return;
        const s = types.DependentChecker.formatJudgment(pt, self.allocator) catch return;
        defer self.allocator.free(s);
        platform.debug.print("  {s}\n", .{s});
        return;
    }

    // Sigma type: \"Sigma x Nat Int\"
    if (std.mem.startsWith(u8, trimmed, "Sigma ") or std.mem.startsWith(u8, trimmed, "sigma ")) {
        var iter = std.mem.tokenizeAny(u8, trimmed, " ");
        _ = iter.next();
        const param = iter.next() orelse "x";
        const fst_str = iter.next() orelse "Nat";
        const snd_str = iter.next() orelse "Int";
        const fst: types.Type = if (std.mem.eql(u8, fst_str, "Nat")) 0 else 1;
        const snd: types.Type = if (std.mem.eql(u8, snd_str, "Int")) 1 else 2;
        const st = dc.sigmaType(param, fst, snd) catch return;
        const s = types.DependentChecker.formatJudgment(st, self.allocator) catch return;
        defer self.allocator.free(s);
        platform.debug.print("  {s}\n", .{s});
        return;
    }

    // Vec append: \"append Vec(3,Int) Vec(2,Int)\"
    if (std.mem.startsWith(u8, trimmed, "append")) {
        var iter = std.mem.tokenizeAny(u8, trimmed, " (,)");
        _ = iter.next(); // skip \"append\"
        _ = iter.next(); // skip \"Vec\"
        const n_str = iter.next() orelse "0";
        const n = std.fmt.parseInt(i64, n_str, 10) catch 0;
        _ = iter.next(); // skip elem
        _ = iter.next(); // skip \"Vec\"
        const m_str = iter.next() orelse "0";
        const m = std.fmt.parseInt(i64, m_str, 10) catch 0;
        const result = dc.checkVecAppend(n, m, 1) catch return;
        const s = types.DependentChecker.formatJudgment(result, self.allocator) catch return;
        defer self.allocator.free(s);
        platform.debug.print("  Vec({d}, Int) ++ Vec({d}, Int) = {s}\n", .{ n, m, s });
        return;
    }

    // Equality: \"eq n+0 n\"
    if (std.mem.startsWith(u8, trimmed, "eq ")) {
        const rest = trimmed[3..];
        if (std.mem.indexOf(u8, rest, " ")) |sp| {
            const lhs_str = std.mem.trim(u8, rest[0..sp], " ");
            const rhs_str = std.mem.trim(u8, rest[sp + 1 ..], " ");
            // Simple: try to parse as \"n+0 n\"
            if (std.mem.indexOf(u8, lhs_str, "+0")) |_| {
                const n_part = lhs_str[0 .. std.mem.indexOf(u8, lhs_str, "+") orelse 0];
                if (std.mem.eql(u8, n_part, rhs_str)) {
                    platform.debug.print("  \xe2\x9c\x93 {s} \xe2\x89\xa1 {s} (by refl + add_zero)\n", .{ lhs_str, rhs_str });
                } else {
                    platform.debug.print("  \xe2\x9c\x97 {s} \xe2\x89\xa2 {s}\n", .{ lhs_str, rhs_str });
                }
                return;
            }
            if (std.mem.eql(u8, lhs_str, rhs_str)) {
                platform.debug.print(" \xe2\x9c\x93 {s} \xe2\x89\xa1 {s} (by refl)\n", .{ lhs_str, rhs_str });
            } else if (utils.isCommuted(lhs_str, rhs_str)) {
                platform.debug.print(" \xe2\x9c\x93 {s} \xe2\x89\xa1 {s} (by commutativity)\n", .{ lhs_str, rhs_str });
            } else {
                platform.debug.print(" \xe2\x9c\x97 {s} \xe2\x89\xa2 {s}\n", .{ lhs_str, rhs_str });
            }
        } else {
            platform.debug.print("  Usage: :dep eq <lhs> <rhs>\n", .{});
        }
        return;
    }

    platform.debug.print("  \xe2\x95\x90\xe2\x95\x90\xe2\x95\x90 Types D\xc3\xa9pendants \xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\n", .{});
    platform.debug.print("  :dep Vec 3 Int         \xe2\x86\x92 Vec(3, Int)\n", .{});
    platform.debug.print("  :dep Pi n Nat Int      \xe2\x86\x92 (n : Nat) \xe2\x86\x92 Int\n", .{});
    platform.debug.print("  :dep Sigma x Nat Int   \xe2\x86\x92 \xce\xa3(x : Nat, Int)\n", .{});
    platform.debug.print("  :dep append Vec(3,Int) Vec(2,Int) \xe2\x86\x92 Vec(5,Int)\n", .{});
    platform.debug.print("  :dep eq n+0 n          \xe2\x86\x92 \xe2\x9c\x93 proof\n", .{});
}
pub fn cmdHole(self: *Shell, input: []const u8) void {
    if (input.len == 0) {
        platform.debug.print(" Usage: :hole <expr with ?> e.g. :hole ? + 3 = 10\n", .{});
        return;
    }
    // Check if it's an equation: expr = value
    if (std.mem.indexOfScalar(u8, input, '=')) |eq| {
        const lhs = std.mem.trim(u8, input[0..eq], " ");
        const rhs = std.mem.trim(u8, input[eq + 1 ..], " ");
        // Try to solve: substitute ? with candidate values
        const rhs_val = std.fmt.parseInt(i64, rhs, 10) catch {
            platform.debug.print(" RHS must be an integer\n", .{});
            return;
        };
        // Try to solve via :solve first (algebraic)
        var solve_buf: [256]u8 = undefined;
        const solve_expr = std.fmt.bufPrint(&solve_buf, "{s} - {d}", .{ lhs, rhs_val }) catch "";
        if (solve_expr.len > 0) {
            // Replace ? with x for the solver
            const solve_input = self.heaven.substExpr(solve_expr, "?", "x") catch null;
            if (solve_input) |si| {
                defer self.allocator.free(si);
                if (self.heaven.solve(si, "x") catch null) |sol| {
                    defer self.allocator.free(sol);
                    // Replace x back to ? in output
                    platform.debug.print("{s}\n", .{sol});
                    return;
                }
            }
        }
        // Fallback: brute force with positive values only (safe)
        var found = false;
        var i: i64 = 0;
        while (i <= 20) : (i += 1) {
            const vals = [_]i64{ i, -i };
            for (vals) |v| {
                var buf: [64]u8 = undefined;
                const val_str = std.fmt.bufPrint(&buf, "{d}", .{v}) catch continue;
                const substituted = self.heaven.substExpr(lhs, "?", val_str) catch continue;
                defer self.allocator.free(substituted);
                // Use evalSExpr which is safer
                const as_sexpr = self.heaven.eval(substituted) catch continue;
                defer self.allocator.free(as_sexpr);
                if (as_sexpr.len > 0 and as_sexpr[0] == '(') continue;
                const eval_val = std.fmt.parseInt(i64, as_sexpr, 10) catch continue;
                if (eval_val == rhs_val) {
                    platform.debug.print(" ? = {d}\n", .{v});
                    found = true;
                }
            }
        }
        if (!found) platform.debug.print(" (no solution in [-20, 20])\n", .{});
        return;
    }
    // Just type-check the expression with hole
    const type_result = self.heaven.typeOf(input) catch {
        platform.debug.print(" type error\n", .{});
        return;
    };
    defer self.allocator.free(type_result);
    platform.debug.print(" ? : {s} (inferred from context)\n", .{type_result});
}
pub fn cmdMeta(self: *Shell, input: []const u8) void {
    if (input.len == 0) {
        // List all rules as data
        const rules = self.heaven.listRules() catch return;
        defer self.allocator.free(rules);
        platform.debug.print("{s}", .{rules});
        return;
    }
    // :meta eval (+ 2 3) — evaluate s-expression
    if (std.mem.startsWith(u8, input, "eval ")) {
        const sexpr = std.mem.trim(u8, input[5..], " ");
        const result = self.heaven.evalSExpr(sexpr) catch return;
        defer self.allocator.free(result);
        platform.debug.print(" \xe2\x86\x92 {s}\n", .{result});
        return;
    }
    // :meta quote <expr> — quote then show
    if (std.mem.startsWith(u8, input, "quote ")) {
        const e = std.mem.trim(u8, input[6..], " ");
        const ast = self.heaven.dumpAst(e) catch return;
        defer self.allocator.free(ast);
        platform.debug.print("{s}", .{ast});
        return;
    }
    platform.debug.print(" Usage: :meta [eval|quote] <expr>\n", .{});
}
pub fn cmdSubst(self: *Shell, input: []const u8) void {
    // :subst <expr> <var> <val> — split from the end
    const trimmed = std.mem.trim(u8, input, " ");
    // Find last two tokens (var and val)
    const last_space = std.mem.lastIndexOfScalar(u8, trimmed, ' ') orelse return;
    const value = std.mem.trim(u8, trimmed[last_space + 1 ..], " ");
    const before_val = std.mem.trim(u8, trimmed[0..last_space], " ");
    const second_space = std.mem.lastIndexOfScalar(u8, before_val, ' ') orelse return;
    const varname = std.mem.trim(u8, before_val[second_space + 1 ..], " ");
    const expr_str = std.mem.trim(u8, before_val[0..second_space], " ");
    const result = self.heaven.substExpr(expr_str, varname, value) catch return;
    defer self.allocator.free(result);
    platform.debug.print(" \xe2\x86\x92 {s}\n", .{result});
}
pub fn cmdSExpr(self: *Shell, input: []const u8) void {
    if (input.len == 0) return;
    const result = self.heaven.evalSExpr(input) catch return;
    defer self.allocator.free(result);
    platform.debug.print("  \xe2\x86\x92 {s}\n", .{result});
}
pub fn cmdOnto(self: *Shell, input: []const u8) void {
    if (input.len == 0) {
        // List all concepts
        var it = self.meta.ontology.concepts.iterator();
        platform.debug.print(" \xe2\x95\x90\xe2\x95\x90\xe2\x95\x90 Ontologie \xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\n", .{});
        while (it.next()) |entry| {
            const co = entry.value_ptr.*;
            const parent = co.parent orelse "(root)";
            platform.debug.print(" {s} is-a {s} [{d} algos]\n", .{ co.name, parent, co.num_algos });
        }
        return;
    }
    // Define concept: ":onto Dog subclassof Animal"
    var iter = std.mem.tokenizeAny(u8, input, " ");
    const name = iter.next() orelse return;
    const keyword = iter.next();
    if (keyword) |kw| {
        if (std.mem.eql(u8, kw, "subclassof") or std.mem.eql(u8, kw, "isa")) {
            const parent = iter.next() orelse return;
            self.meta.userDefineConcept(name, parent) catch {};
            platform.debug.print(" \xe2\x9c\x93 concept {s} is-a {s}\n", .{ name, parent });
            return;
        }
    }
    // Show concept details
    const ctx = ontology_lib.OptContext{ .expected_n = 100, .has_gpu = false, .max_stack = 0, .prefer_simple = false };
    const desc = self.meta.ontology.describeChoice(name, ctx, self.allocator) catch return;
    defer self.allocator.free(desc);
    platform.debug.print("{s}", .{desc});
}
pub fn cmdOptimize(self: *Shell, input: []const u8) void {
    // :optimize Factorial 1000
    // :optimize Factorial 10 gpu
    var iter = std.mem.tokenizeAny(u8, input, " ");
    const concept = iter.next() orelse {
        platform.debug.print("  Usage: :optimize <concept> [n] [gpu]\n", .{});
        return;
    };
    const n_str = iter.next() orelse "100";
    const n = std.fmt.parseInt(u64, n_str, 10) catch 100;
    const gpu_flag = iter.next();
    const has_gpu = if (gpu_flag) |g| std.mem.eql(u8, g, "gpu") else false;

    if (has_gpu) {
        const result = self.meta.optimizeGPU(concept, n) catch return;
        defer self.allocator.free(result);
        platform.debug.print("{s}", .{result});
    } else {
        const result = self.meta.optimize(concept, n) catch return;
        defer self.allocator.free(result);
        platform.debug.print("{s}", .{result});
    }
}
pub fn cmdIsA(self: *Shell, input: []const u8) void {
    // :isa Factorial Arithmetic
    var iter = std.mem.tokenizeAny(u8, input, " ");
    const child = iter.next() orelse return;
    const ancestor = iter.next() orelse return;
    if (self.meta.isA(child, ancestor)) {
        platform.debug.print("  \xe2\x9c\x93 {s} is-a {s}\n", .{ child, ancestor });
    } else {
        platform.debug.print("  \xe2\x9c\x97 {s} is NOT a {s}\n", .{ child, ancestor });
    }
}
pub fn cmdQTT(self: *Shell, input: []const u8) void {
    // Parse: "1 x = expr" or "0 y = expr" or "w z = expr"
    const types = @import("types");
    var checker = types.LinearChecker.init(self.allocator);
    defer checker.deinit();

    var iter = std.mem.splitScalar(u8, input, ';');
    while (iter.next()) |stmt| {
        const trimmed = std.mem.trim(u8, stmt, " ");
        if (trimmed.len == 0) continue;

        // Parse quantity prefix: \"1 x = ...\" or \"0 x = ...\" or \"w x = ...\"
        if (trimmed.len > 2 and trimmed[1] == ' ') {
            const qty: types.Quantity = switch (trimmed[0]) {
                '0' => .zero,
                '1' => .one,
                'w' => .many,
                else => .many,
            };
            const rest = std.mem.trim(u8, trimmed[2..], " ");
            if (std.mem.indexOfScalar(u8, rest, '=')) |eq| {
                const name = std.mem.trim(u8, rest[0..eq], " ");
                const val_str = std.mem.trim(u8, rest[eq + 1 ..], " ");
                checker.declare(name, qty) catch continue;
                // Count variable uses in the expression
                var usage_it = checker.usage.iterator();
                while (usage_it.next()) |uentry| {
                    const var_name = uentry.key_ptr.*;
                    var count: u32 = 0;
                    var search = val_str;
                    while (std.mem.indexOf(u8, search, var_name)) |found| {
                        count += 1;
                        if (found + var_name.len < search.len) {
                            search = search[found + var_name.len ..];
                        } else break;
                    }
                    var ci: u32 = 0;
                    while (ci < count) : (ci += 1) {
                        checker.use(var_name) catch {};
                    }
                }
                platform.debug.print(" {s} {s} : {s} = {s}\n", .{ qty.format(), name, @tagName(qty), val_str });
            }
        }
    }

    checker.check() catch {};
    if (checker.hasErrors()) {
        const errs = checker.formatErrors(self.allocator) catch return;
        defer self.allocator.free(errs);
        platform.debug.print("{s}", .{errs});
    } else {
        platform.debug.print(" \xe2\x9c\x93 QTT: all quantities satisfied\n", .{});
    }
}
pub fn cmdHook(self: *Shell, input: []const u8) void {
    if (std.mem.indexOf(u8, input, "=>")) |pos| {
        const event = std.mem.trim(u8, input[0..pos], " ");
        const agent = std.mem.trim(u8, input[pos + 2 ..], " \n\r\t");
        self.green.registerHook(event, agent) catch {
            platform.debug.print("  (hook registration error)\n", .{});
            return;
        };
        platform.debug.print("  ✓ hook: '{s}' => '{s}'\n", .{ event, agent });
    } else {
        platform.debug.print("  Usage: :hook <event> => <agent>\n", .{});
    }
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
    platform.debug.print("═════════════════════════════\n\n", .{});
}

pub fn exprEval(self: *Shell, input: []const u8) void {
    eval.exprEval(self, input);
}

pub fn exprSimplify(self: *Shell, input: []const u8) void {
    eval.exprSimplify(self, input);
}

pub fn exprFact(self: *Shell, input: []const u8) void {
    eval.exprFact(self, input);
}

pub fn exprRule(self: *Shell, input: []const u8) void {
    eval.exprRule(self, input);
}

pub fn exprQuery(self: *Shell, input: []const u8) void {
    eval.exprQuery(self, input);
}

pub fn exprRewrite(self: *Shell, input: []const u8) void {
    eval.exprRewrite(self, input);
}

pub fn exprType(self: *Shell, input: []const u8) void {
    eval.exprType(self, input);
}

fn parseKanrenArg(self: *Shell, text: []const u8, qvs: *[8]QV, num_qv: *usize) @import("kanren").Term {
    if (text.len == 0) return .Nil;
    if (std.mem.eql(u8, text, "[]")) return .Nil;
    if (text[0] >= 'A' and text[0] <= 'Z') {
        const v = self.kanren.fresh();
        if (num_qv.* < 8) {
            qvs[num_qv.*] = .{ .name = text, .id = v.Var };
            num_qv.* += 1;
        }
        return v;
    }
    if (std.fmt.parseInt(i64, text, 10)) |n| return .{ .Int = n } else |_| {}
    if (text[0] == '[' and text[text.len - 1] == ']') {
        return self.kanren.parseListTerm(text[1 .. text.len - 1], null);
    }
    return .{ .Atom = text };
}

// ═══════════════════════════════════════════════════════════
// MLCPD & MCP Commands
// ═══════════════════════════════════════════════════════════

const mlcpd_mod = @import("mlcpd");
const mlcpd_equiv_mod = @import("mlcpd_equiv");
const mcp_server_mod = @import("mcp_server");

pub fn cmdMlcpdParse(self: *Shell, input: []const u8) void {
    const trimmed = std.mem.trim(u8, input, " \t\n\r");
    if (trimmed.len == 0) {
        platform.io.print("usage: mlcpd <json-file-or-inline-json>\n", .{});
        return;
    }

    // Essayer de lire comme fichier d'abord
    const json_data: []const u8 = blk: {
        const file = platform.fs.cwd().openFile(trimmed, .{}) catch {
            // Pas un fichier, traiter comme JSON inline
            break :blk trimmed;
        };
        defer file.close();
        break :blk file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch {
            platform.io.print("error: failed to read file\n", .{});
            return;
        };
    };
    const is_file = !std.mem.eql(u8, json_data.ptr[0..@min(json_data.len, trimmed.len)], trimmed);
    defer if (is_file) self.allocator.free(json_data);

    var parsed = mlcpd_mod.parseMlcpdJson(self.allocator, json_data) catch |err| {
        platform.io.print("error: MLCPD parse failed: {}\n", .{err});
        return;
    };
    defer parsed.deinit();

    platform.io.print("MLCPD Parse Result:\n", .{});
    platform.io.print("  Language: {s}\n", .{@tagName(parsed.metadata.language)});
    platform.io.print("  Nodes: {d}\n", .{parsed.nodeCount()});
    platform.io.print("  Lines: {d}\n", .{parsed.metadata.lines});
    platform.io.print("  Errors: {d}\n", .{parsed.metadata.errors});
}

pub fn cmdMlcpdConvert(self: *Shell, input: []const u8) void {
    const trimmed = std.mem.trim(u8, input, " \t\n\r");
    if (trimmed.len == 0) {
        platform.io.print("usage: mlcpd-convert <json-file-or-inline-json>\n", .{});
        return;
    }

    const json_data: []const u8 = blk: {
        const file = platform.fs.cwd().openFile(trimmed, .{}) catch {
            break :blk trimmed;
        };
        defer file.close();
        break :blk file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch {
            platform.io.print("error: failed to read file\n", .{});
            return;
        };
    };
    const is_file = !std.mem.eql(u8, json_data.ptr[0..@min(json_data.len, trimmed.len)], trimmed);
    defer if (is_file) self.allocator.free(json_data);

    var parsed = mlcpd_mod.parseMlcpdJson(self.allocator, json_data) catch |err| {
        platform.io.print("error: MLCPD parse failed: {}\n", .{err});
        return;
    };
    defer parsed.deinit();

    const expr_id = parsed.toExprIr(&self.heaven.store) catch |err| {
        platform.io.print("error: conversion failed: {}\n", .{err});
        return;
    };

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(self.allocator);
    // Print expression via Heaven.format
    {
        const expr_str = self.heaven.format(expr_id) catch "<error>";
        defer self.allocator.free(expr_str);
        buf.appendSlice(self.allocator, expr_str) catch {};
    }

    platform.io.print("MLCPD → Heaven Expr IR:\n", .{});
    platform.io.print("  Source nodes: {d}\n", .{parsed.nodeCount()});
    platform.io.print("  Expression: {s}\n", .{buf.items});
}

pub fn cmdMlcpdStats(self: *Shell, _: []const u8) void {
    _ = self;
    platform.io.print(
        \\MLCPD Integration Status:
        \\  Schema: Universal AST (4 layers)
        \\  Languages: C, C++, C#, Go, Java, JS, Python, Ruby, Scala, TS
        \\  Format: JSON / Parquet
        \\  Commands:
        \\    mlcpd <file.json>       - Parse MLCPD file
        \\    mlcpd-convert <file>    - Convert to Heaven Expr IR
        \\    mlcpd-stats             - Show this help
        \\  Reference: https://arxiv.org/html/2510.16357v1
        \\
    , .{});
}

pub fn cmdMcpServe(self: *Shell, _: []const u8) void {
    var server = mcp_server_mod.McpServer.init(self.allocator);
    server.ensureHeaven();

    platform.io.print("Starting Heaven MCP Server on stdio...\n", .{});
    platform.io.print("Configure Claude Desktop with:\n", .{});
    platform.io.print("  {{\"mcpServers\": {{\"heaven\": {{\"command\": \"./zig-out/bin/heaven\", \"args\": [\"mcp\"]}}}}}}\n", .{});

    server.run() catch |err| {
        platform.io.print("MCP server error: {}\n", .{err});
        return;
    };

    platform.io.print("MCP server stopped\n", .{});
}

pub fn cmdMlcpdEquiv(self: *Shell, input: []const u8) void {
    const trimmed = std.mem.trim(u8, input, " \t\n\r");
    if (trimmed.len == 0) {
        platform.io.print("usage: mlcpd-equiv <file1.json> <file2.json>\n", .{});
        return;
    }

    // Splitter l'entrée en deux chemins
    var it = std.mem.splitSequence(u8, trimmed, " ");
    const path1 = it.next() orelse {
        platform.io.print("error: missing first file path\n", .{});
        return;
    };
    const path2 = it.next() orelse {
        platform.io.print("error: missing second file path\n", .{});
        return;
    };

    // Parser et convertir le premier fichier
    const json_data1 = blk: {
        const file = platform.fs.cwd().openFile(path1, .{}) catch {
            platform.io.print("error: cannot open file '{s}'\n", .{path1});
            return;
        };
        defer file.close();
        break :blk file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch {
            platform.io.print("error: failed to read file '{s}'\n", .{path1});
            return;
        };
    };
    defer self.allocator.free(json_data1);

    var parsed1 = mlcpd_mod.parseMlcpdJson(self.allocator, json_data1) catch |err| {
        platform.io.print("error: MLCPD parse failed for '{s}': {}\n", .{ path1, err });
        return;
    };
    defer parsed1.deinit();

    parsed1.normalizeParsedFile();
    const expr_id1 = parsed1.toExprIr(&self.heaven.store) catch |err| {
        platform.io.print("error: conversion failed for '{s}': {}\n", .{ path1, err });
        return;
    };

    // Parser et convertir le deuxième fichier
    const json_data2 = blk: {
        const file = platform.fs.cwd().openFile(path2, .{}) catch {
            platform.io.print("error: cannot open file '{s}'\n", .{path2});
            return;
        };
        defer file.close();
        break :blk file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch {
            platform.io.print("error: failed to read file '{s}'\n", .{path2});
            return;
        };
    };
    defer self.allocator.free(json_data2);

    var parsed2 = mlcpd_mod.parseMlcpdJson(self.allocator, json_data2) catch |err| {
        platform.io.print("error: MLCPD parse failed for '{s}': {}\n", .{ path2, err });
        return;
    };
    defer parsed2.deinit();

    parsed2.normalizeParsedFile();
    const expr_id2 = parsed2.toExprIr(&self.heaven.store) catch |err| {
        platform.io.print("error: conversion failed for '{s}': {}\n", .{ path2, err });
        return;
    };

    // Preuve d'équivalence certifiée via MLCPD equiv
    var equiv_result = mlcpd_equiv_mod.proveEquivalence(self.allocator, &self.heaven.store, expr_id1, expr_id2) catch |err| {
        platform.io.print("❌ Erreur lors de la preuve d'équivalence: {}\n", .{err});
        return;
    };
    defer equiv_result.deinit(self.allocator);

    if (equiv_result.equivalent) {
        platform.io.print("EQUIVALENT: Preuve formelle d'équivalence (stratégie: {s})\n", .{@tagName(equiv_result.strategy)});
        if (equiv_result.canon1) |c1| {
            const str1 = self.heaven.format(c1) catch "<error>";
            defer self.allocator.free(str1);
            platform.io.print("  Forme canonique: {s}\n", .{str1});
        }
        if (equiv_result.proof != null) {
            platform.io.print("  📜 Certificat de preuve: disponible\n", .{});
        }
    } else {
        platform.io.print("❌ DIFFERENT: Les expressions ne sont pas équivalentes (stratégie: {s})\n", .{@tagName(equiv_result.strategy)});
        if (equiv_result.error_message) |msg| {
            platform.io.print("  Raison: {s}\n", .{msg});
        }
        if (equiv_result.canon1) |c1| {
            const str1 = self.heaven.format(c1) catch "<error>";
            defer self.allocator.free(str1);
            platform.io.print("  Forme 1 ({s}): {s}\n", .{ @tagName(parsed1.metadata.language), str1 });
        }
        if (equiv_result.canon2) |c2| {
            const str2 = self.heaven.format(c2) catch "<error>";
            defer self.allocator.free(str2);
            platform.io.print("  Forme 2 ({s}): {s}\n", .{ @tagName(parsed2.metadata.language), str2 });
        }
    }
}

// ═══════════════════════════════════════════════════════════
// Multi-language parsing & translation
// ═══════════════════════════════════════════════════════════

pub fn cmdParseFile(self: *Shell, path: []const u8) void {
    const ext = std.fs.path.extension(path);
    const lang = platform.shell_parser_types.Language.fromExtension(ext) orelse {
        platform.debug.print("unsupported extension: {s}\n", .{ext});
        return;
    };
    const content = platform.fs.cwd().readFileAlloc(self.allocator, path, 10 * 1024 * 1024) catch |err| {
        platform.debug.print("error reading {s}: {}\n", .{ path, err });
        return;
    };
    defer self.allocator.free(content);

    if (lang == .heaven) {
        const id = self.heaven.importExpr(content) catch {
            platform.debug.print("parse failed for {s}\n", .{path});
            return;
        };
        platform.debug.print("✓ parsed and evaluated {s} as heaven\n", .{path});
        _ = id;
        return;
    }

    var parser = platform.MultiParser.init(self.allocator, lang) catch |err| {
        platform.debug.print("parser init error: {}\n", .{err});
        return;
    };
    defer parser.deinit();
    const matrix = parser.parse(content) catch {
        platform.debug.print("parse failed for {s}\n", .{@tagName(lang)});
        return;
    };

    const universal_translator = @import("universal_translator");
    var universal = universal_translator.UniversalTranslator.init(self.allocator, &self.heaven.store);
    const mlcpd_lang = switch (lang) {
        .c => @import("mlcpd").FileMetadata.Language.c,
        .zig => @import("mlcpd").FileMetadata.Language.c,
        .pie => @import("mlcpd").FileMetadata.Language.unknown,
        .heaven => unreachable,
    };
    const heaven_id = universal.translate(&matrix, mlcpd_lang) catch {
        platform.debug.print("translation failed for {s}\n", .{@tagName(lang)});
        return;
    };

    self.heaven.engine.fuel = 1_000_000;
    const result = engine_expr.evaluate(&self.heaven.store, &self.heaven.env, &self.heaven.engine, heaven_id, 0) catch heaven_id;
    const result_str = self.heaven.format(result) catch "error";
    defer self.allocator.free(result_str);
    platform.debug.print("✓ translated and evaluated {s} as {s}\n", .{ path, @tagName(lang) });
    platform.debug.print("→ {s}\n", .{result_str});
}

pub fn cmdDumpAstFile(self: *Shell, path: []const u8) void {
    const ext = std.fs.path.extension(path);
    const lang = platform.shell_parser_types.Language.fromExtension(ext) orelse {
        platform.debug.print("unsupported extension: {s}\n", .{ext});
        return;
    };
    const content = platform.fs.cwd().readFileAlloc(self.allocator, path, 10 * 1024 * 1024) catch |err| {
        platform.debug.print("error reading {s}: {}\n", .{ path, err });
        return;
    };
    defer self.allocator.free(content);

    var parser = platform.MultiParser.init(self.allocator, lang) catch |err| {
        platform.debug.print("parser init error: {}\n", .{err});
        return;
    };
    defer parser.deinit();
    const matrix = parser.parse(content) catch {
        platform.debug.print("parse failed for {s}\n", .{@tagName(lang)});
        return;
    };

    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(self.allocator);
    dumpMatrixShell(&matrix, 0, &buf, self.allocator);
    platform.debug.print("{s}", .{buf.items});
}

pub fn cmdTranslateAndDump(self: *Shell, path: []const u8) void {
    const ext = std.fs.path.extension(path);
    const lang = platform.shell_parser_types.Language.fromExtension(ext) orelse {
        platform.debug.print("unsupported extension: {s}\n", .{ext});
        return;
    };
    const content = platform.fs.cwd().readFileAlloc(self.allocator, path, 10 * 1024 * 1024) catch |err| {
        platform.debug.print("error reading {s}: {}\n", .{ path, err });
        return;
    };
    defer self.allocator.free(content);

    var parser = platform.MultiParser.init(self.allocator, lang) catch |err| {
        platform.debug.print("parser init error: {}\n", .{err});
        return;
    };
    defer parser.deinit();
    const matrix = parser.parse(content) catch {
        platform.debug.print("parse failed for {s}\n", .{@tagName(lang)});
        return;
    };

    const universal_translator = @import("universal_translator");
    var universal = universal_translator.UniversalTranslator.init(self.allocator, &self.heaven.store);
    const mlcpd_lang = switch (lang) {
        .c => @import("mlcpd").FileMetadata.Language.c,
        .zig => @import("mlcpd").FileMetadata.Language.c,
        .pie => @import("mlcpd").FileMetadata.Language.unknown,
        .heaven => unreachable,
    };
    const heaven_id = universal.translate(&matrix, mlcpd_lang) catch {
        platform.debug.print("translation failed for {s}\n", .{@tagName(lang)});
        return;
    };

    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(self.allocator);
    writeAstHeavenShell(self, heaven_id, 0, &buf);
    platform.debug.print("{s}", .{buf.items});
}

fn dumpMatrixShell(matrix: *const platform.shell_parser_types.Matrix, depth: u32, buf: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator) void {
    var i: u32 = 0;
    while (i < depth) : (i += 1) buf.appendSlice(alloc, " ") catch return;
    buf.appendSlice(alloc, @tagName(matrix.kind)) catch return;
    if (matrix.text) |text| {
        if (text.len <= 40) {
            buf.appendSlice(alloc, " \"") catch return;
            buf.appendSlice(alloc, text) catch return;
            buf.appendSlice(alloc, "\"") catch return;
        } else {
            buf.appendSlice(alloc, " \"") catch return;
            buf.appendSlice(alloc, text[0..40]) catch return;
            buf.appendSlice(alloc, "...\"") catch return;
        }
    }
    buf.append(alloc, '\n') catch return;
    for (matrix.children) |*child| {
        dumpMatrixShell(child, depth + 1, buf, alloc);
    }
}

fn writeAstHeavenShell(self: *Shell, id: u32, depth: u32, buf: *std.ArrayListUnmanaged(u8)) void {
    if (id >= self.heaven.store.len()) return;
    const node = self.heaven.store.get(id);
    var i: u32 = 0;
    while (i < depth) : (i += 1) buf.appendSlice(self.allocator, " ") catch return;
    switch (node.tag) {
        .sym => {
            buf.appendSlice(self.allocator, "(sym \"") catch return;
            buf.appendSlice(self.allocator, self.heaven.store.interner.resolve(node.payload)) catch return;
            buf.appendSlice(self.allocator, "\")\n") catch return;
        },
        .lit => {
            const l = self.heaven.store.lits.items[node.aux];
            switch (l) {
                .int => |v| {
                    var tmp: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&tmp, "(lit {d})\n", .{v}) catch return;
                    buf.appendSlice(self.allocator, s) catch return;
                },
                else => buf.appendSlice(self.allocator, "(lit ?)\n") catch return,
            }
        },
        .apply => {
            buf.appendSlice(self.allocator, "(apply\n") catch return;
            writeAstHeavenShell(self, node.payload, depth + 1, buf);
            for (node.span_a.slice(self.heaven.store.pool.items)) |child| {
                writeAstHeavenShell(self, child, depth + 1, buf);
            }
            i = 0;
            while (i < depth) : (i += 1) buf.appendSlice(self.allocator, " ") catch return;
            buf.appendSlice(self.allocator, ")\n") catch return;
        },
        .bind => {
            buf.appendSlice(self.allocator, "(bind ") catch return;
            buf.appendSlice(self.allocator, self.heaven.store.interner.resolve(node.payload)) catch return;
            buf.appendSlice(self.allocator, "\n") catch return;
            for (node.span_a.slice(self.heaven.store.pool.items)) |child| {
                writeAstHeavenShell(self, child, depth + 1, buf);
            }
            i = 0;
            while (i < depth) : (i += 1) buf.appendSlice(self.allocator, " ") catch return;
            buf.appendSlice(self.allocator, ")\n") catch return;
        },
        .lambda => {
            buf.appendSlice(self.allocator, "(lambda ") catch return;
            buf.appendSlice(self.allocator, self.heaven.store.interner.resolve(node.payload)) catch return;
            buf.appendSlice(self.allocator, "\n") catch return;
            for (node.span_a.slice(self.heaven.store.pool.items)) |child| {
                writeAstHeavenShell(self, child, depth + 1, buf);
            }
            i = 0;
            while (i < depth) : (i += 1) buf.appendSlice(self.allocator, " ") catch return;
            buf.appendSlice(self.allocator, ")\n") catch return;
        },
        else => {
            buf.appendSlice(self.allocator, "(") catch return;
            buf.appendSlice(self.allocator, @tagName(node.tag)) catch return;
            buf.appendSlice(self.allocator, ")\n") catch return;
        },
    }
}
