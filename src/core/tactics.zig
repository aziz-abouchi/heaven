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
const Goal = ps.Goal;
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
    assumption,
    auto,
    cases: []const u8,
    exact: []const u8,
    induction: []const u8,
    rewrite: []const u8,
    apply: []const u8,
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
        .assumption => return applyAssumption(state, ctx),
        .auto => return applyAuto(state, ctx),
        .cases => |v| return applyCases(state, v, ctx),
        .exact => |n| return applyExact(state, n, ctx),
        .induction => |v| return applyInduction(state, v, ctx),
        .rewrite => |n| return applyRewrite(state, n, ctx),
        .apply => |n| return applyApplyHyp(state, n, ctx),
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
    if (node.payload >= ctx.store.len()) return null;
    const all = ctx.store.spanSliceConst(node.span_a);
    if (all.len < 1) return null;
    const args = all[1..];
    if (args.len != 2) return null;
    for (args) |a| if (a >= ctx.store.len()) return null;
    const fnode = ctx.store.get(node.payload);
    if (fnode.tag != .sym) return null;
    if (fnode.payload >= ctx.store.interner.list.items.len) return null;
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

    // 1. Essai strict (hash-consing / structuralEql).
    const same = ctx.eqFn(ctx, eq.lhs, eq.rhs) catch false;
    if (same) {
        _ = state.popGoal();
        return;
    }

    // 2. Unification DIRECTE — pas d'abstraction de free syms : ce sont
    //    des variables de la cible, les abstraire reviendrait à prouver
    //    n'importe quoi (Eq(a,b) passerait). L'unification ne doit lier
    //    que les evars déjà présentes dans la cible.
    var subst: Subst = .{};
    defer subst.deinit(ctx.allocator);

    const unified = unify(ctx, eq.lhs, eq.rhs, &subst) catch return TacticError.TacticFailed;
    if (!unified) return TacticError.TacticFailed;

    _ = state.popGoal();
}

fn applyAssumption(state: *ProofState, ctx: *TacticCtx) TacticError!void {
    const goal = state.currentGoal() orelse return TacticError.NoGoal;
    for (goal.hyps) |h| {
        const same = ctx.eqFn(ctx, h.ty, goal.target) catch false;
        if (same) {
            _ = state.popGoal();
            return;
        }
    }
    return TacticError.TacticFailed;
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

fn findHyp(goal: *const Goal, name: []const u8) ?Hypothesis {
    for (goal.hyps) |h| {
        if (std.mem.eql(u8, h.name, name)) return h;
    }
    return null;
}

fn isArrowNode(ctx: *TacticCtx, id: Id) ?struct { dom: Id, cod: Id } {
    if (id >= ctx.store.len()) return null;
    const node = ctx.store.get(id);
    if (node.tag != .apply) return null;
    const all = ctx.store.spanSliceConst(node.span_a);
    if (all.len < 1) return null;
    const args = all[1..];
    if (args.len != 2) return null;
    const fnode = ctx.store.get(node.payload);
    if (fnode.tag != .sym) return null;
    const name = ctx.store.interner.resolve(fnode.payload);
    if (!std.mem.eql(u8, name, "->") and
        !std.mem.eql(u8, name, "=>") and
        !std.mem.eql(u8, name, "Π"))
    {
        return null;
    }
    return .{ .dom = args[0], .cod = args[1] };
}

fn rewriteIn(ctx: *TacticCtx, e: Id, from: Id, to: Id) TacticError!Id {
    const same = ctx.eqFn(ctx, e, from) catch false;
    if (same) return to;
    if (e >= ctx.store.len()) return e;
    const node = ctx.store.get(e);
    switch (node.tag) {
        .apply => {
            const new_func = try rewriteIn(ctx, node.payload, from, to);
            // Convention Store : span_a = [head] ++ args (cf. isEqNode,
            // evalSpecialExpr). On skip donc le head, sinon le nœud
            // reconstruit gonfle d'un cran à chaque réécriture.
            const all = ctx.store.spanSliceConst(node.span_a);
            if (all.len < 1) return e;
            const args_copy = try ctx.allocator.dupe(Id, all[1..]);
            defer ctx.allocator.free(args_copy);
            var new_args: std.ArrayListUnmanaged(Id) = .{};
            defer new_args.deinit(ctx.allocator);
            var changed = (new_func != node.payload);
            for (args_copy) |a| {
                const na = try rewriteIn(ctx, a, from, to);
                try new_args.append(ctx.allocator, na);
                if (na != a) changed = true;
            }
            if (!changed) return e;
            return ctx.store.apply(new_func, new_args.items) catch return TacticError.OutOfMemory;
        },
        else => return e,
    }
}

fn applyRewrite(state: *ProofState, h_name: []const u8, ctx: *TacticCtx) TacticError!void {
    const goal = state.currentGoal() orelse return TacticError.NoGoal;
    const h = findHyp(goal, h_name) orelse return TacticError.TacticFailed;
    const eq = isEqNode(ctx, h.ty) orelse return TacticError.TacticFailed;

    const new1 = try rewriteIn(ctx, goal.target, eq.lhs, eq.rhs);

    if (new1 != goal.target) {
        goal.target = new1;
        return;
    }
    const new2 = try rewriteIn(ctx, goal.target, eq.rhs, eq.lhs);
    if (new2 != goal.target) {
        goal.target = new2;
        return;
    }
    return TacticError.TacticFailed;
}

const Subst = std.AutoHashMapUnmanaged(u32, Id);

/// Un symbole qui n'est pas un opérateur connu est considéré comme une
/// variable libre (métavariable implicite).
fn isFreeVarSym(ctx: *TacticCtx, id: Id) bool {
    if (id >= ctx.store.len()) return false;
    const node = ctx.store.get(id);
    if (node.tag != .sym) return false;
    if (node.payload >= ctx.store.interner.list.items.len) return false;
    const name = ctx.store.interner.resolve(node.payload);
    if (name.len == 0) return false;
    // Majuscule → constructeur / type, pas une variable.
    if (name[0] >= 'A' and name[0] <= 'Z') return false;
    // Whitelist d'opérateurs / constantes.
    const whitelist = [_][]const u8{
        "=",     "Eq",   "->",  "=>",  "+",   "-",   "*",    "/",    "%",   "^",
        "==",    "!=",   "<",   ">",   "<=",  ">=",  "succ", "zero", "nil", "true",
        "false", "unit", "add", "mul", "sub", "div", "mod",
    };
    for (whitelist) |w| {
        if (std.mem.eql(u8, name, w)) return false;
    }
    return true;
}

fn collectFreeSyms(
    ctx: *TacticCtx,
    e: Id,
    out: *std.StringHashMapUnmanaged(void),
) TacticError!void {
    if (e >= ctx.store.len()) return;
    const node = ctx.store.get(e);
    if (isFreeVarSym(ctx, e)) {
        const name = ctx.store.interner.resolve(node.payload);
        try out.put(ctx.allocator, name, {});
        return;
    }
    switch (node.tag) {
        .apply => {
            const all = ctx.store.spanSliceConst(node.span_a);
            const args = if (all.len > 0) all[1..] else all;
            for (args) |a| try collectFreeSyms(ctx, a, out);
        },
        .bind, .lambda => {
            const body = node.aux;
            if (body < ctx.store.len()) try collectFreeSyms(ctx, body, out);
        },
        else => {},
    }
}

fn abstractSyms(
    ctx: *TacticCtx,
    e: Id,
    sym_to_evar: *const std.StringHashMapUnmanaged(Id),
) TacticError!Id {
    if (e >= ctx.store.len()) return e;
    if (isFreeVarSym(ctx, e)) {
        const node = ctx.store.get(e);
        const name = ctx.store.interner.resolve(node.payload);
        if (sym_to_evar.get(name)) |ev| return ev;
        return e;
    }
    const node = ctx.store.get(e);
    switch (node.tag) {
        .apply => {
            const new_func = try abstractSyms(ctx, node.payload, sym_to_evar);
            const all = ctx.store.spanSliceConst(node.span_a);
            if (all.len < 1) return e;
            const args_copy = try ctx.allocator.dupe(Id, all[1..]);
            defer ctx.allocator.free(args_copy);
            var new_args: std.ArrayListUnmanaged(Id) = .{};
            defer new_args.deinit(ctx.allocator);
            for (args_copy) |a| {
                try new_args.append(ctx.allocator, try abstractSyms(ctx, a, sym_to_evar));
            }
            return ctx.store.apply(new_func, new_args.items) catch return TacticError.OutOfMemory;
        },
        else => return e,
    }
}

fn instantiate(ctx: *TacticCtx, e: Id, subst: *const Subst) TacticError!Id {
    if (e >= ctx.store.len()) return e;
    if (ctx.store.isEvar(e)) |p| {
        if (subst.get(p)) |bound| return instantiate(ctx, bound, subst);
        return e;
    }
    const node = ctx.store.get(e);
    switch (node.tag) {
        .apply => {
            const new_func = try instantiate(ctx, node.payload, subst);
            const all = ctx.store.spanSliceConst(node.span_a);
            if (all.len < 1) return e;
            const args_copy = try ctx.allocator.dupe(Id, all[1..]);
            defer ctx.allocator.free(args_copy);
            var new_args: std.ArrayListUnmanaged(Id) = .{};
            defer new_args.deinit(ctx.allocator);
            var changed = (new_func != node.payload);
            for (args_copy) |a| {
                const na = try instantiate(ctx, a, subst);
                try new_args.append(ctx.allocator, na);
                if (na != a) changed = true;
            }
            if (!changed) return e;
            return ctx.store.apply(new_func, new_args.items) catch return TacticError.OutOfMemory;
        },
        else => return e,
    }
}

/// Unification simple : remplit `subst` (evar_payload → Id).
fn unify(ctx: *TacticCtx, a: Id, b: Id, subst: *Subst) TacticError!bool {
    if (a == b) return true;

    if (ctx.store.isEvar(a)) |pa| {
        if (subst.get(pa)) |bound| return unify(ctx, bound, b, subst);
        subst.put(ctx.allocator, pa, b) catch return TacticError.OutOfMemory;
        return true;
    }
    if (ctx.store.isEvar(b)) |pb| {
        if (subst.get(pb)) |bound| return unify(ctx, a, bound, subst);
        subst.put(ctx.allocator, pb, a) catch return TacticError.OutOfMemory;
        return true;
    }

    if (expr.structuralEql(ctx.store, a, b)) return true;
    if (a >= ctx.store.len() or b >= ctx.store.len()) return false;

    const na = ctx.store.get(a);
    const nb = ctx.store.get(b);
    if (na.tag != .apply or nb.tag != .apply) return false;

    // Unifie la fonction puis les arguments (span_a = [head] ++ args).
    if (!try unify(ctx, na.payload, nb.payload, subst)) return false;
    const all_a = ctx.store.spanSliceConst(na.span_a);
    const all_b = ctx.store.spanSliceConst(nb.span_a);
    if (all_a.len != all_b.len) return false;
    for (all_a, all_b) |x, y| {
        if (!try unify(ctx, x, y, subst)) return false;
    }
    return true;
}

fn applyApplyHyp(state: *ProofState, h_name: []const u8, ctx: *TacticCtx) TacticError!void {
    const goal = state.currentGoal() orelse return TacticError.NoGoal;
    const h = findHyp(goal, h_name) orelse return TacticError.TacticFailed;

    // 1. Déroule les flèches.
    var current = h.ty;
    var prems: std.ArrayListUnmanaged(Id) = .{};
    defer prems.deinit(ctx.allocator);
    while (isArrowNode(ctx, current)) |arrow| {
        try prems.append(ctx.allocator, arrow.dom);
        current = arrow.cod;
    }

    // 2. Collecte les symboles libres de h.ty (métas implicites).
    var free_syms: std.StringHashMapUnmanaged(void) = .{};
    defer free_syms.deinit(ctx.allocator);
    try collectFreeSyms(ctx, h.ty, &free_syms);

    // 3. Abstrait chaque free sym en une evar fraîche.
    var sym_to_evar: std.StringHashMapUnmanaged(Id) = .{};
    defer {
        var it = sym_to_evar.keyIterator();
        while (it.next()) |k| ctx.allocator.free(k.*);
        sym_to_evar.deinit(ctx.allocator);
    }
    {
        var it = free_syms.keyIterator();
        while (it.next()) |k| {
            const ev = ctx.store.mkEvar() catch return TacticError.OutOfMemory;
            const owned = ctx.allocator.dupe(u8, k.*) catch return TacticError.OutOfMemory;
            sym_to_evar.put(ctx.allocator, owned, ev) catch {
                ctx.allocator.free(owned);
                return TacticError.OutOfMemory;
            };
        }
    }

    const abs_current = try abstractSyms(ctx, current, &sym_to_evar);

    // 4. Unification avec la cible.
    var subst: Subst = .{};
    defer subst.deinit(ctx.allocator);
    const ok = unify(ctx, abs_current, goal.target, &subst) catch return TacticError.TacticFailed;
    if (!ok) return TacticError.TacticFailed;

    // 5. Pop + empile les prémisses instanciées (ordre : prems[0] en tête).
    const hyps_snapshot = goal.hyps;
    _ = state.popGoal();

    var i: usize = prems.items.len;
    while (i > 0) {
        i -= 1;
        const abs_prem = try abstractSyms(ctx, prems.items[i], &sym_to_evar);
        const inst = try instantiate(ctx, abs_prem, &subst);
        const label = state.dupLabel("apply") catch return TacticError.OutOfMemory;
        state.appendGoal(.{
            .hyps = hyps_snapshot,
            .target = inst,
            .label = label,
        }) catch return TacticError.OutOfMemory;
    }
}

fn applyAuto(state: *ProofState, ctx: *TacticCtx) TacticError!void {
    if (state.goals.items.len == 0) return TacticError.NoGoal;
    if (applyAssumption(state, ctx)) |_| return else |_| {}
    if (applyReflexivity(state, ctx)) |_| return else |_| {}
    if (applySimplify(state, ctx)) |_| return else |_| {}
    return TacticError.TacticFailed;
}

fn applyCases(state: *ProofState, var_name: []const u8, ctx: *TacticCtx) TacticError!void {
    const goal = state.currentGoal() orelse return TacticError.NoGoal;

    // Refuse si la variable n'apparaît pas dans la cible.
    const uses = expr.countSymUses(ctx.store, goal.target, var_name);
    if (uses == 0) return TacticError.TacticFailed;

    // Nat uniquement (v4) : base = zero, step = succ(k).
    const zero = ctx.peanoFn(ctx, 0) catch return TacticError.TacticFailed;
    const t_base = ctx.substFn(ctx, goal.target, var_name, zero) catch return TacticError.TacticFailed;

    const k_sym = ctx.store.sym("k") catch return TacticError.TacticFailed;
    const succ_k = ctx.store.call("succ", &.{k_sym}) catch return TacticError.TacticFailed;
    const t_step = ctx.substFn(ctx, goal.target, var_name, succ_k) catch return TacticError.TacticFailed;

    const hyps_snapshot = goal.hyps;
    _ = state.popGoal();

    const label_base = state.dupLabel("base") catch return TacticError.OutOfMemory;
    state.appendGoal(.{
        .hyps = hyps_snapshot,
        .target = t_base,
        .label = label_base,
    }) catch return TacticError.OutOfMemory;

    const label_step = state.dupLabel("step") catch return TacticError.OutOfMemory;
    state.appendGoal(.{
        .hyps = hyps_snapshot,
        .target = t_step,
        .label = label_step,
    }) catch return TacticError.OutOfMemory;
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

    // Snapshot : copie superficielle du tableau (Goal contient des slices
    // allouées dans l'arène, jamais libérées individuellement).
    const snapshot = try ctx.allocator.alloc(Goal, n0);
    defer ctx.allocator.free(snapshot);
    @memcpy(snapshot, state.goals.items[0..n0]);

    // Applique `first`. En cas d'échec, restaure et propage.
    applyTactic(state, first.*, ctx) catch |err| {
        state.goals.clearRetainingCapacity();
        try state.goals.appendSlice(ctx.allocator, snapshot);
        return err;
    };

    // Nombre de sous-buts produits par `first` :
    //   (nouveau total) + 1 - (total avant)  — car first a pop le but de tête.
    const n1 = state.goals.items.len;
    const k = if (n1 + 1 >= n0) n1 + 1 - n0 else 0;
    if (k == 0) return; // first a tout résolu

    // Retire les k sous-buts dans une queue locale pour éviter
    // que les sous-buts produits par `then` ne se mélangent à ceux
    // de `first` (sinon on perdrait des buts ou on en traiterait
    // deux fois).
    var queue: std.ArrayListUnmanaged(Goal) = .{};
    defer queue.deinit(ctx.allocator);
    var i: usize = 0;
    while (i < k) : (i += 1) {
        const g = state.popGoal() orelse break;
        try queue.append(ctx.allocator, g);
    }

    // Applique `then` à chaque sous-but de `first`, dans l'ordre.
    for (queue.items) |g| {
        state.goals.insert(ctx.allocator, 0, g) catch |err| {
            state.goals.clearRetainingCapacity();
            try state.goals.appendSlice(ctx.allocator, snapshot);
            return err;
        };
        applyTactic(state, then.*, ctx) catch |err| {
            state.goals.clearRetainingCapacity();
            try state.goals.appendSlice(ctx.allocator, snapshot);
            return err;
        };
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
    if (std.mem.eql(u8, t, "assumption") or std.mem.eql(u8, t, "auto_assum")) return .assumption;
    if (std.mem.eql(u8, t, "auto")) return .auto;
    if (std.mem.startsWith(u8, t, "cases ")) {
        const v = std.mem.trim(u8, t["cases ".len..], " \t");
        if (v.len == 0) return TacticError.InvalidTactic;
        return .{ .cases = arena.dupe(u8, v) catch return TacticError.OutOfMemory };
    }

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
    if (std.mem.startsWith(u8, t, "rewrite ")) {
        const n = std.mem.trim(u8, t["rewrite ".len..], " \t");
        if (n.len == 0) return TacticError.InvalidTactic;
        return .{ .rewrite = arena.dupe(u8, n) catch return TacticError.OutOfMemory };
    }
    if (std.mem.startsWith(u8, t, "apply ")) {
        const n = std.mem.trim(u8, t["apply ".len..], " \t");
        if (n.len == 0) return TacticError.InvalidTactic;
        return .{ .apply = arena.dupe(u8, n) catch return TacticError.OutOfMemory };
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
            '}', ')' => if (depth > 0) {
                depth -= 1;
            },
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
