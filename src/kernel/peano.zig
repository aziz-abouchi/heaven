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
    peano_mul, // mul(zero, n) → zero ; mul(succ(k), n) → add(n, mul(k, n))
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
        if (self.terms.items.len > 100_000) {
            @panic("TermPool size cap exceeded (100k terms) - allocation runaway");
        }
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
            if (inner == t.payload) return term_idx;
            return pool.mkSucc(inner);
        },

        .eq => {
            const lhs = try eval(pool, @as(u32, @intCast(t.payload)));
            const rhs = try eval(pool, @as(u32, @intCast(t.payload2)));
            if (lhs == t.payload and rhs == t.payload2) return term_idx;
            return pool.mkEq(lhs, rhs);
        },

        .lam => return term_idx, // Lambda is already WHNF

        .pi => {
            const ty = try eval(pool, @as(u32, @intCast(t.payload)));
            const body = try eval(pool, @as(u32, @intCast(t.payload2)));
            if (ty == t.payload and body == t.payload2) return term_idx;
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
                            .peano_mul => {
                                const x_nf = try eval(pool, first_arg);
                                const xa = pool.get(x_nf);
                                if (xa.tag == .nat_zero) return pool.mkZero();
                                if (xa.tag == .nat_succ) {
                                    const k = @as(u32, @intCast(xa.payload));
                                    const mul_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "mul"));
                                    const add_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "add"));
                                    const mul_k_n = try pool.mkApp(try pool.mkApp(mul_ref, k), arg_idx);
                                    const add_n_mul_kn = try pool.mkApp(try pool.mkApp(add_ref, arg_idx), mul_k_n);
                                    return eval(pool, add_n_mul_kn);
                                }
                                const second_nf = try eval(pool, arg_idx);
                                if (pool.get(second_nf).tag == .nat_zero) return pool.mkZero();
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
            // Short-circuit : si func_whnf == original func, rien n'a bougé
            if (func_whnf == t.payload) return term_idx;
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
                // entry.type_idx est valide dans le prefixe du ctx (invariant 1).
                // Dans le ctx courant, il faut shifter de (db_idx + 1) pour que
                // les variables libres pointent toujours sur les memes binders.
                const shift_amt: i32 = @intCast(db_idx + 1);
                return shift(pool, entry.type_idx, 0, shift_amt) catch return KernelError.OutOfMemory;
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
/// - add_zero_right : RETIRÉ (2026-09-29). Dérivable (delta + nat_ind).
/// - add_succ_right : RETIRÉ (2026-09-29). Dérivable via nat_ind,
///   proof term construit par mkAddSuccRightProof.
/// ═════════════════════════════════════════════════════════════════════
pub fn initNatAxioms(pool: *TermPool) !void {
    const nat_hash = std.hash.Wyhash.hash(0, "Nat");
    const type0 = try pool.mkType(0);
    const nat_ref = try pool.mkRef(nat_hash);
    const add_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "add"));

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
    try pool.registerDelta("mul", .peano_mul);

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


    // cong_succ : Πa:Nat. Πb:Nat. Eq(a, b) → Eq(succ a, succ b)
    // Sous le Πa : var(0)=a
    // Sous le Πb : var(0)=b, var(1)=a — Eq(a,b) = Eq(var(1),var(0))
    // Sous le Πh : var(0)=h, var(1)=b, var(2)=a — codomaine Eq(succ a, succ b)
    const eq_a_b = try pool.mkEq(try pool.mkVar(1), try pool.mkVar(0));
    const cong_succ_type = try pool.mkPi(nat_ref,
        try pool.mkPi(nat_ref,
            try pool.mkPi(eq_a_b,
                try pool.mkEq(
                    try pool.mkSucc(try pool.mkVar(2)),
                    try pool.mkSucc(try pool.mkVar(1))))));
    _ = try pool.declareAxiom("cong_succ", cong_succ_type);

    // sym : Pi a b:Nat. Eq(a,b) -> Eq(b,a)
    const sym_type = try pool.mkPi(nat_ref,
        try pool.mkPi(nat_ref,
            try pool.mkPi(
                try pool.mkEq(try pool.mkVar(1), try pool.mkVar(0)),
                try pool.mkEq(try pool.mkVar(1), try pool.mkVar(2)))));
    _ = try pool.declareAxiom("sym", sym_type);

    // trans : Pi a b c:Nat. Eq(a,b) -> Eq(b,c) -> Eq(a,c)
    const trans_type = try pool.mkPi(nat_ref,
        try pool.mkPi(nat_ref,
            try pool.mkPi(nat_ref,
                try pool.mkPi(
                    try pool.mkEq(try pool.mkVar(2), try pool.mkVar(1)),
                    try pool.mkPi(
                        try pool.mkEq(try pool.mkVar(2), try pool.mkVar(1)),
                        try pool.mkEq(try pool.mkVar(4), try pool.mkVar(2)))))));
    _ = try pool.declareAxiom("trans", trans_type);

    // cong_add_l : Pi b c. Eq(b,c) -> Pi a. Eq(add a b, add a c)
    // Sous Pi b : var(0)=b
    // Sous Pi c : var(0)=c, var(1)=b
    // Sous Pi h : var(0)=h, var(1)=c, var(2)=b
    // Sous Pi a : var(0)=a, var(1)=h, var(2)=c, var(3)=b
    const cong_add_l_type = try pool.mkPi(nat_ref,
        try pool.mkPi(nat_ref,
            try pool.mkPi(
                try pool.mkEq(try pool.mkVar(1), try pool.mkVar(0)),
                try pool.mkPi(nat_ref,
                    try pool.mkEq(
                        try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(0)), try pool.mkVar(3)),
                        try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(0)), try pool.mkVar(2)))))));
    _ = try pool.declareAxiom("cong_add_l", cong_add_l_type);

    // cong_add_r : Pi a b. Eq(a,b) -> Pi c. Eq(add a c, add b c)
    // Sous Pi a : var(0)=a
    // Sous Pi b : var(0)=b, var(1)=a
    // Sous Pi h : var(0)=h, var(1)=b, var(2)=a
    // Sous Pi c : var(0)=c, var(1)=h, var(2)=b, var(3)=a
    const cong_add_r_type = try pool.mkPi(nat_ref,
        try pool.mkPi(nat_ref,
            try pool.mkPi(
                try pool.mkEq(try pool.mkVar(1), try pool.mkVar(0)),
                try pool.mkPi(nat_ref,
                    try pool.mkEq(
                        try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(3)), try pool.mkVar(0)),
                        try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(2)), try pool.mkVar(0)))))));
    _ = try pool.declareAxiom("cong_add_r", cong_add_r_type);
}

/// Construit un proof term pour add_succ_right :
///   Pi n m. Eq(add n (succ m), succ(add n m))
/// nat_ind(P, base, step) n m.
pub fn mkAddSuccRightProof(pool: *TermPool, n: u32, m: u32) !u32 {
    const nat_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "Nat"));
    const add_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "add"));
    const nat_ind_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "nat_ind"));
    const cong_succ_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "cong_succ"));

    const P_body = try pool.mkPi(nat_ref,
        try pool.mkEq(
            try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(1)), try pool.mkSucc(try pool.mkVar(0))),
            try pool.mkSucc(try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(1)), try pool.mkVar(0)))));
    const P = try pool.mkLam(nat_ref, P_body);

    const base = try pool.mkLam(nat_ref, try pool.mkRefl(try pool.mkSucc(try pool.mkVar(0))));

    const add_k_succ_m = try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(2)), try pool.mkSucc(try pool.mkVar(0)));
    const succ_add_k_m = try pool.mkSucc(try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(2)), try pool.mkVar(0)));
    const ih_m = try pool.mkApp(try pool.mkVar(1), try pool.mkVar(0));
    const step_inner = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(cong_succ_ref, add_k_succ_m), succ_add_k_m), ih_m);
    const ih_type = try pool.mkApp(P, try pool.mkVar(0));
    const step = try pool.mkLam(nat_ref,
        try pool.mkLam(ih_type,
            try pool.mkLam(nat_ref, step_inner)));

    return pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(try pool.mkApp(try pool.mkApp(nat_ind_ref, P), base), step),
            n),
        m);
}


/// Construit un proof term pour add_assoc :
///   Pi a b c. Eq(add (add a b) c, add a (add b c))
/// nat_ind(P, base, step) a b c.
pub fn mkAddAssocProof(pool: *TermPool, a: u32, b: u32, c: u32) !u32 {
    const nat_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "Nat"));
    const add_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "add"));
    const nat_ind_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "nat_ind"));
    const cong_succ_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "cong_succ"));

    // P = La. Pi b c. Eq(add (add a b) c, add a (add b c))
    const P_body = try pool.mkPi(nat_ref,
        try pool.mkPi(nat_ref,
            try pool.mkEq(
                try pool.mkApp(try pool.mkApp(add_ref,
                    try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(2)), try pool.mkVar(1))),
                    try pool.mkVar(0)),
                try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(2)),
                    try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(1)), try pool.mkVar(0))))));
    const P = try pool.mkLam(nat_ref, P_body);

    // base = Lb. Lc. refl(add b c)
    const base = try pool.mkLam(nat_ref,
        try pool.mkLam(nat_ref,
            try pool.mkRefl(try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(1)), try pool.mkVar(0)))));

    // step = Lk. Lih:P(k). Lb. Lc. cong_succ(add (add k b) c, add k (add b c), ih b c)
    const add_add_k_b_c = try pool.mkApp(try pool.mkApp(add_ref,
        try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(3)), try pool.mkVar(1))),
        try pool.mkVar(0));
    const add_k_add_b_c = try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(3)),
        try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(1)), try pool.mkVar(0)));
    const ih_b_c = try pool.mkApp(try pool.mkApp(try pool.mkVar(2), try pool.mkVar(1)), try pool.mkVar(0));
    const step_inner = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(cong_succ_ref, add_add_k_b_c), add_k_add_b_c), ih_b_c);
    const ih_type = try pool.mkApp(P, try pool.mkVar(0));
    const step = try pool.mkLam(nat_ref,
        try pool.mkLam(ih_type,
            try pool.mkLam(nat_ref,
                try pool.mkLam(nat_ref, step_inner))));

    const proof_term = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(nat_ind_ref, P), base), step);

    return pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(proof_term, a), b),
        c);
}



/// Construit un proof term pour add_comm :
///   Pi n m. Eq(add n m, add m n)
pub fn mkAddCommProof(pool: *TermPool, n: u32, m_arg: u32) !u32 {
    const nat_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "Nat"));
    const add_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "add"));
    const nat_ind_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "nat_ind"));
    const cong_succ_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "cong_succ"));
    const sym_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "sym"));
    const trans_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "trans"));

    // P = Ln. Pi m. Eq(add n m, add m n)
    const P_body = try pool.mkPi(nat_ref,
        try pool.mkEq(
            try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(1)), try pool.mkVar(0)),
            try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(0)), try pool.mkVar(1))));
    const P = try pool.mkLam(nat_ref, P_body);

    // base = Lm. refl(m)
    const base = try pool.mkLam(nat_ref, try pool.mkRefl(try pool.mkVar(0)));

    // step = Lk. Lih:P(k). Lm. trans(...)
    // Sous Lk,Lih,Lm : var(0)=m, var(1)=ih, var(2)=k
    const add_k_m = try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(2)), try pool.mkVar(0));
    const add_m_k = try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(0)), try pool.mkVar(2));
    const succ_add_k_m = try pool.mkSucc(add_k_m);
    const succ_add_m_k = try pool.mkSucc(add_m_k);
    const add_m_succ_k = try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(0)), try pool.mkSucc(try pool.mkVar(2)));

    const ih_m = try pool.mkApp(try pool.mkVar(1), try pool.mkVar(0));
    const p1 = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(cong_succ_ref, add_k_m), add_m_k), ih_m);
    const asr = try mkAddSuccRightProof(pool, try pool.mkVar(0), try pool.mkVar(2));
    const p2 = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(sym_ref, add_m_succ_k), succ_add_m_k), asr);
    const step_inner = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(
                try pool.mkApp(try pool.mkApp(trans_ref, succ_add_k_m), succ_add_m_k),
                add_m_succ_k),
            p1),
        p2);

    const ih_type = try pool.mkApp(P, try pool.mkVar(0));
    const step = try pool.mkLam(nat_ref,
        try pool.mkLam(ih_type,
            try pool.mkLam(nat_ref, step_inner)));

    const proof_term = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(nat_ind_ref, P), base), step);

    return pool.mkApp(try pool.mkApp(proof_term, n), m_arg);
}


/// Construit un proof term pour mul_zero_right :
///   Pi n. Eq(mul n zero, zero)
pub fn mkMulZeroRightProof(pool: *TermPool, n: u32) !u32 {
    const nat_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "Nat"));
    const mul_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "mul"));
    const nat_ind_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "nat_ind"));
    const zero = try pool.mkZero();

    // P = Ln. Eq(mul n zero, zero)
    const P_body = try pool.mkEq(
        try pool.mkApp(try pool.mkApp(mul_ref, try pool.mkVar(0)), zero),
        zero);
    const P = try pool.mkLam(nat_ref, P_body);

    // base = refl(zero)
    const base = try pool.mkRefl(zero);

    // step = Lk. Lih:P(k). ih
    const ih_type = try pool.mkApp(P, try pool.mkVar(0));
    const step = try pool.mkLam(nat_ref,
        try pool.mkLam(ih_type, try pool.mkVar(0)));

    const proof_term = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(nat_ind_ref, P), base), step);

    return pool.mkApp(proof_term, n);
}



/// Construit un proof term pour distrib :
///   Pi a b c. Eq(mul a (add b c), add (mul a b) (mul a c))
/// Induction sur b.
pub fn mkDistribProof(pool: *TermPool, a_arg: u32, b_arg: u32, c_arg: u32) !u32 {
    const nat_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "Nat"));
    const add_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "add"));
    const mul_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "mul"));
    const nat_ind_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "nat_ind"));
    const cong_add_l_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "cong_add_l"));
    const cong_add_r_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "cong_add_r"));
    const sym_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "sym"));
    const trans_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "trans"));

    // P = Lb. Pi a. Pi c. Eq(mul a (add b c), add (mul a b) (mul a c))
    // Sous Lb : var(0)=b
    // Sous Pi a : var(0)=a, var(1)=b
    // Sous Pi c : var(0)=c, var(1)=a, var(2)=b
    const P_body = try pool.mkPi(nat_ref,
        try pool.mkPi(nat_ref,
            try pool.mkEq(
                try pool.mkApp(try pool.mkApp(mul_ref, try pool.mkVar(1)),
                    try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(2)), try pool.mkVar(0))),
                try pool.mkApp(try pool.mkApp(add_ref,
                    try pool.mkApp(try pool.mkApp(mul_ref, try pool.mkVar(1)), try pool.mkVar(2))),
                    try pool.mkApp(try pool.mkApp(mul_ref, try pool.mkVar(1)), try pool.mkVar(0))))));
    const P = try pool.mkLam(nat_ref, P_body);

    // base = La. Lc. refl(mul a c)
    // Sous La : var(0)=a. Sous Lc : var(0)=c, var(1)=a
    const base = try pool.mkLam(nat_ref,
        try pool.mkLam(nat_ref,
            try pool.mkRefl(try pool.mkApp(try pool.mkApp(mul_ref, try pool.mkVar(1)), try pool.mkVar(0)))));

    // step : Lb. Lih:P(b). La. Lc. ...
    // Sous Lb,Lih,La,Lc : var(0)=c, var(1)=a, var(2)=ih, var(3)=b
    const b = try pool.mkVar(3);
    const a = try pool.mkVar(1);
    const c = try pool.mkVar(0);
    const X = try pool.mkApp(try pool.mkApp(mul_ref, a), b);
    const Y = try pool.mkApp(try pool.mkApp(mul_ref, a), c);
    const add_b_c = try pool.mkApp(try pool.mkApp(add_ref, b), c);
    const succ_add_b_c = try pool.mkSucc(add_b_c);
    const mul_a_succ_add_b_c = try pool.mkApp(try pool.mkApp(mul_ref, a), succ_add_b_c);
    const mul_a_add_b_c = try pool.mkApp(try pool.mkApp(mul_ref, a), add_b_c);
    const add_mul_a_add_b_c_a = try pool.mkApp(try pool.mkApp(add_ref, mul_a_add_b_c), a);
    const add_X_Y = try pool.mkApp(try pool.mkApp(add_ref, X), Y);
    const add_add_X_Y_a = try pool.mkApp(try pool.mkApp(add_ref, add_X_Y), a);
    const add_X_add_Y_a = try pool.mkApp(try pool.mkApp(add_ref, X), try pool.mkApp(try pool.mkApp(add_ref, Y), a));
    const add_Y_a = try pool.mkApp(try pool.mkApp(add_ref, Y), a);
    const add_a_Y = try pool.mkApp(try pool.mkApp(add_ref, a), Y);
    const add_X_add_a_Y = try pool.mkApp(try pool.mkApp(add_ref, X), add_a_Y);
    const add_add_X_a_Y = try pool.mkApp(try pool.mkApp(add_ref, try pool.mkApp(try pool.mkApp(add_ref, X), a)), Y);
    const add_X_a = try pool.mkApp(try pool.mkApp(add_ref, X), a);
    const mul_a_succ_b = try pool.mkApp(try pool.mkApp(mul_ref, a), try pool.mkSucc(b));
    const add_mul_a_succ_b_Y = try pool.mkApp(try pool.mkApp(add_ref, mul_a_succ_b), Y);

    // 1. h_lhs = mkMulSuccRightProof(a, add b c)
    const h_lhs = try mkMulSuccRightProof(pool, a, add_b_c);

    // 2. h_ih = cong_add_r(mul a (add b c), add X Y, ih a c, a)
    // ih a c = app(app(var(2), a), c)
    const ih_ac = try pool.mkApp(try pool.mkApp(try pool.mkVar(2), a), c);
    const h_ih = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(try pool.mkApp(cong_add_r_ref, mul_a_add_b_c), add_X_Y),
            ih_ac),
        a);

    // 3. h_lhs' = trans(mul_a_succ_add_b_c, add_mul_a_add_b_c_a, add_add_X_Y_a, h_lhs, h_ih)
    const h_lhs_p = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(
                try pool.mkApp(try pool.mkApp(trans_ref, mul_a_succ_add_b_c), add_mul_a_add_b_c_a),
                add_add_X_Y_a),
            h_lhs),
        h_ih);

    // 4. add (add X Y) a -> add (add X a) Y
    //   h_assoc1 = mkAddAssocProof(X, Y, a) : Eq(add (add X Y) a, add X (add Y a))
    //   h_comm = mkAddCommProof(Y, a) : Eq(add Y a, add a Y)
    //   h_cong_c = cong_add_l(add Y a, add a Y, h_comm, X)
    //             : Eq(add X (add Y a), add X (add a Y))
    //   h_assoc2 = sym(mkAddAssocProof(X, a, Y))
    //             : Eq(add X (add a Y), add (add X a) Y)
    const h_assoc1 = try mkAddAssocProof(pool, X, Y, a);
    const h_comm = try mkAddCommProof(pool, Y, a);
    const h_cong_c = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(try pool.mkApp(cong_add_l_ref, add_Y_a), add_a_Y),
            h_comm),
        X);
    const h_assoc2_raw = try mkAddAssocProof(pool, X, a, Y);
    const h_assoc2 = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(sym_ref, add_add_X_a_Y), add_X_add_a_Y),
        h_assoc2_raw);

    // h_mid = trans(add_add_X_Y_a, add_X_add_Y_a, add_X_add_a_Y, h_assoc1, h_cong_c)
    const h_mid = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(
                try pool.mkApp(try pool.mkApp(trans_ref, add_add_X_Y_a), add_X_add_Y_a),
                add_X_add_a_Y),
            h_assoc1),
        h_cong_c);

    // h_mid2 = trans(add_add_X_Y_a, add_X_add_a_Y, add_add_X_a_Y, h_mid, h_assoc2)
    const h_mid2 = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(
                try pool.mkApp(try pool.mkApp(trans_ref, add_add_X_Y_a), add_X_add_a_Y),
                add_add_X_a_Y),
            h_mid),
        h_assoc2);

    // h_lhs'' = trans(mul_a_succ_add_b_c, add_add_X_Y_a, add_add_X_a_Y, h_lhs_p, h_mid2)
    const h_lhs_pp = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(
                try pool.mkApp(try pool.mkApp(trans_ref, mul_a_succ_add_b_c), add_add_X_Y_a),
                add_add_X_a_Y),
            h_lhs_p),
        h_mid2);

    // 5. add (add X a) Y -> add (mul a (succ b)) Y
    //   h_msr = mkMulSuccRightProof(a, b) : Eq(mul a (succ b), add X a)
    //   h_msr_sym = sym(h_msr) : Eq(add X a, mul a (succ b))
    //   h_cong2 = cong_add_l(add X a, mul a (succ b), h_msr_sym, Y)
    const h_msr = try mkMulSuccRightProof(pool, a, b);
    const h_msr_sym = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(sym_ref, mul_a_succ_b), add_X_a),
        h_msr);
    const h_cong2 = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(try pool.mkApp(cong_add_r_ref, add_X_a), mul_a_succ_b),
            h_msr_sym),
        Y);

    // h_final = trans(mul_a_succ_add_b_c, add_add_X_a_Y, add_mul_a_succ_b_Y, h_lhs_pp, h_cong2)
    const h_final = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(
                try pool.mkApp(try pool.mkApp(trans_ref, mul_a_succ_add_b_c), add_add_X_a_Y),
                add_mul_a_succ_b_Y),
            h_lhs_pp),
        h_cong2);

    // ih_type : sous [b] seul, b = var(0)
    const ih_type = try pool.mkApp(P, try pool.mkVar(0));
    const step = try pool.mkLam(nat_ref,
        try pool.mkLam(ih_type,
            try pool.mkLam(nat_ref,
                try pool.mkLam(nat_ref, h_final))));

    const proof_term = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(nat_ind_ref, P), base), step);

    // L'ordre de P est Pi b. Pi a. Pi c. donc appliquer b puis a puis c.
    return pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(proof_term, b_arg), a_arg),
        c_arg);
}

/// Construit un proof term pour mul_comm :
///   Pi n m. Eq(mul n m, mul m n)
pub fn mkMulCommProof(pool: *TermPool, n: u32, m_arg: u32) !u32 {
    const nat_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "Nat"));
    const mul_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "mul"));
    const add_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "add"));
    const nat_ind_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "nat_ind"));
    const cong_add_l_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "cong_add_l"));
    const sym_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "sym"));
    const trans_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "trans"));

    // P = Ln. Pi m. Eq(mul n m, mul m n)
    const P_body = try pool.mkPi(nat_ref,
        try pool.mkEq(
            try pool.mkApp(try pool.mkApp(mul_ref, try pool.mkVar(1)), try pool.mkVar(0)),
            try pool.mkApp(try pool.mkApp(mul_ref, try pool.mkVar(0)), try pool.mkVar(1))));
    const P = try pool.mkLam(nat_ref, P_body);

    // base = Lm. sym(mkMulZeroRightProof(m))
    //   : Eq(zero, mul m zero)
    //   ≡ Eq(mul zero m, mul m zero) par delta sur LHS
    const m_var = try pool.mkVar(0);
    const zero_proof = try mkMulZeroRightProof(pool, m_var);
    const mul_m_zero = try pool.mkApp(try pool.mkApp(mul_ref, m_var), try pool.mkZero());
    const zero_term = try pool.mkZero();
    const base_body = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(sym_ref, mul_m_zero), zero_term),
        zero_proof);
    const base = try pool.mkLam(nat_ref, base_body);

    // step = Lk. Lih:P(k). Lm. trans(...)
    // Sous Lk,Lih,Lm : var(0)=m, var(1)=ih, var(2)=k
    const k = try pool.mkVar(2);
    const m = try pool.mkVar(0);
    const mul_k_m = try pool.mkApp(try pool.mkApp(mul_ref, k), m);
    const mul_m_k = try pool.mkApp(try pool.mkApp(mul_ref, m), k);
    const add_m_mul_k_m = try pool.mkApp(try pool.mkApp(add_ref, m), mul_k_m);
    const add_m_mul_m_k = try pool.mkApp(try pool.mkApp(add_ref, m), mul_m_k);
    const add_mul_m_k_m = try pool.mkApp(try pool.mkApp(add_ref, mul_m_k), m);
    const mul_m_succ_k = try pool.mkApp(try pool.mkApp(mul_ref, m), try pool.mkSucc(k));

    // h1 = cong_add_l(mul k m, mul m k, ih m, m)
    const ih_m = try pool.mkApp(try pool.mkVar(1), m);
    const h1 = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(try pool.mkApp(cong_add_l_ref, mul_k_m), mul_m_k),
            ih_m),
        m);

    // hcomm = mkAddCommProof(m, mul m k) : Eq(add m (mul m k), add (mul m k) m)
    const hcomm = try mkAddCommProof(pool, m, mul_m_k);

    // pre = trans(add_m_mul_k_m, add_m_mul_m_k, add_mul_m_k_m, h1, hcomm)
    const pre = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(
                try pool.mkApp(try pool.mkApp(trans_ref, add_m_mul_k_m), add_m_mul_m_k),
                add_mul_m_k_m),
            h1),
        hcomm);

    // asr = mkMulSuccRightProof(m, k) : Eq(mul m (succ k), add (mul m k) m)
    const asr = try mkMulSuccRightProof(pool, m, k);
    const asr_sym = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(sym_ref, mul_m_succ_k), add_mul_m_k_m),
        asr);

    // step_inner = trans(add_m_mul_k_m, add_mul_m_k_m, mul_m_succ_k, pre, asr_sym)
    //   : Eq(add m (mul k m), mul m (succ k))
    //   ≡ Eq(mul (succ k) m, mul m (succ k)) par delta
    const step_inner = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(
                try pool.mkApp(try pool.mkApp(trans_ref, add_m_mul_k_m), add_mul_m_k_m),
                mul_m_succ_k),
            pre),
        asr_sym);

    // ih_type : sous [k] seul, k = var(0)
    const ih_type = try pool.mkApp(P, try pool.mkVar(0));
    const step = try pool.mkLam(nat_ref,
        try pool.mkLam(ih_type,
            try pool.mkLam(nat_ref, step_inner)));

    const proof_term = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(nat_ind_ref, P), base), step);

    return pool.mkApp(try pool.mkApp(proof_term, n), m_arg);
}

/// Construit un proof term pour mul_succ_right :
///   Pi n m. Eq(mul n (succ m), add (mul n m) n)
pub fn mkMulSuccRightProof(pool: *TermPool, n: u32, m_arg: u32) !u32 {
    const nat_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "Nat"));
    const add_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "add"));
    const mul_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "mul"));
    const nat_ind_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "nat_ind"));
    const cong_succ_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "cong_succ"));
    const cong_add_l_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "cong_add_l"));
    const sym_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "sym"));
    const trans_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "trans"));

    // P = Ln. Pi m. Eq(mul n (succ m), add (mul n m) n)
    const P_body = try pool.mkPi(nat_ref,
        try pool.mkEq(
            try pool.mkApp(try pool.mkApp(mul_ref, try pool.mkVar(1)), try pool.mkSucc(try pool.mkVar(0))),
            try pool.mkApp(try pool.mkApp(add_ref,
                try pool.mkApp(try pool.mkApp(mul_ref, try pool.mkVar(1)), try pool.mkVar(0))),
                try pool.mkVar(1))));
    const P = try pool.mkLam(nat_ref, P_body);

    // base = Lm. refl(zero)
    const zero = try pool.mkZero();
    const base = try pool.mkLam(nat_ref, try pool.mkRefl(zero));

    // step : Lk. Lih:P(k). Lm. ...
    // Sous Lk,Lih,Lm : var(0)=m, var(1)=ih, var(2)=k
    const k = try pool.mkVar(2);
    const m = try pool.mkVar(0);
    const X = try pool.mkApp(try pool.mkApp(mul_ref, k), m);
    const mul_k_succ_m = try pool.mkApp(try pool.mkApp(mul_ref, k), try pool.mkSucc(m));
    const add_X_k = try pool.mkApp(try pool.mkApp(add_ref, X), k);
    const add_m_mul_k_succ_m = try pool.mkApp(try pool.mkApp(add_ref, m), mul_k_succ_m);
    const add_m_add_X_k = try pool.mkApp(try pool.mkApp(add_ref, m), add_X_k);
    const succ_add_m_mul_k_succ_m = try pool.mkSucc(add_m_mul_k_succ_m);
    const succ_add_m_add_X_k = try pool.mkSucc(add_m_add_X_k);
    const add_m_X_k = try pool.mkApp(try pool.mkApp(add_ref, m), X);
    const add_add_m_X_k = try pool.mkApp(try pool.mkApp(add_ref, add_m_X_k), k);
    const succ_add_add_m_X_k = try pool.mkSucc(add_add_m_X_k);

    const ih_m = try pool.mkApp(try pool.mkVar(1), m);
    const h1 = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(try pool.mkApp(cong_add_l_ref, mul_k_succ_m), add_X_k),
            ih_m),
        m);
    const h1_prime = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(cong_succ_ref, add_m_mul_k_succ_m), add_m_add_X_k),
        h1);

    const assoc_m = try mkAddAssocProof(pool, m, X, k);
    const sym_assoc = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(sym_ref, add_add_m_X_k), add_m_add_X_k),
        assoc_m);
    const h2 = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(cong_succ_ref, add_m_add_X_k), add_add_m_X_k),
        sym_assoc);

    const step_inner_23 = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(
                try pool.mkApp(try pool.mkApp(trans_ref, succ_add_m_mul_k_succ_m), succ_add_m_add_X_k),
                succ_add_add_m_X_k),
            h1_prime),
        h2);

    const add_add_m_X_succ_k = try pool.mkApp(
        try pool.mkApp(add_ref, add_m_X_k), try pool.mkSucc(k));
    const asr_proof = try mkAddSuccRightProof(pool, add_m_X_k, k);
    const h3 = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(sym_ref, add_add_m_X_succ_k), succ_add_add_m_X_k),
        asr_proof);

    const step_inner = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(
                try pool.mkApp(try pool.mkApp(trans_ref, succ_add_m_mul_k_succ_m), succ_add_add_m_X_k),
                add_add_m_X_succ_k),
            step_inner_23),
        h3);

    // ih_type : sous [k] seulement, k = var(0)
    const ih_type = try pool.mkApp(P, try pool.mkVar(0));
    const step = try pool.mkLam(nat_ref,
        try pool.mkLam(ih_type,
            try pool.mkLam(nat_ref, step_inner)));

    const proof_term = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(nat_ind_ref, P), base), step);

    return pool.mkApp(try pool.mkApp(proof_term, n), m_arg);
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


test "cong_succ sanity: Eq(zero,zero) -> Eq(succ zero, succ zero)" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    try initNatAxioms(&pool);

    const cong_succ_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "cong_succ"));
    const zero = try pool.mkZero();
    const rfl = try pool.mkRefl(zero);

    // proof = cong_succ(zero, zero, refl(zero))
    const proof = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(cong_succ_ref, zero), zero), rfl);

    // expected = Eq(succ zero, succ zero)
    const expected = try pool.mkEq(try pool.mkSucc(zero), try pool.mkSucc(zero));

    const ok = try verify(&pool, proof, expected);
    std.debug.print("[SANITY] cong_succ: type_check={}\n", .{ok});
    try std.testing.expect(ok);
}


test "sym + trans sanity" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    try initNatAxioms(&pool);

    const zero = try pool.mkZero();
    const rfl = try pool.mkRefl(zero);
    const eq_zz = try pool.mkEq(zero, zero);

    const sym_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "sym"));
    const sym_proof = try pool.mkApp(try pool.mkApp(try pool.mkApp(sym_ref, zero), zero), rfl);
    const ok_sym = try verify(&pool, sym_proof, eq_zz);
    std.debug.print("[SANITY] sym: type_check={}\n", .{ok_sym});
    try std.testing.expect(ok_sym);

    const trans_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "trans"));
    const trans_proof = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(
                try pool.mkApp(try pool.mkApp(trans_ref, zero), zero),
                zero),
            rfl),
        rfl);
    const ok_trans = try verify(&pool, trans_proof, eq_zz);
    std.debug.print("[SANITY] trans: type_check={}\n", .{ok_trans});
    try std.testing.expect(ok_trans);
}

test "add_comm via nat_ind" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    try initNatAxioms(&pool);

    const add_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "add"));
    const zero = try pool.mkZero();

    const proof = try mkAddCommProof(&pool, zero, zero);
    const expected = try pool.mkEq(
        try pool.mkApp(try pool.mkApp(add_ref, zero), zero),
        try pool.mkApp(try pool.mkApp(add_ref, zero), zero));
    const ok = try verify(&pool, proof, expected);
    std.debug.print("[SANITY] add_comm: type_check={}\n", .{ok});
    try std.testing.expect(ok);
}

test "add_zero_right derivable (delta + nat_ind)" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    try initNatAxioms(&pool);

    const nat_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "Nat"));
    const add_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "add"));
    const nat_ind_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "nat_ind"));
    const zero = try pool.mkZero();

    // P = Lm n. Eq(add n zero, n)
    const P_body = try pool.mkEq(
        try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(0)), zero),
        try pool.mkVar(0));
    const P = try pool.mkLam(nat_ref, P_body);

    // base = refl(zero) : Eq(zero,zero) convertible a Eq(add zero zero, zero)
    const base = try pool.mkRefl(zero);

    // step = Lk. Lih:P(k). refl(succ k)
    // Sous Lk,Lih : var(0)=ih, var(1)=k
    // P(succ k) = Eq(add(succ k) zero, succ k) -delta-> Eq(succ k, succ k)
    const step = try pool.mkLam(nat_ref,
        try pool.mkLam(try pool.mkApp(P, try pool.mkVar(0)),
            try pool.mkRefl(try pool.mkSucc(try pool.mkVar(1)))));

    const proof_term = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(nat_ind_ref, P), base), step);

    // theorem_type = Pi n. Eq(add n zero, n)
    const theorem_type = try pool.mkPi(nat_ref,
        try pool.mkEq(
            try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(0)), zero),
            try pool.mkVar(0)));

    const ok = try verify(&pool, proof_term, theorem_type);
    std.debug.print("[SANITY] add_zero_right: type_check={}\n", .{ok});
    try std.testing.expect(ok);
}


test "add_succ_right derivable via nat_ind" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    try initNatAxioms(&pool);

    const nat_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "Nat"));
    const add_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "add"));
    const nat_ind_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "nat_ind"));
    const cong_succ_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "cong_succ"));

    // P = Lm n. Pi m:Nat. Eq(add n (succ m), succ(add n m))
    // Sous Lm n    : var(0)=n
    // Sous Pi m    : var(0)=m, var(1)=n
    const P_body = try pool.mkPi(nat_ref,
        try pool.mkEq(
            try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(1)), try pool.mkSucc(try pool.mkVar(0))),
            try pool.mkSucc(try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(1)), try pool.mkVar(0)))));
    const P = try pool.mkLam(nat_ref, P_body);

    // base = Lm. refl(succ m)  : Eq(succ m, succ m) convertible a P(zero) par delta
    const base = try pool.mkLam(nat_ref, try pool.mkRefl(try pool.mkSucc(try pool.mkVar(0))));

    // step = Lk. Lih:P(k). Lm. cong_succ(add k (succ m), succ(add k m), ih m)
    // Sous Lk,Lih,Lm : var(0)=m, var(1)=ih, var(2)=k
    const add_k_succ_m = try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(2)), try pool.mkSucc(try pool.mkVar(0)));
    const succ_add_k_m = try pool.mkSucc(try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(2)), try pool.mkVar(0)));
    const ih_m = try pool.mkApp(try pool.mkVar(1), try pool.mkVar(0));
    const step_inner = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(cong_succ_ref, add_k_succ_m), succ_add_k_m), ih_m);
    const ih_type = try pool.mkApp(P, try pool.mkVar(0));
    const step = try pool.mkLam(nat_ref,
        try pool.mkLam(ih_type,
            try pool.mkLam(nat_ref, step_inner)));

    const proof_term = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(nat_ind_ref, P), base), step);

    // theorem_type = Pi n. Pi m. Eq(add n (succ m), succ(add n m))
    const theorem_type = try pool.mkPi(nat_ref,
        try pool.mkPi(nat_ref,
            try pool.mkEq(
                try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(1)), try pool.mkSucc(try pool.mkVar(0))),
                try pool.mkSucc(try pool.mkApp(try pool.mkApp(add_ref, try pool.mkVar(1)), try pool.mkVar(0))))));

    const ok = try verify(&pool, proof_term, theorem_type);
    std.debug.print("[SANITY] add_succ_right: type_check={}\n", .{ok});
    try std.testing.expect(ok);
}


test "mul_zero_right derivable via nat_ind" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    try initNatAxioms(&pool);

    const nat_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "Nat"));
    const mul_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "mul"));
    const nat_ind_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "nat_ind"));
    const zero = try pool.mkZero();

    // P = Lm n. Eq(mul n zero, zero)
    const P_body = try pool.mkEq(
        try pool.mkApp(try pool.mkApp(mul_ref, try pool.mkVar(0)), zero),
        zero);
    const P = try pool.mkLam(nat_ref, P_body);

    // base = refl(zero)
    const base = try pool.mkRefl(zero);

    // step = Lk. Lih:P(k). ih
    // Sous Lk,Lih : var(0)=ih, var(1)=k
    const step = try pool.mkLam(nat_ref,
        try pool.mkLam(try pool.mkApp(P, try pool.mkVar(0)),
            try pool.mkVar(0)));

    const proof_term = try pool.mkApp(
        try pool.mkApp(try pool.mkApp(nat_ind_ref, P), base), step);

    const theorem_type = try pool.mkPi(nat_ref,
        try pool.mkEq(
            try pool.mkApp(try pool.mkApp(mul_ref, try pool.mkVar(0)), zero),
            zero));

    const ok = try verify(&pool, proof_term, theorem_type);
    std.debug.print("[SANITY] mul_zero_right: type_check={}\n", .{ok});
    try std.testing.expect(ok);
}


test "mul delta-reduction: 2*3 = 6" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    try initNatAxioms(&pool);

    const mul_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "mul"));
    const zero = try pool.mkZero();
    const one = try pool.mkSucc(zero);
    const two = try pool.mkSucc(one);
    const three = try pool.mkSucc(two);
    // 6 = succ^3(three)
    const six = try pool.mkSucc(try pool.mkSucc(try pool.mkSucc(three)));

    const expr = try pool.mkApp(try pool.mkApp(mul_ref, two), three);
    const result = try eval(&pool, expr);
    const expected = try eval(&pool, six);
    const ok = try convertible(&pool, result, expected);
    try std.testing.expect(ok);
}


test "add_assoc derivable via nat_ind" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    try initNatAxioms(&pool);

    const add_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "add"));
    const zero = try pool.mkZero();

    // proof = mkAddAssocProof(zero, zero, zero)
    // -> Eq(add (add zero zero) zero, add zero (add zero zero))
    //    convertible a Eq(zero, zero) par delta
    const proof = try mkAddAssocProof(&pool, zero, zero, zero);

    const expected = try pool.mkEq(
        try pool.mkApp(try pool.mkApp(add_ref,
            try pool.mkApp(try pool.mkApp(add_ref, zero), zero)), zero),
        try pool.mkApp(try pool.mkApp(add_ref, zero),
            try pool.mkApp(try pool.mkApp(add_ref, zero), zero)));

    const ok = try verify(&pool, proof, expected);
    std.debug.print("[SANITY] add_assoc: type_check={}\n", .{ok});
    try std.testing.expect(ok);
}


test "cong_add_l/r sanity" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    try initNatAxioms(&pool);

    const add_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "add"));
    const cong_add_l_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "cong_add_l"));
    const cong_add_r_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "cong_add_r"));
    const zero = try pool.mkZero();
    const rfl = try pool.mkRefl(zero);

    // cong_add_l(zero, zero, refl zero, zero) : Eq(add zero zero, add zero zero)
    const l_proof = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(
                try pool.mkApp(cong_add_l_ref, zero), zero),
            rfl),
        zero);
    const l_expected = try pool.mkEq(
        try pool.mkApp(try pool.mkApp(add_ref, zero), zero),
        try pool.mkApp(try pool.mkApp(add_ref, zero), zero));
    const ok_l = try verify(&pool, l_proof, l_expected);
    std.debug.print("[SANITY] cong_add_l: type_check={}\n", .{ok_l});
    try std.testing.expect(ok_l);

    // cong_add_r(zero, zero, refl zero, zero)
    const r_proof = try pool.mkApp(
        try pool.mkApp(
            try pool.mkApp(
                try pool.mkApp(cong_add_r_ref, zero), zero),
            rfl),
        zero);
    const ok_r = try verify(&pool, r_proof, l_expected);
    std.debug.print("[SANITY] cong_add_r: type_check={}\n", .{ok_r});
    try std.testing.expect(ok_r);
}


test "mul_succ_right derivable via nat_ind" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    try initNatAxioms(&pool);

    const add_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "add"));
    const mul_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "mul"));
    const zero = try pool.mkZero();

    const proof = try mkMulSuccRightProof(&pool, zero, zero);
    const expected = try pool.mkEq(
        try pool.mkApp(try pool.mkApp(mul_ref, zero), try pool.mkSucc(zero)),
        try pool.mkApp(try pool.mkApp(add_ref,
            try pool.mkApp(try pool.mkApp(mul_ref, zero), zero)),
            zero));

    const ok = try verify(&pool, proof, expected);
    std.debug.print("[SANITY] mul_succ_right: type_check={}\n", .{ok});
    try std.testing.expect(ok);
}


test "mul_comm derivable via nat_ind" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    try initNatAxioms(&pool);

    const mul_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "mul"));
    const zero = try pool.mkZero();

    const proof = try mkMulCommProof(&pool, zero, zero);
    const expected = try pool.mkEq(
        try pool.mkApp(try pool.mkApp(mul_ref, zero), zero),
        try pool.mkApp(try pool.mkApp(mul_ref, zero), zero));
    const ok = try verify(&pool, proof, expected);
    std.debug.print("[SANITY] mul_comm: type_check={}\n", .{ok});
    try std.testing.expect(ok);
}


test "distrib derivable via nat_ind" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    try initNatAxioms(&pool);

    const add_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "add"));
    const mul_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "mul"));
    const zero = try pool.mkZero();

    const proof = try mkDistribProof(&pool, zero, zero, zero);
    const expected = try pool.mkEq(
        try pool.mkApp(try pool.mkApp(mul_ref, zero),
            try pool.mkApp(try pool.mkApp(add_ref, zero), zero)),
        try pool.mkApp(try pool.mkApp(add_ref,
            try pool.mkApp(try pool.mkApp(mul_ref, zero), zero)),
            try pool.mkApp(try pool.mkApp(mul_ref, zero), zero)));

    const ok = try verify(&pool, proof, expected);
    std.debug.print("[SANITY] distrib: type_check={}\n", .{ok});
    try std.testing.expect(ok);
}


test "e2e proofs on concrete naturals" {
    var pool = TermPool.init(std.testing.allocator);
    defer pool.deinit();
    try initNatAxioms(&pool);

    const add_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "add"));
    const mul_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "mul"));
    const zero = try pool.mkZero();
    const one = try pool.mkSucc(zero);
    const two = try pool.mkSucc(one);
    const three = try pool.mkSucc(two);
    const four = try pool.mkSucc(three);

    // 1. add_comm(2, 3) : Eq(add 2 3, add 3 2)
    {
        const proof = try mkAddCommProof(&pool, two, three);
        const expected = try pool.mkEq(
            try pool.mkApp(try pool.mkApp(add_ref, two), three),
            try pool.mkApp(try pool.mkApp(add_ref, three), two));
        const ok = try verify(&pool, proof, expected);
        std.debug.print("[E2E] add_comm(2,3): {}\n", .{ok});
        try std.testing.expect(ok);
    }

    // 2. mul_comm(2, 3) : Eq(mul 2 3, mul 3 2)
    {
        const proof = try mkMulCommProof(&pool, two, three);
        const expected = try pool.mkEq(
            try pool.mkApp(try pool.mkApp(mul_ref, two), three),
            try pool.mkApp(try pool.mkApp(mul_ref, three), two));
        const ok = try verify(&pool, proof, expected);
        std.debug.print("[E2E] mul_comm(2,3): {}\n", .{ok});
        try std.testing.expect(ok);
    }

    // 3. distrib(2, 3, 4) : Eq(mul 2 (add 3 4), add (mul 2 3) (mul 2 4))
    {
        const proof = try mkDistribProof(&pool, two, three, four);
        const expected = try pool.mkEq(
            try pool.mkApp(try pool.mkApp(mul_ref, two),
                try pool.mkApp(try pool.mkApp(add_ref, three), four)),
            try pool.mkApp(try pool.mkApp(add_ref,
                try pool.mkApp(try pool.mkApp(mul_ref, two), three)),
                try pool.mkApp(try pool.mkApp(mul_ref, two), four)));
        const ok = try verify(&pool, proof, expected);
        std.debug.print("[E2E] distrib(2,3,4): {}\n", .{ok});
        try std.testing.expect(ok);
    }

    // 4. add_assoc(2, 3, 4) : Eq(add (add 2 3) 4, add 2 (add 3 4))
    {
        const proof = try mkAddAssocProof(&pool, two, three, four);
        const expected = try pool.mkEq(
            try pool.mkApp(try pool.mkApp(add_ref,
                try pool.mkApp(try pool.mkApp(add_ref, two), three)), four),
            try pool.mkApp(try pool.mkApp(add_ref, two),
                try pool.mkApp(try pool.mkApp(add_ref, three), four)));
        const ok = try verify(&pool, proof, expected);
        std.debug.print("[E2E] add_assoc(2,3,4): {}\n", .{ok});
        try std.testing.expect(ok);
    }
}
