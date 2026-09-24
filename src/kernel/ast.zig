const std = @import("std");

pub const UniverseLevel = union(enum) {
    concrete: u32,
    max: struct {
        a: *const UniverseLevel,
        b: *const UniverseLevel,
    },

    pub fn getConcrete(self: UniverseLevel) ?u32 {
        return switch (self) {
            .concrete => |c| c,
            .max => |m| if (m.a.getConcrete()) |c1|
                if (m.b.getConcrete()) |c2| @max(c1, c2) else null
            else
                null,
        };
    }

    pub fn maxWith(self: UniverseLevel, other: UniverseLevel, allocator: std.mem.Allocator) !UniverseLevel {
        if (self.getConcrete()) |c1| {
            if (other.getConcrete()) |c2| {
                return UniverseLevel{ .concrete = @max(c1, c2) };
            }
        }
        const a_ptr = try allocator.create(UniverseLevel);
        const b_ptr = try allocator.create(UniverseLevel);
        a_ptr.* = self;
        b_ptr.* = other;
        return UniverseLevel{ .max = .{ .a = a_ptr, .b = b_ptr } };
    }
};

pub const Sort = union(enum) {
    prop,
    type_sort: UniverseLevel,
};

pub const Term = union(enum) {
    sort: Sort,
    variable: usize, // Index de De Bruijn
    pi: struct {
        name: []const u8,
        domain: *const Term,
        codomain: *const Term,
    },
    lambda: struct {
        name: []const u8,
        domain: *const Term,
        body: *const Term,
    },
    app: struct {
        func: *const Term,
        arg: *const Term,
    },
    // Primitive Types Quotients
    quot: struct {
        type_a: *const Term,
        relation_r: *const Term, // R : A -> A -> Prop
    },
    class: struct {
        quot_type: *const Term, // Quot(A, R)
        element: *const Term, // x : A
    },
    lift: struct {
        quot_type: *const Term, // Quot(A, R)
        target_b: *const Term, // Type d'arrivée B
        func_f: *const Term, // f : A -> B
        proof: *const Term, // Preuve que f resp. R
    },
    // ─── Égalité intensionnelle ───
    // Γ ⊢ A : Sort u   Γ ⊢ a : A   Γ ⊢ b : A
    // ────────────────────────────────────────
    // Γ ⊢ Eq A a b : Prop
    eq: struct {
        type_a: *const Term,
        lhs: *const Term,
        rhs: *const Term,
    },
    // Γ ⊢ A : Sort u   Γ ⊢ a : A
    // ────────────────────────────
    // Γ ⊢ refl A a : Eq A a a
    refl: struct {
        type_a: *const Term,
        element: *const Term,
    },
};

// ═══════════════════════════════════════════════════════════
// Égalité structurelle (pas de β/ι — c'est la "version minimale",
// à remplacer par la conversion kernel une fois branchée).
//
// NOTE : les noms des binders (pi/lambda) ne participent PAS à
// l'égalité — ce sont des annotations, les indices sont De Bruijn.
// (λx. x) et (λy. y) sont α-équivalents. Ne pas "corriger" ça
// en comparant les noms : ça casserait l'α-équivalence.
// ═══════════════════════════════════════════════════════════
pub fn termsStructurallyEqual(a: Term, b: Term) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .sort => |s| sortsEqual(s, b.sort),
        .variable => |v| v == b.variable,
        .pi => |p| termsStructurallyEqual(p.domain.*, b.pi.domain.*) and
            termsStructurallyEqual(p.codomain.*, b.pi.codomain.*),
        .lambda => |l| termsStructurallyEqual(l.domain.*, b.lambda.domain.*) and
            termsStructurallyEqual(l.body.*, b.lambda.body.*),
        .app => |ap| termsStructurallyEqual(ap.func.*, b.app.func.*) and
            termsStructurallyEqual(ap.arg.*, b.app.arg.*),
        .quot => |q| termsStructurallyEqual(q.type_a.*, b.quot.type_a.*) and
            termsStructurallyEqual(q.relation_r.*, b.quot.relation_r.*),
        .class => |c| termsStructurallyEqual(c.quot_type.*, b.class.quot_type.*) and
            termsStructurallyEqual(c.element.*, b.class.element.*),
        .lift => |l| termsStructurallyEqual(l.quot_type.*, b.lift.quot_type.*) and
            termsStructurallyEqual(l.target_b.*, b.lift.target_b.*) and
            termsStructurallyEqual(l.func_f.*, b.lift.func_f.*) and
            termsStructurallyEqual(l.proof.*, b.lift.proof.*),
        .eq => |e| termsStructurallyEqual(e.type_a.*, b.eq.type_a.*) and
            termsStructurallyEqual(e.lhs.*, b.eq.lhs.*) and
            termsStructurallyEqual(e.rhs.*, b.eq.rhs.*),
        .refl => |r| termsStructurallyEqual(r.type_a.*, b.refl.type_a.*) and
            termsStructurallyEqual(r.element.*, b.refl.element.*),
    };
}

fn sortsEqual(a: Sort, b: Sort) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .prop => true,
        .type_sort => |l| universeLevelsEqual(l, b.type_sort),
    };
}

fn universeLevelsEqual(a: UniverseLevel, b: UniverseLevel) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .concrete => |c| c == b.concrete,
        .max => |m| universeLevelsEqual(m.a.*, b.max.a.*) and
            universeLevelsEqual(m.b.*, b.max.b.*),
    };
}
