//! proofs.zig — Section Preuve de Commands (D4 batch 1).
//! Extraite de src/core/commands.zig. Voir docs/DECISIONS.md (D4).

const std = @import("std");
const expr = @import("expr");
const canon_mod = @import("canon");
const elab_mod = @import("elab");
const platform = @import("platform");
const proof_core = @import("proof_core");
const proof_helpers_mod = @import("proof_helpers");

const Store = expr.Store;
const Id = expr.Id;

fn proveWith(cmds: anytype, target: []const u8, skill_name: []const u8, induction_var: []const u8) anyerror![]u8 {
    const normalized = std.mem.trim(u8, skill_name, " ");
    if (std.mem.eql(u8, normalized, "simplify")) {
        const ok = try cmds.proof_core.verifyBySimplify(target, cmds);
        return proofResult(cmds, target, ok, "simplify");
    }
    if (std.mem.eql(u8, normalized, "eval")) {
        const ok = try cmds.proof_core.verifyByEval(target, cmds.engine, cmds.env, cmds.store);
        return proofResult(cmds, target, ok, "eval");
    }
    if (std.mem.eql(u8, normalized, "induction")) {
        const ok = try cmds.proof_core.verifyByInduction(target, induction_var, cmds, cmds.store);
        return proofResult(cmds, target, ok, "induction");
    }
    if (std.mem.eql(u8, normalized, "rewrite")) {
        const ok = try cmds.proof_core.verifyByRewrite(target, cmds);
        return proofResult(cmds, target, ok, "rewrite");
    }
    return evalSkill(cmds, normalized);
}

fn proofResult(cmds: anytype, target: []const u8, ok: bool, method: []const u8) anyerror![]u8 {
    if (ok) {
        if (cmds.proof_core.theorems.getPtr(target)) |thm| thm.verified = true;
        var buf: [128]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "✓ [{s}] proved ({s})", .{ target, method });
        return try cmds.allocator.dupe(u8, msg);
    } else {
        var buf: [128]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "✗ [{s}] proof failed ({s})", .{ target, method });
        return try cmds.allocator.dupe(u8, msg);
    }
}

pub fn evalTheorem(cmds: anytype, input: []const u8) anyerror![]u8 {
    const colon_pos = std.mem.indexOfScalar(u8, input, ':') orelse
        return try cmds.allocator.dupe(u8, "Usage: theorem <name> : <stmt>");
    const name = std.mem.trim(u8, input[0..colon_pos], " ");
    const stmt = std.mem.trim(u8, input[colon_pos + 1 ..], " ");
    const has_proof_block = std.mem.indexOf(u8, stmt, "{") != null;
    var proof_text: ?[]const u8 = null;
    var stmt_clean = stmt;
    if (has_proof_block) {
        const brace_pos = std.mem.indexOf(u8, stmt, "{").?;
        stmt_clean = std.mem.trim(u8, stmt[0..brace_pos], " ");
        proof_text = stmt[brace_pos..];
        if (!std.mem.startsWith(u8, stmt_clean, "forall") and std.mem.indexOf(u8, stmt_clean, "Eq<") == null) {
            const eq_pos = std.mem.indexOf(u8, stmt_clean, "=") orelse return try cmds.allocator.dupe(u8, "Invalid syntax");
            var lhs = std.mem.trim(u8, stmt_clean[0..eq_pos], " ");
            var rhs = std.mem.trim(u8, stmt_clean[eq_pos + 1 ..], " ");
            var lhs_buf: [256]u8 = undefined;
            var rhs_buf: [256]u8 = undefined;
            const ops = [_]struct { char: u8, name: []const u8 }{
                .{ .char = '+', .name = "add" }, .{ .char = '*', .name = "mul" },
                .{ .char = '-', .name = "sub" }, .{ .char = '/', .name = "div" },
            };
            for (ops) |op| {
                if (std.mem.indexOfScalar(u8, lhs, op.char)) |pos| {
                    const a = std.mem.trim(u8, lhs[0..pos], " ");
                    const b = std.mem.trim(u8, lhs[pos + 1 ..], " ");
                    lhs = try std.fmt.bufPrint(&lhs_buf, "({s} {s} {s})", .{ op.name, a, b });
                    break;
                }
            }
            for (ops) |op| {
                if (std.mem.indexOfScalar(u8, rhs, op.char)) |pos| {
                    const a = std.mem.trim(u8, rhs[0..pos], " ");
                    const b = std.mem.trim(u8, rhs[pos + 1 ..], " ");
                    rhs = try std.fmt.bufPrint(&rhs_buf, "({s} {s} {s})", .{ op.name, a, b });
                    break;
                }
            }
            var buf: [1024]u8 = undefined;
            stmt_clean = try std.fmt.bufPrint(&buf, "Eq<{s}, {s}>", .{ lhs, rhs });
        }
    }
    const is_new_format = std.mem.startsWith(u8, stmt_clean, "forall") or std.mem.indexOf(u8, stmt_clean, "Eq<") != null;
    if (is_new_format) {
        var src_buf: [1024]u8 = undefined;
        const src = try std.fmt.bufPrint(&src_buf, "theorem {s} : {s}", .{ name, stmt_clean });
        var tmp_store = Store.init(cmds.allocator);
        defer tmp_store.deinit();
        //if (@import("builtin").target.cpu.arch == .wasm32) return error.NotSupported;
        platform.dbg("[DEBUG evalTheorem] src to elaborate: '{s}'\n", .{src});
        const root_id = elab_mod.elaborateSource(cmds.allocator, &tmp_store, src, null) catch |err| {
            var buf: [128]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "✗ elaboration failed: {}", .{err});
            return try cmds.allocator.dupe(u8, msg);
        };

        const dbg_str = expr.toString(&tmp_store, root_id, cmds.allocator) catch |err| {
            platform.dbg("[DEBUG evalTheorem] root_id={d} toString FAILED: {}\n", .{ root_id, err });
            const node = tmp_store.get(root_id);
            platform.dbg("[DEBUG evalTheorem] root node tag={s} payload={d} aux={d}\n", .{ @tagName(node.tag), node.payload, node.aux });
            return try cmds.allocator.dupe(u8, "✗ debug: toString failed");
        };
        platform.dbg("[DEBUG evalTheorem] root_id={d} tree={s}\n", .{ root_id, dbg_str });
        cmds.allocator.free(dbg_str);
        const root_node = tmp_store.get(root_id);
        platform.dbg("[DEBUG evalTheorem] root_id={d} tag={s} payload={d} aux={d} span_a.len={d}\n", .{
            root_id, @tagName(root_node.tag), root_node.payload, root_node.aux, root_node.span_a.len,
        });
        if (root_node.span_a.len > 0) {
            const child_id = root_node.span_a.slice(tmp_store.pool.items)[0];
            const child_node = tmp_store.get(child_id);
            platform.dbg("[DEBUG evalTheorem] child_id={d} tag={s} payload={d} aux={d} span_a.len={d}\n", .{
                child_id, @tagName(child_node.tag), child_node.payload, child_node.aux, child_node.span_a.len,
            });
            if (child_node.tag == .apply) {
                const func_node = tmp_store.get(child_node.payload);
                const fname = if (func_node.tag == .sym) tmp_store.interner.resolve(func_node.payload) else "???";
                platform.dbg("[DEBUG evalTheorem] child is apply, func_name='{s}'\n", .{fname});
            }
            if (child_node.tag == .bind) {
                const bname = tmp_store.interner.resolve(child_node.payload);
                const val_node = tmp_store.get(child_node.aux);
                platform.dbg("[DEBUG evalTheorem] child is bind, name='{s}', val_tag={s}\n", .{ bname, @tagName(val_node.tag) });
            }
        }

        const eq_args = proof_helpers_mod.extractEqArgsFromStore(&tmp_store, root_id) orelse
            return try cmds.allocator.dupe(u8, "✗ could not extract Eq<lhs,rhs> from statement");
        const lhs = try proof_helpers_mod.copyIdBetweenStores(&tmp_store, cmds.store, eq_args.lhs);
        const rhs = try proof_helpers_mod.copyIdBetweenStores(&tmp_store, cmds.store, eq_args.rhs);
        const lhs_canon = try canon_mod.canonicalize(cmds.store, cmds.allocator, lhs);
        const rhs_canon = try canon_mod.canonicalize(cmds.store, cmds.allocator, rhs);
        var proof_term: ?*const proof_core.ProofTerm = null;
        if (proof_text) |pt| proof_term = proof_helpers_mod.ProofHelpers.parseProofBlock(cmds.allocator, pt);
        // La preuve simplifie la forme RÉELLE — la canonisation reste
// pour la règle KB ci-dessous (matching), pas pour le théorème.
try cmds.proof_core.theorem(name, stmt, lhs, rhs);            if (proof_term) |pt| {
            if (cmds.proof_core.theorems.getPtr(name)) |thm| {
                thm.proof = pt;
                thm.verified = true;
            }
        }
        const rule_id = try cmds.store.relation("=>", &.{ lhs_canon, rhs_canon }, &.{});
        try cmds.kb.rules.append(cmds.allocator, rule_id);
        if (cmds.active_theorem.*) |old| cmds.allocator.free(old);
        cmds.active_theorem.* = try cmds.allocator.dupe(u8, name);
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "✓ theorem {s} stated", .{name});
        return try cmds.allocator.dupe(u8, msg);
    }
    const eq_pos = std.mem.indexOf(u8, stmt, "=") orelse
        return try cmds.allocator.dupe(u8, "Usage: theorem <name> : <lhs> = <rhs>");
    const lhs_str = std.mem.trim(u8, stmt[0..eq_pos], " ");
    const rhs_str = std.mem.trim(u8, stmt[eq_pos + 1 ..], " ");

    // Parser correctement les côtés de l'équation — voie canonique
    // UNIQUEMENT. Un statement imparsable est REFUSÉ, pas importé
    // via le bridge (parser arithmétique parallèle fabricant des
    // arbres non-foldables — cause de l'échec t_double_zero).
    const lhs = cmds.parseExpression(lhs_str) catch {
        return try cmds.allocator.dupe(u8, "✗ could not parse theorem statement (lhs)");
    };
    const rhs = cmds.parseExpression(rhs_str) catch {
        return try cmds.allocator.dupe(u8, "✗ could not parse theorem statement (rhs)");
    };
    const lhs_canon = try canon_mod.canonicalize(cmds.store, cmds.allocator, lhs);
    const rhs_canon = try canon_mod.canonicalize(cmds.store, cmds.allocator, rhs);
    // La preuve simplifie la forme RÉELLE — la canonisation reste
    // pour la règle KB ci-dessous (matching), pas pour le théorème.
    try cmds.proof_core.theorem(name, stmt, lhs, rhs);
    const rule_id = try cmds.store.relation("=>", &.{ lhs_canon, rhs_canon }, &.{});
    
    try cmds.kb.rules.append(cmds.allocator, rule_id);
    if (cmds.active_theorem.*) |old| cmds.allocator.free(old);
    cmds.active_theorem.* = try cmds.allocator.dupe(u8, name);
    var buf: [256]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, "✓ theorem {s} stated", .{name});
    return try cmds.allocator.dupe(u8, msg);
}

pub fn evalProve(cmds: anytype, input: []const u8) anyerror![]u8 {
    const trimmed = std.mem.trim(u8, input, " ");
    if (std.mem.startsWith(u8, trimmed, "by ")) {
        const rest = trimmed[3..];
        var skill_name: []const u8 = rest;
        var induction_var: []const u8 = "n";
        if (std.mem.indexOf(u8, rest, " on ")) |on_pos| {
            skill_name = std.mem.trim(u8, rest[0..on_pos], " ");
            induction_var = std.mem.trim(u8, rest[on_pos + 4 ..], " ");
        }
        const target = cmds.active_theorem.* orelse
            return try cmds.allocator.dupe(u8, "No active theorem. Use 'theorem <name> : ...' first.");
        const request_msg = try std.fmt.allocPrint(cmds.allocator, "proof_request|{s}|{s}|{s}", .{ target, skill_name, induction_var });
        if (cmds.pending_proof_request.*) |old| cmds.allocator.free(old);
        cmds.pending_proof_request.* = request_msg;
        return proveWith(cmds, target, skill_name, induction_var);
    }
    if (std.mem.indexOf(u8, trimmed, " by ")) |by_pos| {
        const name = std.mem.trim(u8, trimmed[0..by_pos], " ");
        const rest = std.mem.trim(u8, trimmed[by_pos + 4 ..], " ");
        var skill_name: []const u8 = rest;
        var induction_var: []const u8 = "n";
        if (std.mem.indexOf(u8, rest, " on ")) |on_pos| {
            skill_name = std.mem.trim(u8, rest[0..on_pos], " ");
            induction_var = std.mem.trim(u8, rest[on_pos + 4 ..], " ");
        }

        if (cmds.active_theorem.*) |old| cmds.allocator.free(old);
        cmds.active_theorem.* = try cmds.allocator.dupe(u8, name);

        const request_msg = try std.fmt.allocPrint(cmds.allocator, "proof_request|{s}|{s}|{s}", .{ name, skill_name, induction_var });
        if (cmds.pending_proof_request.*) |old| cmds.allocator.free(old);
        cmds.pending_proof_request.* = request_msg;
        return proveWith(cmds, name, skill_name, induction_var);
    }
    return try cmds.allocator.dupe(u8, "Usage: prove [name] by <method> [on <var>]");
}

pub fn evalSkill(cmds: anytype, input: []const u8) anyerror![]u8 {
    const skill_name = std.mem.trim(u8, input, " ");
    const target = cmds.active_theorem.* orelse return try cmds.allocator.dupe(u8, "No active theorem.");
    const thm = cmds.proof_core.theorems.getPtr(target) orelse return try cmds.allocator.dupe(u8, "Theorem not found");
    const ok = if (std.mem.eql(u8, skill_name, "simplify")) try cmds.proof_core.verifyBySimplify(target, cmds) else if (std.mem.eql(u8, skill_name, "eval")) try cmds.proof_core.verifyByEval(target, cmds.engine, cmds.env, cmds.store) else if (std.mem.eql(u8, skill_name, "induction")) try cmds.proof_core.verifyByInduction(target, "n", cmds, cmds.store) else if (std.mem.eql(u8, skill_name, "algebra")) try cmds.proof_core.verifyBySimplify(target, cmds) else return try cmds.allocator.dupe(u8, "skill: unknown tactic");
    if (ok) {
        thm.verified = true;
        var buf: [128]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "✓ [{s}] proved ({s})", .{ target, skill_name });
        return try cmds.allocator.dupe(u8, msg);
    } else return try cmds.allocator.dupe(u8, "✗ proof failed");
}

