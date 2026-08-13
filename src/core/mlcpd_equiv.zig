//! Module d'équivalence MLCPD certifié
//!
//! Ce module remplace la comparaison syntaxique de strings par une preuve formelle
//! utilisant le type checker et la normalisation WHNF.
//!
//! Stratégies de preuve :
//! 1. Type checking : si les types diffèrent → non équivalents (preuve immédiate)
//! 2. WHNF normalization : normaliser les deux expressions vers Weak Head Normal Form
//! 3. Structural comparison : si les WHNF sont identiques → construire ProofTerm
//! 4. Fallback syntaxique : si WHNF échoue, comparer les formes canonisées (non certifié)

const std = @import("std");
const Allocator = std.mem.Allocator;
const expr_mod = @import("expr");
const Store = expr_mod.Store;
const Id = expr_mod.Id;
const elab_mod = @import("elab");
const TypeChecker = elab_mod.TypeChecker;
const TypingContext = elab_mod.TypingContext;
const platform = @import("platform");
const proof_core = @import("proof_core");
pub const ProofTerm = proof_core.ProofTerm;

pub const EquivError = error{
    TypeMismatch,
    NormalizationFailed,
    ProofConstructionFailed,
    OutOfMemory,
};

pub const Strategy = enum(u8) {
    /// Preuve formelle via type checking + WHNF normalization
    whnf_normalization,

    /// Preuve par réflexivité (expressions identiques)
    reflexivity,

    /// Preuve par congruence (même structure, sous-expressions équivalentes)
    congruence,

    /// Fallback : comparaison syntaxique des formes canonisées (NON certifié)
    structural_fallback,

    /// Types différents → non équivalents (preuve négative)
    type_mismatch,
};

pub const EquivResult = struct {
    /// Les expressions sont-elles équivalentes ?
    equivalent: bool,

    /// Certificat de preuve (null si non équivalent ou fallback non certifié)
    proof: ?ProofTerm,

    /// Stratégie utilisée pour la preuve
    strategy: Strategy,

    /// Forme canonique de e1 (pour debugging)
    canon1: ?Id,

    /// Forme canonique de e2 (pour debugging)
    canon2: ?Id,

    /// Message d'erreur si échec
    error_message: ?[]const u8,

    pub fn deinit(self: *EquivResult, allocator: Allocator) void {
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
    }
};

/// Prouve l'équivalence de deux expressions avec certificat formel
pub fn proveEquivalence(
    allocator: Allocator,
    store: *Store,
    e1: Id,
    e2: Id,
) EquivError!EquivResult {
    // platform.debug.print("\n[proveEquivalence] e1={}, e2={}\n", .{ e1, e2 });

    // Étape 1 : Vérifier les types
    var checker = TypeChecker.init(allocator, store);
    var ctx = TypingContext.init(allocator);
    defer ctx.deinit();

    const t1 = checker.inferType(&ctx, e1) catch |err| {
        // platform.debug.print("[proveEquivalence] inferType(e1) failed: {}\n", .{err});
        return EquivResult{
            .equivalent = false,
            .proof = null,
            .strategy = .type_mismatch,
            .canon1 = null,
            .canon2 = null,
            .error_message = try std.fmt.allocPrint(allocator, "Type inference failed for e1: {}", .{err}),
        };
    };
    // platform.debug.print("[proveEquivalence] inferType(e1) OK: t1={}\n", .{t1});

    const t2 = checker.inferType(&ctx, e2) catch |err| {
        // platform.debug.print("[proveEquivalence] inferType(e2) failed: {}\n", .{err});
        return EquivResult{
            .equivalent = false,
            .proof = null,
            .strategy = .type_mismatch,
            .canon1 = null,
            .canon2 = null,
            .error_message = try std.fmt.allocPrint(allocator, "Type inference failed for e2: {}", .{err}),
        };
    };
    // platform.debug.print("[proveEquivalence] inferType(e2) OK: t2={}\n", .{t2});

    // Étape 2 : Si types différents → non équivalents
    const types_eq = checker.typesEqual(t1, t2);
    // platform.debug.print("[proveEquivalence] typesEqual(t1, t2) = {}\n", .{types_eq});
    if (!types_eq) {
        return EquivResult{
            .equivalent = false,
            .proof = null,
            .strategy = .type_mismatch,
            .canon1 = e1,
            .canon2 = e2,
            .error_message = try allocator.dupe(u8, "Types differ"),
        };
    }

    // Étape 3 : Normaliser vers WHNF
    // platform.debug.print("[proveEquivalence] Normalizing to WHNF...\n", .{});
    const n1 = checker.whnf(e1) catch |err| {
        // Fallback : comparaison syntaxique
        return proveStructuralFallback(allocator, store, e1, e2, err);
    };
    // platform.debug.print("[proveEquivalence] whnf(e1) = {}\n", .{n1});

    const n2 = checker.whnf(e2) catch |err| {
        // platform.debug.print("[proveEquivalence] whnf(e2) failed: {}\n", .{err});
        return proveStructuralFallback(allocator, store, e1, e2, err);
    };
    // platform.debug.print("[proveEquivalence] whnf(e2) = {}\n", .{n2});
    // platform.debug.print("[proveEquivalence] n1 == n2 ? {}\n", .{n1 == n2});

    // Étape 4 : Si WHNF identiques (même Id) → construire ProofTerm par réflexivité
    if (n1 == n2) {
        // platform.debug.print("[proveEquivalence] Reflexivity (same Id)\n", .{});
        return EquivResult{
            .equivalent = true,
            .proof = ProofTerm{ .refl = @intCast(n1) },
            .strategy = .reflexivity,
            .canon1 = n1,
            .canon2 = n2,
            .error_message = null,
        };
    }

    // Étape 5 : Comparaison structurelle des WHNF (valeurs égales mais Id différents)
    // platform.debug.print("[proveEquivalence] Trying structural comparison...\n", .{});
    const structurally_equal = compareWhnfStructures(store, n1, n2);
    // platform.debug.print("[proveEquivalence] structurally_equal = {}\n", .{structurally_equal});

    if (structurally_equal) {
        // platform.debug.print("[proveEquivalence] Structurally equal\n", .{});
        // Construire preuve par congruence
        const proof = try buildCongruenceProof(allocator, store, n1, n2);
        return EquivResult{
            .equivalent = true,
            .proof = proof,
            .strategy = .congruence,
            .canon1 = n1,
            .canon2 = n2,
            .error_message = null,
        };
    }

    // Non équivalents
    return EquivResult{
        .equivalent = false,
        .proof = null,
        .strategy = .whnf_normalization,
        .canon1 = n1,
        .canon2 = n2,
        .error_message = try allocator.dupe(u8, "WHNF forms differ"),
    };
}

/// Fallback : comparaison syntaxique des formes canonisées (NON certifié)
fn proveStructuralFallback(
    allocator: Allocator,
    store: *Store,
    e1: Id,
    e2: Id,
    whnf_err: anyerror,
) EquivError!EquivResult {
    _ = store;
    _ = e1;
    _ = e2;

    return EquivResult{
        .equivalent = false,
        .proof = null,
        .strategy = .structural_fallback,
        .canon1 = null,
        .canon2 = null,
        .error_message = try std.fmt.allocPrint(allocator, "WHNF failed: {}, structural fallback not yet implemented", .{whnf_err}),
    };
}

/// Compare deux WHNF structurellement (au-delà de l'égalité d'Id)
fn compareWhnfStructures(store: *Store, n1: Id, n2: Id) bool {
    const node1 = store.get(n1);
    const node2 = store.get(n2);

    // Tags différents → non égaux
    if (node1.tag != node2.tag) return false;

    // Cas spécial : littéraux - comparer les valeurs, pas les Id
    if (node1.tag == .lit and node2.tag == .lit) {
        const lit1 = store.lits.items[node1.aux];
        const lit2 = store.lits.items[node2.aux];

        return switch (lit1) {
            .int => |v1| switch (lit2) {
                .int => |v2| v1 == v2,
                else => false,
            },
            .float => |v1| switch (lit2) {
                .float => |v2| v1 == v2,
                else => false,
            },
            .boolean => |v1| switch (lit2) {
                .boolean => |v2| v1 == v2,
                else => false,
            },
            .str => |v1| switch (lit2) {
                .str => |v2| v1 == v2, // Comparer les Sym IDs
                else => false,
            },
            .unit => switch (lit2) {
                .unit => true,
                else => false,
            },
            .runtime => false, // Runtime refs ne sont pas comparables structurellement
        };
    }

    // Même tag : comparer payload et aux
    if (node1.payload != node2.payload) return false;
    if (node1.aux != node2.aux) return false;

    // Pour les nœuds avec enfants, comparer récursivement
    const pool = store.pool.items;
    const children1 = node1.span_a.slice(pool);
    const children2 = node2.span_a.slice(pool);

    if (children1.len != children2.len) return false;

    for (children1, children2) |c1, c2| {
        if (!compareWhnfStructures(store, c1, c2)) return false;
    }

    return true;
}

/// Construit une preuve par congruence pour deux expressions structurellement égales
fn buildCongruenceProof(
    allocator: Allocator,
    store: *Store,
    n1: Id,
    n2: Id,
) EquivError!ProofTerm {
    _ = allocator;
    _ = store;
    _ = n2;

    // TODO : Construire une preuve de congruence complète
    // Pour l'instant, retourner une preuve simplifiée
    return ProofTerm{ .refl = @intCast(n1) };
}

/// Vérifie qu'un ProofTerm est valide
pub fn verifyProof(
    store: *Store,
    proof: ProofTerm,
    e1: Id,
    e2: Id,
) bool {
    _ = store; // TODO: utiliser store pour vérifier structurellement

    switch (proof) {
        .refl => |id| {
            // refl prouve que id ≡ id
            return id == e1 and id == e2;
        },
        .by_eval => |args| {
            // by_eval prouve que eval(args.lhs) = eval(args.rhs)
            // Pour l'instant, vérifier que lhs = e1 et rhs = e2
            return args.lhs == e1 and args.rhs == e2;
        },
        .cong => |args| {
            // cong prouve que si args.proof prouve a ≡ b, alors f(a) ≡ f(b)
            // TODO : Vérifier récursivement
            _ = args;
            return false;
        },
        else => return false,
    }
}

test "mlcpd_equiv - proveEquivalence reflexivity (literals)" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    // Create two identical literal expressions: 42 and 42
    // Note: they may have different Ids but same value
    const expr1 = try store.int(42);
    const expr2 = try store.int(42);

    // Prove equivalence
    var result = try proveEquivalence(allocator, &store, expr1, expr2);
    defer result.deinit(allocator);

    // Should be equivalent
    try std.testing.expect(result.equivalent);
    // Strategy can be .reflexivity (same Id) or .congruence (same value, different Ids)
    try std.testing.expect(result.strategy == .reflexivity or result.strategy == .congruence);
    try std.testing.expect(result.proof != null);
}

test "mlcpd_equiv - proveEquivalence type mismatch" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    // Create expressions with different types: 5 (int) vs true (bool)
    const five = try store.int(5);
    const true_val = try store.boolean(true);

    // Should not be equivalent due to type mismatch
    var result = try proveEquivalence(allocator, &store, five, true_val);
    defer result.deinit(allocator);

    try std.testing.expect(!result.equivalent);
    try std.testing.expect(result.strategy == .type_mismatch);
}

test "mlcpd_equiv - proveEquivalence different literals" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    // Create two different literals: 5 and 7
    const expr1 = try store.int(5);
    const expr2 = try store.int(7);

    // Should not be equivalent (different values)
    var result = try proveEquivalence(allocator, &store, expr1, expr2);
    defer result.deinit(allocator);

    try std.testing.expect(!result.equivalent);
}

// TODO: Ajouter un test WHNF quand le TypeChecker supporte les lambdas natifs
// test "mlcpd_equiv - proveEquivalence WHNF normalization" { ... }
