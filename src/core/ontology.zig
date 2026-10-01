//! Ontologie Heaven - niveau High-Level Semantic IR.
//!
//! Ce fichier est un squelette (Phase 2, 2026-10-01).
//! Il n'est pas encore branche dans build.zig ni importe par main.zig.
//! Il est testable isolement via : zig test src/core/ontology.zig
//!
//! Voir docs/spec/_ontology.md pour les decisions actees.

const std = @import("std");
const Allocator = std.mem.Allocator;

// =====================================================================
// Trust et provenance
// =====================================================================

/// Niveau de confiance d'un concept ou d'une relation.
///
/// - asserted : vient d'une source externe non verifiee
/// - derived  : derive par une regle interne valide (subsomption, etc.)
/// - certified: prouve par proof_core.zig
pub const TrustLevel = enum(u8) {
    asserted = 0,
    derived = 1,
    certified = 2,

    pub fn format(self: TrustLevel) []const u8 {
        return switch (self) {
            .asserted => "asserted",
            .derived => "derived",
            .certified => "certified",
        };
    }

    /// Retourne true si `self` est au moins aussi fiable que `other`.
    pub fn atLeast(self: TrustLevel, other: TrustLevel) bool {
        return @intFromEnum(self) >= @intFromEnum(other);
    }
};

/// Origine d'un concept ou d'une relation.
pub const SourceKind = enum(u8) {
    user,
    smt_lib,
    owl,
    lean,
    rocq,
    mpst,
    internal,

    pub fn format(self: SourceKind) []const u8 {
        return switch (self) {
            .user => "user",
            .smt_lib => "smt_lib",
            .owl => "owl",
            .lean => "lean",
            .rocq => "rocq",
            .mpst => "mpst",
            .internal => "internal",
        };
    }
};

/// Provenance d'un concept ou d'une relation.
///
/// `source_id` est optionnel : URI, nom de fichier, numero de ligne,
/// identifiant de regle. Libere par l'appelant si non null.
pub const Provenance = struct {
    source: SourceKind,
    source_id: ?[]const u8,
    timestamp: i64,

    pub fn now(source: SourceKind) Provenance {
        return .{
            .source = source,
            .source_id = null,
            .timestamp = std.time.timestamp(),
        };
    }
};

// =====================================================================
// Concept et Relation
// =====================================================================

/// Un concept de l'ontologie.
///
/// `name` est la cle d'affichage, `expr_id` l'identite semantique
/// (a terme un Id du Store). Pour l'instant `expr_id` est optionnel
/// et non verifie - la Phase 3 le branchera sur expr.Store.
///
/// `parent` est un nom de concept parent (subsomption simple).
/// Un DAG de parents viendra plus tard si besoin.
pub const Concept = struct {
    name: []const u8,
    parent: ?[]const u8,
    trust: TrustLevel,
    provenance: Provenance,
    expr_id: ?u32,
};

/// Type de relation entre concepts.
pub const RelationKind = enum {
    is_a,
    equivalent_to,
    produces,
    consumes,
    has_part,

    pub fn format(self: RelationKind) []const u8 {
        return switch (self) {
            .is_a => "is-a",
            .equivalent_to => "equivalent-to",
            .produces => "produces",
            .consumes => "consumes",
            .has_part => "has-part",
        };
    }
};

/// Une relation entre deux concepts, identifiee par leurs noms.
pub const Relation = struct {
    kind: RelationKind,
    from: []const u8,
    to: []const u8,
    trust: TrustLevel,
    provenance: Provenance,
};

// =====================================================================
// Ontology
// =====================================================================

pub const OntologyError = Allocator.Error || error{
    UnknownConcept,
    DuplicateConcept,
};

pub const Ontology = struct {
    allocator: Allocator,
    concepts: std.StringHashMapUnmanaged(Concept),
    relations: std.ArrayListUnmanaged(Relation),

    pub fn init(allocator: Allocator) Ontology {
        return .{
            .allocator = allocator,
            .concepts = .{},
            .relations = .{},
        };
    }

    pub fn deinit(self: *Ontology) void {
        // Les cles de `concepts` sont la propriete exclusive de la map.
        // Concept.name est un alias de la cle : ne PAS le liberer
        // separement. On libere la cle, puis le parent (dupe distinct).
        var it = self.concepts.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            if (entry.value_ptr.parent) |p| self.allocator.free(p);
        }
        self.concepts.deinit(self.allocator);
        self.relations.deinit(self.allocator);
    }

    /// Ajoute un concept. Retourne DuplicateConcept si le nom existe deja.
    /// Le nom est duplique ; il appartient a l'ontologie apres l'appel.
    pub fn addConcept(
        self: *Ontology,
        name: []const u8,
        parent: ?[]const u8,
        trust: TrustLevel,
        provenance: Provenance,
    ) OntologyError!void {
        if (self.concepts.contains(name)) return error.DuplicateConcept;

        const name_dupe = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_dupe);

        const parent_dupe = if (parent) |p| try self.allocator.dupe(u8, p) else null;
        errdefer if (parent_dupe) |p| self.allocator.free(p);

        try self.concepts.put(self.allocator, name_dupe, .{
            .name = name_dupe,
            .parent = parent_dupe,
            .trust = trust,
            .provenance = provenance,
            .expr_id = null,
        });
    }

    /// Ajoute une relation. Ne verifie pas que from/to existent :
    /// les relations peuvent etre declarees avant leurs concepts.
    pub fn addRelation(
        self: *Ontology,
        kind: RelationKind,
        from: []const u8,
        to: []const u8,
        trust: TrustLevel,
        provenance: Provenance,
    ) OntologyError!void {
        try self.relations.append(self.allocator, .{
            .kind = kind,
            .from = from,
            .to = to,
            .trust = trust,
            .provenance = provenance,
        });
    }

    /// Retourne true si `child` est un descendant de `ancestor`
    /// via la chaine de parents. Reflexif : isA(x, x) est vrai.
    pub fn isA(self: *const Ontology, child: []const u8, ancestor: []const u8) bool {
        if (std.mem.eql(u8, child, ancestor)) return true;
        const c = self.concepts.get(child) orelse return false;
        if (c.parent) |p| return self.isA(p, ancestor);
        return false;
    }

    /// Retourne le nombre de concepts dont le trust est au moins `min`.
    pub fn countAtLeast(self: *const Ontology, min: TrustLevel) usize {
        var n: usize = 0;
        var it = self.concepts.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.trust.atLeast(min)) n += 1;
        }
        return n;
    }

    /// Cherche un concept par nom.
    pub fn get(self: *const Ontology, name: []const u8) ?Concept {
        return self.concepts.get(name);
    }
};

// =====================================================================
// Tests
// =====================================================================

test "ontology: add concept, isA reflexive and transitive" {
    var ont = Ontology.init(std.testing.allocator);
    defer ont.deinit();

    const prov = Provenance.now(.internal);

    try ont.addConcept("Computation", null, .certified, prov);
    try ont.addConcept("Arithmetic", "Computation", .certified, prov);
    try ont.addConcept("Factorial", "Arithmetic", .derived, prov);

    try std.testing.expect(ont.isA("Arithmetic", "Arithmetic"));
    try std.testing.expect(ont.isA("Arithmetic", "Computation"));
    try std.testing.expect(ont.isA("Factorial", "Computation"));
    try std.testing.expect(!ont.isA("Computation", "Arithmetic"));
    try std.testing.expect(!ont.isA("Inconnu", "Computation"));
}

test "ontology: duplicate concept rejected" {
    var ont = Ontology.init(std.testing.allocator);
    defer ont.deinit();

    const prov = Provenance.now(.user);
    try ont.addConcept("Foo", null, .asserted, prov);

    const result = ont.addConcept("Foo", null, .asserted, prov);
    try std.testing.expectError(error.DuplicateConcept, result);
}

test "ontology: trust filtering" {
    var ont = Ontology.init(std.testing.allocator);
    defer ont.deinit();

    try ont.addConcept("A", null, .asserted, Provenance.now(.user));
    try ont.addConcept("B", null, .derived, Provenance.now(.internal));
    try ont.addConcept("C", null, .certified, Provenance.now(.internal));
    try ont.addConcept("D", null, .certified, Provenance.now(.internal));

    try std.testing.expectEqual(@as(usize, 4), ont.countAtLeast(.asserted));
    try std.testing.expectEqual(@as(usize, 3), ont.countAtLeast(.derived));
    try std.testing.expectEqual(@as(usize, 2), ont.countAtLeast(.certified));
}
