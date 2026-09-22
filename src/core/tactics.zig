//! Tactics — tactiques composables.
//!
//! v1 : simplify, reflexivity, exact, induction, seq, try_, repeat.
//! v1.5 : rewrite, apply, REPL interactif.
//! v2 : unification vraie, cases, auto.

const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Id = expr.Id;
const Store = expr.Store;
const ps = @import("proof_state");
const ProofState = ps.ProofState;
const Hypothesis = ps.Hypothesis;

pub const TacticError = error{
    NoGoal,
    TacticFailed,
    InvalidTactic,
    OutOfMemory,
};

pub const Tactic = union(enum) {
    simplify,
    reflexivity,
    exact: []const u8,
    induction: []const u8,
    seq: struct { first: *const Tactic, then: *const Tactic },
    try_: *const Tactic,
    repeat: *const Tactic,
};

/// Contexte d'exécution : callbacks pour éviter la dépendance circulaire
/// avec Heaven. `heaven` porte un pointeur opaque vers l'instance appelante.
pub const TacticCtx = struct {
    allocator: Allocator,
    store: *Store,
    heaven: *anyopaque,
    simplifyFn: *const fn (*TacticCtx, []const u8) anyerror![]u8,
    eqFn: *const fn (*TacticCtx, Id, Id) anyerror!bool,
    peanoFn: *const fn (*TacticCtx, i64) anyerror!Id,
    substFn: *const fn (*TacticCtx, Id, []const u8, Id) anyerror!Id,
};

pub fn applyTactic(state: *ProofState, t: Tactic, ctx: *TacticCtx) TacticError!void {
    switch (t) {
        .simplify => return applySimplify(state, ctx),
        .reflexivity => return applyReflexivity(state, ctx),
        .exact => |n| return applyExact(state, n, ctx),
        .induction => |v| return applyInduction(state, v, ctx),
        .seq => |s| return applySeq(state, s.first, s.then, ctx),
        .try_ => |inner| return applyTry(state, inner, ctx),
        .repeat => |inner| return applyRepeat(state, inner, ctx),
    }
}

// ─── Aides ───

fn isEqNode(ctx: *TacticCtx, id: Id) ?struct { lhs: Id, rhs: Id } {
    if (id >= ctx.store.len()) return null;
    const node = ctx.store.get(id);
    if (node.tag != .apply) return null;
    // Store.apply(f, args) stocke span_a = [f] ++ args.
    // On saute donc la tête avant de valider l'arité binaire.
    const all = ctx.store.spanSliceConst(node.span_a);
    if (all.len < 1) return null;
    const args = all[1..];
    if (args.len != 2) return null;
    const fnode = ctx.store.get(node.payload);
    if (fnode.tag != .sym) return null;
    const name = ctx.store.interner.resolve(fnode.payload);
    if (!std.mem.eql(u8, name, "=") and !std.mem.eql(u8, name, "Eq")) return null;
    return .{ .lhs = args[0], .rhs = args[1] };
}

// ─── Tactiques atomiques ───

fn applySimplify(state: *ProofState, ctx: *TacticCtx) TacticError!void {
    const goal = state.currentGoal() orelse return TacticError.NoGoal;
    const eq = isEqNode(ctx, goal.target) orelse return TacticError.TacticFailed;

    const a_str = expr.toString(ctx.store, eq.lhs, ctx.allocator) catch return TacticError.TacticFailed;
    defer ctx.allocator.free(a_str);
    const b_str = expr.toString(ctx.store, eq.rhs, ctx.allocator) catch return TacticError.TacticFailed;
    defer ctx.allocator.free(b_str);

    const sa = ctx.simplifyFn(ctx, a_str) catch return TacticError.TacticFailed;
    defer ctx.allocator.free(sa);
    const sb = ctx.simplifyFn(ctx, b_str) catch return TacticError.TacticFailed;
    defer ctx.allocator.free(sb);

    if (std.mem.eql(u8, sa, sb)) {
        _ = state.popGoal();
        return;
    }
    return TacticError.TacticFailed;
}

fn applyReflexivity(state: *ProofState, ctx: *TacticCtx) TacticError!void {
    const goal = state.currentGoal() orelse return TacticError.NoGoal;
    const eq = isEqNode(ctx, goal.target) orelse return TacticError.TacticFailed;
    const same = ctx.eqFn(ctx, eq.lhs, eq.rhs) catch return TacticError.TacticFailed;
    if (!same) return TacticError.TacticFailed;
    _ = state.popGoal();
}

fn applyExact(state: *ProofState, name: []const u8, ctx: *TacticCtx) TacticError!void {
    const goal = state.currentGoal() orelse return TacticError.NoGoal;
    for (goal.hyps) |h| {
        if (!std.mem.eql(u8, h.name, name)) continue;
        const same = ctx.eqFn(ctx, h.ty, goal.target) catch return TacticError.TacticFailed;
        if (same) {
            _ = state.popGoal();
            return;
        }
        return TacticError.TacticFailed;
    }
    return TacticError.TacticFailed;
}

fn applyInduction(state: *ProofState, var_name: []const u8, ctx: *TacticCtx) TacticError!void {
    const goal = state.currentGoal() orelse return TacticError.NoGoal;

    const zero = ctx.peanoFn(ctx, 0) catch return TacticError.TacticFailed;
    const base_target = ctx.substFn(ctx, goal.target, var_name, zero) catch return TacticError.TacticFailed;

    const k_sym = ctx.store.sym("k") catch return TacticError.TacticFailed;
    const succ_k = ctx.store.call("succ", &.{k_sym}) catch return TacticError.TacticFailed;
    const step_target = ctx.substFn(ctx, goal.target, var_name, succ_k) catch return TacticError.TacticFailed;
    const ih_target = ctx.substFn(ctx, goal.target, var_name, k_sym) catch return TacticError.TacticFailed;

    const base_hyps = state.dupHyps(goal.hyps) catch return TacticError.OutOfMemory;
    const step_hyps = state.extendHyps(goal.hyps, .{
        .name = "IH",
        .ty = ih_target,
    }) catch return TacticError.OutOfMemory;

    _ = state.popGoal();

    const base_label = state.dupLabel("base") catch return TacticError.OutOfMemory;
    const step_label = state.dupLabel("step") catch return TacticError.OutOfMemory;

    state.goals.insert(ctx.allocator, 0, .{
        .hyps = base_hyps,
        .target = base_target,
        .label = base_label,
    }) catch return TacticError.OutOfMemory;
    state.goals.insert(ctx.allocator, 1, .{
        .hyps = step_hyps,
        .target = step_target,
        .label = step_label,
    }) catch return TacticError.OutOfMemory;
}

// ─── Combinateurs ───

fn applySeq(state: *ProofState, first: *const Tactic, then: *const Tactic, ctx: *TacticCtx) TacticError!void {
    const n0 = state.goals.items.len;
    if (n0 == 0) return TacticError.NoGoal;

    try applyTactic(state, first.*, ctx);
    const n1 = state.goals.items.len;

    // Le but initial a été consommé : subgoals = n1 - n0 + 1
    if (n1 + 1 < n0) return; // but résolu directement
    const k = n1 + 1 - n0;
    if (k == 0) return;

    // v1 : applique `then` à chacun des k premiers buts.
    var i: usize = 0;
    while (i < k) : (i += 1) {
        if (state.goals.items.len == 0) break;
        try applyTactic(state, then.*, ctx);
    }
}

fn applyTry(state: *ProofState, inner: *const Tactic, ctx: *TacticCtx) TacticError!void {
    applyTactic(state, inner.*, ctx) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return,
    };
}

fn applyRepeat(state: *ProofState, inner: *const Tactic, ctx: *TacticCtx) TacticError!void {
    var iter: u32 = 0;
    const MAX: u32 = 1000;
    while (iter < MAX) : (iter += 1) {
        const before = state.goals.items.len;
        applyTactic(state, inner.*, ctx) catch return;
        if (state.goals.items.len == before) return;
    }
}

// ─── Parsing des tactiques ───

/// Parse une tactique atomique : "simplify", "induction x", "try T", ...
pub fn parseTactic(arena: Allocator, s: []const u8) TacticError!Tactic {
    const t = std.mem.trim(u8, s, " \t\r\n");
    if (t.len == 0) return TacticError.InvalidTactic;

    if (std.mem.eql(u8, t, "simplify")) return .simplify;
    if (std.mem.eql(u8, t, "reflexivity") or std.mem.eql(u8, t, "refl")) return .reflexivity;

    if (std.mem.startsWith(u8, t, "exact ")) {
        const n = std.mem.trim(u8, t["exact ".len..], " \t");
        if (n.len == 0) return TacticError.InvalidTactic;
        return .{ .exact = arena.dupe(u8, n) catch return TacticError.OutOfMemory };
    }
    if (std.mem.startsWith(u8, t, "induction ")) {
        const v = std.mem.trim(u8, t["induction ".len..], " \t");
        if (v.len == 0) return TacticError.InvalidTactic;
        return .{ .induction = arena.dupe(u8, v) catch return TacticError.OutOfMemory };
    }
    if (std.mem.startsWith(u8, t, "try ")) {
        const inner = arena.create(Tactic) catch return TacticError.OutOfMemory;
        inner.* = try parseTactic(arena, t["try ".len..]);
        return .{ .try_ = inner };
    }
    if (std.mem.startsWith(u8, t, "repeat ")) {
        const inner = arena.create(Tactic) catch return TacticError.OutOfMemory;
        inner.* = try parseTactic(arena, t["repeat ".len..]);
        return .{ .repeat = inner };
    }
    return TacticError.InvalidTactic;
}

/// Parse un bloc `t1; t2; t3` (ou juste `t1`). Découpe sur `;` à depth 0,
/// hors chaîne. Les `{`, `}`, `(`, `)` incrémentent la profondeur.
pub fn parseTacticsBlock(arena: Allocator, body: []const u8) TacticError!Tactic {
    var parts: std.ArrayListUnmanaged([]const u8) = .{};
    defer parts.deinit(arena);

    var start: usize = 0;
    var depth: usize = 0;
    var in_str = false;
    var i: usize = 0;
    while (i <= body.len) : (i += 1) {
        const at_end = i == body.len;
        const c: u8 = if (at_end) ';' else body[i];
        if (in_str) {
            if (c == '"') in_str = false;
            continue;
        }
        switch (c) {
            '"' => in_str = true,
            '{', '(' => depth += 1,
            '}', ')' => if (depth > 0) { depth -= 1; },
            ';' => if (depth == 0) {
                const piece = std.mem.trim(u8, body[start..i], " \t\r\n");
                if (piece.len > 0) parts.append(arena, piece) catch return TacticError.OutOfMemory;
                start = i + 1;
            },
            else => {},
        }
    }
    if (parts.items.len == 0) return TacticError.InvalidTactic;

    // Fold right : t1 ; t2 ; t3  →  seq(t1, seq(t2, t3))
    var result = try parseTactic(arena, parts.items[parts.items.len - 1]);
    var j: usize = parts.items.len - 1;
    while (j > 0) {
        j -= 1;
        const first = arena.create(Tactic) catch return TacticError.OutOfMemory;
        first.* = try parseTactic(arena, parts.items[j]);
        const then = arena.create(Tactic) catch return TacticError.OutOfMemory;
        then.* = result;
        const seq = arena.create(Tactic) catch return TacticError.OutOfMemory;
        seq.* = .{ .seq = .{ .first = first, .then = then } };
        result = seq.*;
    }
    return result;
}
