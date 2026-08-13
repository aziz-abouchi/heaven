//! ═══════════════════════════════════════════════════════════
//! HEAVEN KERNEL — Noyau logique auto-hébergé
//! ═══════════════════════════════════════════════════════════
//! Minimal type checker for a simplified Calculus of Inductive Constructions.
//! This is the TRUSTED CORE: everything else can be wrong, but if this
//! says "ok", the proof is valid.
//!
//! Design principles:
//! - No dependencies on engine_expr, heaven_expr, or any evaluation logic
//! - Owns its own Term representation (independent from Store/Expr)
//! - ≤500 lines of actual logic
//! - Every public function is documented with its typing rule

const std = @import("std");
const Allocator = std.mem.Allocator;
const platform = @import("platform");

// ═══════════════════════════════════════════════════════════
// TERM REPRESENTATION
// ═══════════════════════════════════════════════════════════

pub const TermTag = enum(u8) {
    var_, // De Bruijn variable
    app, // Application
    lam, // Lambda abstraction
    pi, // Dependent product (Π-type / forall)
    type_, // Universe Type(i)
    ref, // Named reference (axiom/theorem/definition)
    nat_zero, // Peano zero (built-in for efficiency)
    nat_succ, // Peano succ (built-in for efficiency)
    eq, // Equality type Eq(a, b)
    refl, // Reflexivity proof refl : Eq(a, a)
};

pub const Term = struct {
    tag: TermTag,
    /// Payload depends on tag:
    /// - var_: De Bruijn index (u32)
    /// - app: index into term pool (first arg), second arg stored separately
    /// - lam/pi: type index, body index
    /// - type_: universe level (u32)
    /// - ref: name hash (u64)
    /// - nat_succ: argument index
    /// - eq: lhs index, rhs index
    payload: u64,
    /// Secondary payload for two-child nodes
    payload2: u64,
};

/// Pool-based term storage (arena-style, no individual frees)
/// Signature globale : noms des axiomes/définitions autorisés et leurs types
pub const AxiomEntry = struct {
    name_hash: u64,
    type_idx: u32, // Index du type dans le pool (construit lors de l'init)
};

pub const TermPool = struct {
    terms: std.ArrayListUnmanaged(Term),
    axioms: std.ArrayListUnmanaged(AxiomEntry),
    allocator: Allocator,

    pub fn init(allocator: Allocator) TermPool {
        return .{ .terms = .{}, .axioms = .{}, .allocator = allocator };
    }

    pub fn deinit(self: *TermPool) void {
        self.terms.deinit(self.allocator);
        self.axioms.deinit(self.allocator);
    }

    /// Déclarer un axiome avec son type. Retourne le hash du nom.
    pub fn declareAxiom(self: *TermPool, name: []const u8, type_idx: u32) !u64 {
        const h = std.hash.Wyhash.hash(0, name);
        try self.axioms.append(self.allocator, .{ .name_hash = h, .type_idx = type_idx });
        return h;
    }

    /// Rechercher un axiome par son hash. Retourne null si non trouvé.
    pub fn lookupAxiom(self: *const TermPool, name_hash: u64) ?u32 {
        for (self.axioms.items) |ax| {
            if (ax.name_hash == name_hash) return ax.type_idx;
        }
        return null;
    }

    pub fn alloc(self: *TermPool, tag: TermTag, payload: u64, payload2: u64) !u32 {
        const idx = @as(u32, @intCast(self.terms.items.len));
        try self.terms.append(self.allocator, .{ .tag = tag, .payload = payload, .payload2 = payload2 });
        return idx;
    }

    pub fn get(self: *const TermPool, idx: u32) Term {
        return self.terms.items[idx];
    }

    pub fn len(self: *const TermPool) u32 {
        return @as(u32, @intCast(self.terms.items.len));
    }

    // ── Constructors ──

    pub fn mkVar(self: *TermPool, db_index: u32) !u32 {
        return self.alloc(.var_, db_index, 0);
    }

    pub fn mkApp(self: *TermPool, func: u32, arg: u32) !u32 {
        return self.alloc(.app, func, arg);
    }

    pub fn mkLam(self: *TermPool, ty: u32, body: u32) !u32 {
        return self.alloc(.lam, ty, body);
    }

    pub fn mkPi(self: *TermPool, ty: u32, body: u32) !u32 {
        return self.alloc(.pi, ty, body);
    }

    pub fn mkType(self: *TermPool, level: u32) !u32 {
        return self.alloc(.type_, level, 0);
    }

    pub fn mkRef(self: *TermPool, name_hash: u64) !u32 {
        return self.alloc(.ref, name_hash, 0);
    }

    pub fn mkZero(self: *TermPool) !u32 {
        return self.alloc(.nat_zero, 0, 0);
    }

    pub fn mkSucc(self: *TermPool, arg: u32) !u32 {
        return self.alloc(.nat_succ, arg, 0);
    }

    pub fn mkEq(self: *TermPool, lhs: u32, rhs: u32) !u32 {
        return self.alloc(.eq, lhs, rhs);
    }

    pub fn mkRefl(self: *TermPool, value: u32) !u32 {
        return self.alloc(.refl, value, 0);
    }
};

// ═══════════════════════════════════════════════════════════
// CONTEXT (typing environment)
// ═══════════════════════════════════════════════════════════

/// Typing context: stack of (name_hash, type_term_index)
pub const CtxEntry = struct {
    name_hash: u64,
    type_idx: u32,
};

pub const Context = struct {
    entries: std.ArrayListUnmanaged(CtxEntry),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Context {
        return .{ .entries = .{}, .allocator = allocator };
    }

    pub fn deinit(self: *Context) void {
        self.entries.deinit(self.allocator);
    }

    pub fn push(self: *Context, name_hash: u64, type_idx: u32) !void {
        try self.entries.append(self.allocator, .{ .name_hash = name_hash, .type_idx = type_idx });
    }

    pub fn pop(self: *Context) void {
        _ = self.entries.pop();
    }

    pub fn lookup(self: *const Context, db_index: u32) ?CtxEntry {
        if (db_index >= self.entries.items.len) return null;
        // De Bruijn 0 = most recent binding
        return self.entries.items[self.entries.items.len - 1 - db_index];
    }

    pub fn depth(self: *const Context) u32 {
        return @as(u32, @intCast(self.entries.items.len));
    }
};

// ═══════════════════════════════════════════════════════════
// REDUCTION (βιζ-normalization)
// ═══════════════════════════════════════════════════════════

/// Evaluate a term to weak head normal form.
/// Returns a NEW term index in the pool (never mutates existing terms).
pub fn eval(pool: *TermPool, term_idx: u32) !u32 {
    const t = pool.get(term_idx);
    switch (t.tag) {
        .var_, .type_, .ref, .nat_zero, .refl => return term_idx, // Already WHNF

        .nat_succ => {
            const inner = try eval(pool, @as(u32, @intCast(t.payload)));
            return pool.mkSucc(inner);
        },

        .eq => {
            const lhs = try eval(pool, @as(u32, @intCast(t.payload)));
            const rhs = try eval(pool, @as(u32, @intCast(t.payload2)));
            return pool.mkEq(lhs, rhs);
        },

        .lam => return term_idx, // Lambda is already WHNF

        .pi => {
            const ty = try eval(pool, @as(u32, @intCast(t.payload)));
            const body = try eval(pool, @as(u32, @intCast(t.payload2)));
            return pool.mkPi(ty, body);
        },

        .app => {
            const func_whnf = try eval(pool, @as(u32, @intCast(t.payload)));
            const arg_idx = @as(u32, @intCast(t.payload2));
            const func = pool.get(func_whnf);

            // δ-reduction: règles de calcul pour add
            // add(zero, n) → n
            // add(succ(k), n) → succ(add(k, n))
            if (func.tag == .app) {
                const inner_func = pool.get(@as(u32, @intCast(func.payload)));
                const first_arg = @as(u32, @intCast(func.payload2));
                if (inner_func.tag == .ref) {
                    if (inner_func.payload == std.hash.Wyhash.hash(0, "add")) {
                        const first_arg_nf = try eval(pool, first_arg);
                        const fa = pool.get(first_arg_nf);
                        if (fa.tag == .nat_zero) {
                            // add(zero, n) → n
                            return eval(pool, arg_idx);
                        }
                        // add(n, zero) → n (si le second argument est zero)
                        const second_arg_nf = try eval(pool, arg_idx);
                        const sa = pool.get(second_arg_nf);
                        if (sa.tag == .nat_zero) {
                            return eval(pool, first_arg);
                        }
                        if (fa.tag == .nat_succ) {
                            // add(succ(k), n) → succ(add(k, n))
                            const k = @as(u32, @intCast(fa.payload));
                            const add_k_n = try pool.mkApp(try pool.mkApp(try pool.mkRef(std.hash.Wyhash.hash(0, "add")), k), arg_idx);
                            const reduced = try eval(pool, add_k_n);
                            return pool.mkSucc(reduced);
                        }
                    }
                }
            }

            // β-reduction: (λx:T. body) arg → body[x := arg]
            if (func.tag == .lam) {
                const body = @as(u32, @intCast(func.payload2));
                const substituted = try subst(pool, body, 0, arg_idx);
                return eval(pool, substituted); // Continue reducing
            }

            // Not a lambda → stuck application
            return pool.mkApp(func_whnf, arg_idx);
        },
    }
}

/// Substitute term `replacement` for De Bruijn index `target` in `expr`.
/// Shifts free variables appropriately.
fn subst(pool: *TermPool, expr: u32, target: u32, replacement: u32) !u32 {
    const t = pool.get(expr);
    switch (t.tag) {
        .var_ => {
            const idx = @as(u32, @intCast(t.payload));
            if (idx == target) return replacement;
            if (idx > target) return pool.mkVar(idx - 1); // Shift down past removed binder
            return expr; // Below target, unchanged
        },
        .app => {
            const f = try subst(pool, @as(u32, @intCast(t.payload)), target, replacement);
            const a = try subst(pool, @as(u32, @intCast(t.payload2)), target, replacement);
            return pool.mkApp(f, a);
        },
        .lam, .pi => {
            const ty = try subst(pool, @as(u32, @intCast(t.payload)), target, replacement);
            // Under binder: shift target up, shift replacement up
            const shifted_replacement = try shift(pool, replacement, 0, 1);
            const body = try subst(pool, @as(u32, @intCast(t.payload2)), target + 1, shifted_replacement);
            if (t.tag == .lam) return pool.mkLam(ty, body);
            return pool.mkPi(ty, body);
        },
        .nat_succ => {
            const inner = try subst(pool, @as(u32, @intCast(t.payload)), target, replacement);
            return pool.mkSucc(inner);
        },
        .eq => {
            const lhs = try subst(pool, @as(u32, @intCast(t.payload)), target, replacement);
            const rhs = try subst(pool, @as(u32, @intCast(t.payload2)), target, replacement);
            return pool.mkEq(lhs, rhs);
        },
        .type_, .ref, .nat_zero, .refl => return expr,
    }
}

/// Shift all free De Bruijn indices >= cutoff by delta.
fn shift(pool: *TermPool, expr: u32, cutoff: u32, delta: i32) !u32 {
    const t = pool.get(expr);
    switch (t.tag) {
        .var_ => {
            const idx = @as(u32, @intCast(t.payload));
            if (idx >= cutoff) {
                const new_idx = @as(u32, @intCast(@as(i64, @intCast(idx)) + delta));
                return pool.mkVar(new_idx);
            }
            return expr;
        },
        .app => {
            const f = try shift(pool, @as(u32, @intCast(t.payload)), cutoff, delta);
            const a = try shift(pool, @as(u32, @intCast(t.payload2)), cutoff, delta);
            return pool.mkApp(f, a);
        },
        .lam, .pi => {
            const ty = try shift(pool, @as(u32, @intCast(t.payload)), cutoff, delta);
            const body = try shift(pool, @as(u32, @intCast(t.payload2)), cutoff + 1, delta);
            if (t.tag == .lam) return pool.mkLam(ty, body);
            return pool.mkPi(ty, body);
        },
        .nat_succ => {
            const inner = try shift(pool, @as(u32, @intCast(t.payload)), cutoff, delta);
            return pool.mkSucc(inner);
        },
        .eq => {
            const lhs = try shift(pool, @as(u32, @intCast(t.payload)), cutoff, delta);
            const rhs = try shift(pool, @as(u32, @intCast(t.payload2)), cutoff, delta);
            return pool.mkEq(lhs, rhs);
        },
        .type_, .ref, .nat_zero, .refl => return expr,
    }
}

// ═══════════════════════════════════════════════════════════
// CONVERSIONAL EQUALITY
// ═══════════════════════════════════════════════════════════

/// Check if two terms are convertible (equal after reduction + α-equivalence).
pub fn convertible(pool: *TermPool, a: u32, b: u32) !bool {
    return structuralEq(pool, a, b);
}

/// Structural equality on normalized terms (α-equivalence via De Bruijn).
/// Reduces sub-terms before comparison to handle δ-rules inside Eq, App, etc.
fn structuralEq(pool: *TermPool, a: u32, b: u32) bool {
    if (a == b) return true;
    // Reduce both sides before comparing
    const a_nf = eval(pool, a) catch return false;
    const b_nf = eval(pool, b) catch return false;
    if (a_nf == b_nf) return true;
    const ta = pool.get(a_nf);
    const tb = pool.get(b_nf);
    if (ta.tag != tb.tag) return false;

    switch (ta.tag) {
        .var_ => return ta.payload == tb.payload,
        .type_ => return ta.payload == tb.payload,
        .ref => return ta.payload == tb.payload,
        .nat_zero => return true,
        .app => {
            return structuralEq(pool, @as(u32, @intCast(ta.payload)), @as(u32, @intCast(tb.payload))) and
                structuralEq(pool, @as(u32, @intCast(ta.payload2)), @as(u32, @intCast(tb.payload2)));
        },
        .lam, .pi => {
            // Types must be equal, bodies must be equal (De Bruijn handles α)
            return structuralEq(pool, @as(u32, @intCast(ta.payload)), @as(u32, @intCast(tb.payload))) and
                structuralEq(pool, @as(u32, @intCast(ta.payload2)), @as(u32, @intCast(tb.payload2)));
        },
        .nat_succ => {
            return structuralEq(pool, @as(u32, @intCast(ta.payload)), @as(u32, @intCast(tb.payload)));
        },
        .eq => {
            return structuralEq(pool, @as(u32, @intCast(ta.payload)), @as(u32, @intCast(tb.payload))) and
                structuralEq(pool, @as(u32, @intCast(ta.payload2)), @as(u32, @intCast(tb.payload2)));
        },
        .refl => {
            return structuralEq(pool, @as(u32, @intCast(ta.payload)), @as(u32, @intCast(tb.payload)));
        },
    }
}

// ═══════════════════════════════════════════════════════════
// TYPE CHECKING (the trusted core)
// ═══════════════════════════════════════════════════════════

pub const KernelError = error{
    TypeError,
    UnboundVariable,
    NotAFunction,
    DomainMismatch,
    NotAType,
    NotImplemented,
    OutOfMemory,
};

/// Infer the type of a term in the given context.
/// Returns the index of the inferred type in the pool.
pub fn infer(pool: *TermPool, ctx: *const Context, term_idx: u32) KernelError!u32 {
    const t = pool.get(term_idx);
    switch (t.tag) {
        .var_ => {
            const db = @as(u32, @intCast(t.payload));
            const entry = ctx.lookup(db) orelse return KernelError.UnboundVariable;
            // Shift the type to account for variables between binding site and use site
            return shift(pool, entry.type_idx, 0, @as(i32, @intCast(db + 1))) catch return KernelError.OutOfMemory;
        },

        .type_ => {
            // Type(i) : Type(i+1)
            const level = @as(u32, @intCast(t.payload));
            return pool.mkType(level + 1) catch return KernelError.OutOfMemory;
        },

        .pi => {
            // Γ ⊢ A : Type(i)    Γ,x:A ⊢ B : Type(j)
            // ─────────────────────────────────────────
            // Γ ⊢ Πx:A.B : Type(max(i,j))
            const dom_ty = @as(u32, @intCast(t.payload));
            const body_ty = @as(u32, @intCast(t.payload2));
            _ = try checkIsType(pool, ctx, dom_ty);

            var ext_ctx = Context.init(ctx.allocator);
            defer ext_ctx.deinit();
            // Copy parent context
            for (ctx.entries.items) |e| {
                try ext_ctx.push(e.name_hash, e.type_idx);
            }
            try ext_ctx.push(0, dom_ty); // Push bound variable
            _ = try checkIsType(pool, &ext_ctx, body_ty);

            return pool.mkType(0) catch return KernelError.OutOfMemory; // Simplified: always Type(0)
        },

        .lam => {
            // Γ ⊢ A : Type(i)    Γ,x:A ⊢ t : B
            // ───────────────────────────────────
            // Γ ⊢ λx:A.t : Πx:A.B
            const ann_ty = @as(u32, @intCast(t.payload));
            const body = @as(u32, @intCast(t.payload2));
            try checkIsType(pool, ctx, ann_ty);

            var ext_ctx = Context.init(ctx.allocator);
            defer ext_ctx.deinit();
            for (ctx.entries.items) |e| {
                try ext_ctx.push(e.name_hash, e.type_idx);
            }
            try ext_ctx.push(0, ann_ty);

            const body_type = infer(pool, &ext_ctx, body) catch |err| {
                // platform.debug.print("[KERNEL-DIAG] lam: infer(body) failed: {}\n", .{err});
                // platform.debug.print("\n[KERNEL-DIAG] lam: ctx depth={d}\n", .{ext_ctx.depth()});
                return err;
            };
            return pool.mkPi(ann_ty, body_type) catch return KernelError.OutOfMemory;
        },

        .app => {
            // Γ ⊢ f : Πx:A.B    Γ ⊢ a : A'    A ≡ A'
            // ──────────────────────────────────────────
            // Γ ⊢ f a : B[x := a]
            const func_idx = @as(u32, @intCast(t.payload));
            const arg_idx = @as(u32, @intCast(t.payload2));

            const func_type = try infer(pool, ctx, func_idx);
            const func_type_nf = try eval(pool, func_type);
            const ft = pool.get(func_type_nf);

            if (ft.tag != .pi) return KernelError.NotAFunction;

            const dom = @as(u32, @intCast(ft.payload));
            const codom = @as(u32, @intCast(ft.payload2));

            try check(pool, ctx, arg_idx, dom);

            return subst(pool, codom, 0, arg_idx) catch return KernelError.OutOfMemory;
        },

        .nat_zero => {
            // zero : Nat (we encode Nat as a ref)
            return pool.mkRef(std.hash.Wyhash.hash(0, "Nat")) catch return KernelError.OutOfMemory;
        },

        .nat_succ => {
            // succ n : Nat  if  n : Nat
            const inner = @as(u32, @intCast(t.payload));
            const nat_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "Nat"));
            try check(pool, ctx, inner, nat_ref);
            return nat_ref;
        },

        .eq => {
            // Eq(a, b) : Type(0)  if  a : T  and  b : T
            const lhs = @as(u32, @intCast(t.payload));
            const rhs = @as(u32, @intCast(t.payload2));
            const lhs_ty = try infer(pool, ctx, lhs);
            try check(pool, ctx, rhs, lhs_ty);
            return pool.mkType(0) catch return KernelError.OutOfMemory;
        },

        .refl => {
            // refl : Eq(a, a)  if  a : T
            const val = @as(u32, @intCast(t.payload));
            _ = try infer(pool, ctx, val);
            return pool.mkEq(val, val) catch return KernelError.OutOfMemory;
        },

        .ref => {
            // Lookup in axiom registry
            const name_hash = t.payload;
            if (pool.lookupAxiom(name_hash)) |type_idx| {
                return type_idx;
            }
            return KernelError.UnboundVariable;
        },
    }
}

/// Check that term has the expected type (up to conversion).
pub fn check(pool: *TermPool, ctx: *const Context, term_idx: u32, expected_type: u32) KernelError!void {
    const inferred = try infer(pool, ctx, term_idx);
    const ok = try convertible(pool, inferred, expected_type);
    if (!ok) return KernelError.TypeError;
}

/// Verify that a term is a type (i.e., its type is some Type(i)).
fn checkIsType(pool: *TermPool, ctx: *const Context, term_idx: u32) KernelError!void {
    const ty = try infer(pool, ctx, term_idx);
    const ty_nf = try eval(pool, ty);
    const t = pool.get(ty_nf);
    if (t.tag != .type_) return KernelError.NotAType;
}

// ═══════════════════════════════════════════════════════════
// PUBLIC API
// ═══════════════════════════════════════════════════════════

/// Initialise les axiomes standard pour l'arithmétique Peano.
/// À appeler après init() et avant verify().
pub fn initNatAxioms(pool: *TermPool) !void {
    const nat_hash = std.hash.Wyhash.hash(0, "Nat");
    const type0 = try pool.mkType(0);
    const nat_ref = try pool.mkRef(nat_hash);

    // Nat : Type(0)
    _ = try pool.declareAxiom("Nat", type0);

    // zero : Nat
    _ = try pool.declareAxiom("zero", nat_ref);

    // succ : Nat → Nat
    const nat_to_nat = try pool.mkPi(nat_ref, nat_ref);
    _ = try pool.declareAxiom("succ", nat_to_nat);

    // add : Nat → Nat → Nat
    const nat_to_nat_to_nat = try pool.mkPi(nat_ref, try pool.mkPi(nat_ref, nat_ref));
    _ = try pool.declareAxiom("add", nat_to_nat_to_nat);

    // mul : Nat → Nat → Nat
    _ = try pool.declareAxiom("mul", nat_to_nat_to_nat);

    // ═══ nat_ind : Π(P:Nat→Type). P(zero) → (Πk:Nat. P(k)→P(succ k)) → Πn:Nat. P(n) ═══
    // De Bruijn levels (0 = innermost binder):
    //   Level 0: P (bound by outermost Π)
    //   Dans P(zero) : P appliqué à zero → app(var(0), zero)
    //   Dans Πk:Nat. P(k)→P(succ k) :
    //     Level 0: k, Level 1: P
    //     P(k) = app(var(1), var(0))
    //     P(succ k) = app(var(1), succ(var(0)))
    //   Dans Πn:Nat. P(n) :
    //     Level 0: n, Level 1: P
    //     P(n) = app(var(1), var(0))

    // P : Nat → Type(0)  [sera var(0) dans le corps du Π externe]
    const nat_to_type = try pool.mkPi(nat_ref, type0);

    // P(zero) : app(var(0), zero)
    const p_zero = try pool.mkApp(try pool.mkVar(0), try pool.mkZero());

    // Πk:Nat. P(k) → P(succ k)
    // Sous le Πk : var(0)=k, var(1)=P
    const p_k = try pool.mkApp(try pool.mkVar(1), try pool.mkVar(0)); // P(k)
    const p_succ_k = try pool.mkApp(try pool.mkVar(1), try pool.mkSucc(try pool.mkVar(0))); // P(succ k)
    const step_body = try pool.mkPi(p_k, p_succ_k); // P(k) → P(succ k)
    const step_type = try pool.mkPi(nat_ref, step_body); // Πk:Nat. P(k)→P(succ k)

    // Πn:Nat. P(n)
    // Sous le Πn : var(0)=n, var(1)=P
    const p_n = try pool.mkApp(try pool.mkVar(1), try pool.mkVar(0)); // P(n)
    const result_type = try pool.mkPi(nat_ref, p_n); // Πn:Nat. P(n)

    // Assemblage complet :
    // nat_ind : Π(P:Nat→Type). P(zero) → step_type → result_type
    const after_step = try pool.mkPi(step_type, result_type);
    const after_base = try pool.mkPi(p_zero, after_step);
    const nat_ind_type = try pool.mkPi(nat_to_type, after_base);

    _ = try pool.declareAxiom("nat_ind", nat_ind_type);

    // Lemmes de réduction pour add (utilisés par le type-checker)
    // add_zero_right : Πn:Nat. Eq(add(n, zero), n)
    // Encodé comme axiome pour permettre la conversion dans les preuves
    const add_n_zero_eq_n = try pool.mkPi(nat_ref,
        try pool.mkEq(
            try pool.mkApp(try pool.mkApp(try pool.mkRef(std.hash.Wyhash.hash(0, "add")), try pool.mkVar(0)), try pool.mkZero()),
            try pool.mkVar(0)
        )
    );
    _ = try pool.declareAxiom("add_zero_right", add_n_zero_eq_n);

    // add_succ_right : Πn:Nat. Πm:Nat. Eq(add(n, succ(m)), succ(add(n, m)))
    const add_n_sm_eq_s_anm = try pool.mkPi(nat_ref,
        try pool.mkPi(nat_ref,
            try pool.mkEq(
                try pool.mkApp(try pool.mkApp(try pool.mkRef(std.hash.Wyhash.hash(0, "add")), try pool.mkVar(1)), try pool.mkSucc(try pool.mkVar(0))),
                try pool.mkSucc(try pool.mkApp(try pool.mkApp(try pool.mkRef(std.hash.Wyhash.hash(0, "add")), try pool.mkVar(1)), try pool.mkVar(0)))
            )
        )
    );
    _ = try pool.declareAxiom("add_succ_right", add_n_sm_eq_s_anm);
}

/// Vérification structurelle : valide qu'un terme de preuve par induction
/// est bien formé (bonne arité de nat_ind, base et step présents).
/// C'est une étape intermédiaire avant le typage complet de nat_ind.
pub fn verifyStructural(pool: *TermPool, proof_term: u32) bool {
    const t = pool.get(proof_term);
    // Attendu : app(app(app(nat_ind, P), base), step)
    if (t.tag != .app) return false;

    const outer_func = @as(u32, @intCast(t.payload));
    const step_arg = @as(u32, @intCast(t.payload2));
    _ = step_arg; // step doit exister

    const of = pool.get(outer_func);
    if (of.tag != .app) return false;

    const mid_func = @as(u32, @intCast(of.payload));
    const base_arg = @as(u32, @intCast(of.payload2));
    _ = base_arg; // base doit exister

    const mf = pool.get(mid_func);
    if (mf.tag != .app) return false;

    const nat_ind_idx = @as(u32, @intCast(mf.payload));
    const pred_arg = @as(u32, @intCast(mf.payload2));
    _ = pred_arg; // prédicat P doit exister

    const ni = pool.get(nat_ind_idx);
    if (ni.tag != .ref) return false;

    // Vérifier que c'est bien nat_ind
    const expected_hash = std.hash.Wyhash.hash(0, "nat_ind");
    if (ni.payload != expected_hash) return false;

    return true;
}

/// Top-level verification: check that `proof_term` has type `theorem_type`.
/// This is THE entry point that the rest of Heaven calls.
pub fn verify(pool: *TermPool, proof_term: u32, theorem_type: u32) KernelError!bool {
    var ctx = Context.init(pool.allocator);
    defer ctx.deinit();
    check(pool, &ctx, proof_term, theorem_type) catch return false;
    return true;
}
