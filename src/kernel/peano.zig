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

pub const DeltaScheme = enum {
    peano_add, // add(zero, n) → n ; add(succ(k), n) → succ(add(k, n))
    // d'autres viendront : mul, sub, div...
};

pub const TermPool = struct {
    terms: std.ArrayListUnmanaged(Term),
    axioms: std.ArrayListUnmanaged(AxiomEntry),
    delta_schemes: std.AutoHashMapUnmanaged(u64, DeltaScheme), // name_hash → scheme
    allocator: Allocator,

    pub fn init(allocator: Allocator) TermPool {
        return .{ .terms = .{}, .axioms = .{}, .delta_schemes = .{}, .allocator = allocator };
    }

    pub fn deinit(self: *TermPool) void {
        self.terms.deinit(self.allocator);
        self.axioms.deinit(self.allocator);
        self.delta_schemes.deinit(self.allocator);
    }

    pub fn registerDelta(self: *TermPool, name: []const u8, scheme: DeltaScheme) !void {
        const hash = std.hash.Wyhash.hash(0, name);
        try self.delta_schemes.put(self.allocator, hash, scheme);
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

pub const KernelError = error{
    NotAType,
    NotAFunction,
    TypeMismatch,
    UnboundVariable,
    InvalidAxiom,
    OutOfMemory,
};

// ═══════════════════════════════════════════════════════════
// CONTEXT (typing environment)
// ═══════════════════════════════════════════════════════════

pub const CtxEntry = struct {
    name_hash: u64,
    type_idx: u32,
};

pub const Context = struct {
    entries: std.ArrayList(CtxEntry),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Context {
        return .{
            .entries = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Context) void {
        self.entries.deinit(self.allocator); // Nécessite de passer self.allocator
    }

    pub fn push(self: *Context, name_hash: u64, type_idx: u32) !void {
        try self.entries.append(self.allocator, .{ .name_hash = name_hash, .type_idx = type_idx });
    }

    pub fn pop(self: *Context) void {
        _ = self.entries.pop();
    }

    pub fn lookup(self: *const Context, db_index: u32) ?CtxEntry {
        if (db_index >= self.entries.items.len) return null;
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
                    if (pool.delta_schemes.get(inner_func.payload)) |scheme| {
                        switch (scheme) {
                            .peano_add => {
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
                            },
                            // autres schémas à venir
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
// TYPE INFERENCE & CHECKING
// ═══════════════════════════════════════════════════════════

pub fn infer(pool: *TermPool, ctx: *Context, term_idx: u32) KernelError!u32 {
    const t = pool.get(term_idx);

    switch (t.tag) {
        .type_ => {
            const u = @as(u32, @intCast(t.payload));
            return pool.mkType(u + 1) catch return KernelError.OutOfMemory;
        },

        .var_ => {
            const db_idx = @as(u32, @intCast(t.payload));
            if (ctx.lookup(db_idx)) |entry| {
                return entry.type_idx;
            }
            return KernelError.UnboundVariable;
        },

        .ref => {
            const name_hash = t.payload;
            if (pool.lookupAxiom(name_hash)) |type_idx| {
                return type_idx;
            }
            return KernelError.InvalidAxiom;
        },

        .pi => {
            const dom_ty = @as(u32, @intCast(t.payload));
            const body_ty = @as(u32, @intCast(t.payload2));

            // 1. Validation du domaine A : Type(i)
            const dom_type_idx = try infer(pool, ctx, dom_ty);
            const dom_type_whnf = eval(pool, dom_type_idx) catch return KernelError.NotAType;
            const dom_type_node = pool.get(dom_type_whnf);
            if (dom_type_node.tag != .type_) return KernelError.NotAType;
            const i = @as(u32, @intCast(dom_type_node.payload));

            // 2. Extension du contexte par empilement
            ctx.push(0, dom_ty) catch return KernelError.OutOfMemory;
            defer ctx.pop();

            // 3. Validation du corps B : Type(j)
            const body_type_idx = try infer(pool, ctx, body_ty);
            const body_type_whnf = eval(pool, body_type_idx) catch return KernelError.NotAType;
            const body_type_node = pool.get(body_type_whnf);
            if (body_type_node.tag != .type_) return KernelError.NotAType;
            const j = @as(u32, @intCast(body_type_node.payload));

            // 4. (Π x:A. B) : Type(max(i, j))
            return pool.mkType(@max(i, j)) catch return KernelError.OutOfMemory;
        },

        .lam => {
            const dom_ty = @as(u32, @intCast(t.payload));
            const body = @as(u32, @intCast(t.payload2));

            // Vérification que le type de domaine est valide
            const dom_type_idx = try infer(pool, ctx, dom_ty);
            const dom_type_whnf = eval(pool, dom_type_idx) catch return KernelError.NotAType;
            if (pool.get(dom_type_whnf).tag != .type_) return KernelError.NotAType;

            // Inférence du corps sous le contexte étendu
            ctx.push(0, dom_ty) catch return KernelError.OutOfMemory;
            defer ctx.pop();

            const body_type = try infer(pool, ctx, body);

            // Type de λ x:A. b → Π x:A. B
            return pool.mkPi(dom_ty, body_type) catch return KernelError.OutOfMemory;
        },

        .app => {
            const func = @as(u32, @intCast(t.payload));
            const arg = @as(u32, @intCast(t.payload2));

            const fn_type_idx = try infer(pool, ctx, func);
            const fn_type_whnf = eval(pool, fn_type_idx) catch return KernelError.NotAFunction;
            const fn_node = pool.get(fn_type_whnf);

            if (fn_node.tag != .pi) return KernelError.NotAFunction;
            const pi_dom = @as(u32, @intCast(fn_node.payload));
            const pi_body = @as(u32, @intCast(fn_node.payload2));

            const arg_type_idx = try infer(pool, ctx, arg);

            if (!try convertible(pool, arg_type_idx, pi_dom)) {
                return KernelError.TypeMismatch;
            }

            // Substitution B[x := arg]
            return subst(pool, pi_body, 0, arg) catch return KernelError.OutOfMemory;
        },

        .nat_zero => {
            const nat_hash = std.hash.Wyhash.hash(0, "Nat");
            return pool.mkRef(nat_hash) catch return KernelError.OutOfMemory;
        },

        .nat_succ => {
            const inner = @as(u32, @intCast(t.payload));
            const inner_type = try infer(pool, ctx, inner);
            const nat_hash = std.hash.Wyhash.hash(0, "Nat");
            const nat_ref = pool.mkRef(nat_hash) catch return KernelError.OutOfMemory;

            if (!try convertible(pool, inner_type, nat_ref)) {
                return KernelError.TypeMismatch;
            }
            return nat_ref;
        },

        .eq => {
            const lhs = @as(u32, @intCast(t.payload));
            const rhs = @as(u32, @intCast(t.payload2));

            const lhs_type = try infer(pool, ctx, lhs);
            const rhs_type = try infer(pool, ctx, rhs);

            if (!try convertible(pool, lhs_type, rhs_type)) {
                return KernelError.TypeMismatch;
            }
            return pool.mkType(0) catch return KernelError.OutOfMemory;
        },

        .refl => {
            const val = @as(u32, @intCast(t.payload));
            _ = try infer(pool, ctx, val);
            return pool.mkEq(val, val) catch return KernelError.OutOfMemory;
        },
    }
}

// ═══════════════════════════════════════════════════════════
// TYPE INFERENCE & CHECKING (helpers)
// ═══════════════════════════════════════════════════════════

/// Check that term has the expected type (up to conversion).
pub fn check(pool: *TermPool, ctx: *Context, term_idx: u32, expected_type: u32) KernelError!void {
    const inferred = try infer(pool, ctx, term_idx);
    const ok = try convertible(pool, inferred, expected_type);
    if (!ok) return KernelError.TypeMismatch;
}

/// Verify that a term is a type (i.e., its type is some Type(i)).
fn checkIsType(pool: *TermPool, ctx: *Context, term_idx: u32) KernelError!void {
    const ty = try infer(pool, ctx, term_idx);
    const ty_nf = try eval(pool, ty);
    const t = pool.get(ty_nf);
    if (t.tag != .type_) return KernelError.NotAType;
}

// ═══════════════════════════════════════════════════════════
// PUBLIC API
// ═══════════════════════════════════════════════════════════

/// ═══ BASE DE CONFIANCE — inventaire des affirmations non prouvées ═══
/// Ce que le kernel accepte SANS preuve (chaque entrée = une décision) :
///
/// - Nat, zero, succ, add, mul : primitifs du fragment arithmétique.
/// - δ-règles add : add(zero,n)→n et add(succ k,n)→succ(add k,n)
///   sont DÉFINITIONNELS (c'est la sémantique de add) — sains.
/// - add(n,zero)→n : FIAT. C'est le théorème add_zero érigé en règle
///   de calcul. « x+0=x » passe le kernel parce qu'on le lui a dit.
///   La vraie mesure du kernel : add_comm via nat_ind.
/// - nat_ind : éliminateur de Nat, typage vérifié (indices De Bruijn
///   audités 2026-09-28). Confiance standard (approche no-Inductive).
/// - add_zero_right, add_succ_right : LEMMES ASSERTÉS (axiomes Eq).
///   Prouvables par induction — à déclassifier quand nat_ind sera
///   pleinement actif dans verifyByInduction.
/// ═════════════════════════════════════════════════════════════════════
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
    try pool.registerDelta("add", .peano_add);

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
    // Sous le Πk       : var(0)=k, var(1)=base, var(2)=P
    // Sous le Π(_:P k) : var(0)=h, var(1)=k, var(2)=base, var(3)=P
    const p_k = try pool.mkApp(try pool.mkVar(2), try pool.mkVar(0)); // P(k)
    const p_succ_k = try pool.mkApp(try pool.mkVar(3), try pool.mkSucc(try pool.mkVar(1))); // P(succ k)
    const step_body = try pool.mkPi(p_k, p_succ_k);
    const step_type = try pool.mkPi(nat_ref, step_body);

    // Πn:Nat. P(n)
    // Contexte à l'entrée du codomaine : [P, base, step]
    // Sous le Πn : var(0)=n, var(1)=step, var(2)=base, var(3)=P
    const p_n = try pool.mkApp(try pool.mkVar(3), try pool.mkVar(0)); // P(n)
    const result_type = try pool.mkPi(nat_ref, p_n);

    // Assemblage complet :
    // nat_ind : Π(P:Nat→Type). P(zero) → step_type → result_type
    const after_step = try pool.mkPi(step_type, result_type);
    const after_base = try pool.mkPi(p_zero, after_step);
    const nat_ind_type = try pool.mkPi(nat_to_type, after_base);

    _ = try pool.declareAxiom("nat_ind", nat_ind_type);

    // Lemmes de réduction pour add (utilisés par le type-checker)
    // add_zero_right : Πn:Nat. Eq(add(n, zero), n)
    // Encodé comme axiome pour permettre la conversion dans les preuves
    const add_n_zero_eq_n = try pool.mkPi(nat_ref, try pool.mkEq(try pool.mkApp(try pool.mkApp(try pool.mkRef(std.hash.Wyhash.hash(0, "add")), try pool.mkVar(0)), try pool.mkZero()), try pool.mkVar(0)));
    _ = try pool.declareAxiom("add_zero_right", add_n_zero_eq_n);

    // add_succ_right : Πn:Nat. Πm:Nat. Eq(add(n, succ(m)), succ(add(n, m)))
    const add_n_sm_eq_s_anm = try pool.mkPi(nat_ref, try pool.mkPi(nat_ref, try pool.mkEq(try pool.mkApp(try pool.mkApp(try pool.mkRef(std.hash.Wyhash.hash(0, "add")), try pool.mkVar(1)), try pool.mkSucc(try pool.mkVar(0))), try pool.mkSucc(try pool.mkApp(try pool.mkApp(try pool.mkRef(std.hash.Wyhash.hash(0, "add")), try pool.mkVar(1)), try pool.mkVar(0))))));
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

test "kernel sanity" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    const type0 = try pool.mkType(0);
    const pi_id = try pool.mkPi(type0, type0);
    const inferred = try infer(&pool, &ctx, pi_id);
    const node = pool.terms.items[inferred];
    try std.testing.expectEqual(@as(u64, 1), node.payload);
}

test "Pi rule: Type(i) x Type(j) : Type(max(i,j)+1)" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    const t0 = try pool.mkType(0);
    const t3 = try pool.mkType(3);
    const t7 = try pool.mkType(7);

    // Π(Type(0), Type(0)) : Type(1)
    {
        const pi = try pool.mkPi(t0, t0);
        const inferred = try infer(&pool, &ctx, pi);
        const node = pool.terms.items[inferred];
        try std.testing.expectEqual(TermTag.type_, node.tag);
        try std.testing.expectEqual(@as(u64, 1), node.payload);
    }

    // Π(Type(3), Type(7)) : Type(8) — pas Type(0)
    {
        const pi = try pool.mkPi(t3, t7);
        const inferred = try infer(&pool, &ctx, pi);
        const node = pool.terms.items[inferred];
        try std.testing.expectEqual(TermTag.type_, node.tag);
        try std.testing.expectEqual(@as(u64, 8), node.payload);
    }
}

test "refl: Eq(Type(0), Type(0)) accepted" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    const t0 = try pool.mkType(0);
    const refl_t0 = try pool.mkRefl(t0);
    const eq_t0_t0 = try pool.mkEq(t0, t0);

    try check(&pool, &ctx, refl_t0, eq_t0_t0);
    try std.testing.expect(try verify(&pool, refl_t0, eq_t0_t0));
}

test "type mismatch: refl(Type(0)) rejected against Eq(Type(0), Type(1))" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    const t0 = try pool.mkType(0);
    const t1 = try pool.mkType(1);
    const refl_t0 = try pool.mkRefl(t0);
    const eq_t0_t1 = try pool.mkEq(t0, t1);

    try std.testing.expectError(
        KernelError.TypeMismatch,
        check(&pool, &ctx, refl_t0, eq_t0_t1),
    );
    try std.testing.expect(!try verify(&pool, refl_t0, eq_t0_t1));
}

test "lam: λx:Type(0). x : Π(x:Type(0)). Type(0)" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    const t0 = try pool.mkType(0);
    const v0 = try pool.mkVar(0);
    const lam = try pool.mkLam(t0, v0);
    const inferred = try infer(&pool, &ctx, lam);
    const node = pool.terms.items[inferred];
    try std.testing.expectEqual(TermTag.pi, node.tag);
}

test "impredicativity closed: Π(Type(0), Type(0)) is not Type(0)" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    const t0 = try pool.mkType(0);
    const pi = try pool.mkPi(t0, t0);
    const inferred = try infer(&pool, &ctx, pi);
    const node = pool.terms.items[inferred];
    try std.testing.expect(node.tag == .type_);
    try std.testing.expect(node.payload != 0); // doit être > 0
}

test "Eq : Type(0)" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    const t0 = try pool.mkType(0);
    const eq = try pool.mkEq(t0, t0);
    const inferred = try infer(&pool, &ctx, eq);
    const node = pool.terms.items[inferred];
    try std.testing.expectEqual(TermTag.type_, node.tag);
    try std.testing.expectEqual(@as(u64, 0), node.payload);
}

test "Kernel - Allocation et conversion élémentaire" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();

    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    // Type(0)
    const type0 = try pool.mkType(0);

    // Vérification de la conversion Type(0) == Type(0)
    const is_conv = try convertible(&pool, type0, type0);
    try std.testing.expect(is_conv);
}

test "Kernel - Inférence du type d'un Univers" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();

    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    // Type(0) a pour type Type(1)
    const type0 = try pool.mkType(0);
    const inferred_ty = try infer(&pool, &ctx, type0);

    const ty_obj = pool.get(inferred_ty);
    try std.testing.expectEqual(TermTag.type_, ty_obj.tag);
    try std.testing.expectEqual(@as(u64, 1), ty_obj.payload);
}

test "Kernel - Échec de typage (TypeMismatch)" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();

    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();

    const type0 = try pool.mkType(0);

    // On s'attend à TypeMismatch si on vérifie Type(0) contre Type(0) alors qu'il vaut Type(1)
    const result = check(&pool, &ctx, type0, type0);
    try std.testing.expectError(KernelError.TypeMismatch, result);
}


// BEGIN SANITY TEST nat_ind
test "nat_ind sanity: proves Eq(n,n)" {
    const allocator = std.testing.allocator;
    var pool = TermPool.init(allocator);
    defer pool.deinit();
    try initNatAxioms(&pool);

    const nat_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "Nat"));
    const nat_ind_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "nat_ind"));

    // P = λn. Eq(n, n)
    const P = try pool.mkLam(nat_ref,
        try pool.mkEq(try pool.mkVar(0), try pool.mkVar(0)));

    // base = refl(zero) : Eq(zero, zero)
    const base = try pool.mkRefl(try pool.mkZero());

    // step = λk. λih:(P k). refl(succ k)
    // Sous λk : var(0)=k, P(k) = app(P, var(0))
    // Sous λih : var(0)=ih, var(1)=k, refl(succ k) = refl(succ(var(1)))
    const step = try pool.mkLam(nat_ref,
        try pool.mkLam(try pool.mkApp(P, try pool.mkVar(0)),
            try pool.mkRefl(try pool.mkSucc(try pool.mkVar(1)))));

    const proof_term = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(nat_ind_ref, P), base),
        step);

    // Theorem : Πn:Nat. Eq(n, n)
    const theorem_type = try pool.mkPi(nat_ref,
        try pool.mkEq(try pool.mkVar(0), try pool.mkVar(0)));

    const ok = try verify(&pool, proof_term, theorem_type);
    std.debug.print("[SANITY] nat_ind on Eq(n,n): type_check={}\n", .{ok});
    try std.testing.expect(ok);
}
// END SANITY TEST nat_ind

test "subst shifts replacement under binder" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    // β-réduction : (λz.λw. var(1)) arg  ≡  λw. ↑arg
    // var(1) sous λz.λw désigne la variable 0 du contexte extérieur (z).
    // subst(body, 0, arg) doit :
    //   - entrer sous λw (target+1=1), shifter arg de +1
    //   - matcher var(1) contre target=1, retourner ↑arg
    //   - résultat : λw. ↑arg
    const body_of_lambda_z = try pool.mkLam(try pool.mkType(0),
        try pool.mkVar(1)); // λw. var(1)
    const arg = try pool.mkVar(0); // arg = var(0) du contexte ambiant
    const r = try subst(&pool, body_of_lambda_z, 0, arg);

    // Attendu : lam(_, var(1)) — arg shifté +1, pas var(0)
    const r_node = pool.get(r);
    try std.testing.expectEqual(TermTag.lam, r_node.tag);
    const inner = pool.get(@as(u32, @intCast(r_node.payload2)));
    try std.testing.expectEqual(TermTag.var_, inner.tag);
    try std.testing.expectEqual(@as(u64, 1), inner.payload);
}
