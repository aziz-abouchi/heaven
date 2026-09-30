//! Profile : artefact de mesure (docs/spec/_metrics.md).
//!
//! Un Profile est un terme (hashable, comparable, stockable). Il
//! regroupe un ensemble fixe de métriques, chacune typée par son
//! kind (WallTime, CpuTime, Rss, ...) et sa précision runtime
//! (measured | estimated | unavailable via precision.Metric).
//!
//! Design V1 : structure avec 7 champs typés. La précision est
//! runtime par champ (Metric(T) = union measured/estimated/
//! unavailable). Une V2 pourra ajouter des accesseurs compile-time
//! sur la precision minimale.

const std = @import("std");
const precision_mod = @import("precision.zig");

pub const Precision = precision_mod.Precision;
pub const Metric = precision_mod.Metric;

/// Identifiant stable d'un Profile. Content-addressed : deux profils
/// avec les mêmes métriques ont le même id.
pub const ProfileId = u64;

/// Portée du profil. Utilisé pour distinguer mesures locales et
/// distantes.
pub const ScopeKind = enum {
    local,
    remote,
    nested,  // profil imbriqué dans un autre
};

pub const Profile = struct {
    id: ProfileId = 0,
    parent: ?ProfileId = null,
    scope: ScopeKind = .local,

    wall_time: Metric(u64) = .unavailable,
    cpu_time: Metric(u64) = .unavailable,
    rss: Metric(u64) = .unavailable,
    peak_rss: Metric(u64) = .unavailable,
    energy: Metric(f64) = .unavailable,
    instructions: Metric(u64) = .unavailable,
    allocations: Metric(u64) = .unavailable,

    const Self = @This();

    /// Cree un profil vide.
    pub fn empty() Self {
        return .{};
    }

    /// Calcule et stocke l'id. Doit etre appele apres avoir rempli
    /// les metriques. Deux profils avec les memes champs ont le meme
    /// id (content-addressed).
    pub fn computeId(self: *Self) ProfileId {
        var hasher = std.hash.Wyhash.init(0);
        hashField(&hasher, "wall_time", self.wall_time);
        hashField(&hasher, "cpu_time", self.cpu_time);
        hashField(&hasher, "rss", self.rss);
        hashField(&hasher, "peak_rss", self.peak_rss);
        hashField(&hasher, "energy", self.energy);
        hashField(&hasher, "instructions", self.instructions);
        hashField(&hasher, "allocations", self.allocations);
        if (self.parent) |p| {
            hasher.update(std.mem.asBytes(&p));
        }
        hasher.update(std.mem.asBytes(&self.scope));
        self.id = hasher.final();
        return self.id;
    }

    /// Nombre de metriques disponibles (mesurees ou estimees).
    pub fn availableCount(self: Self) u8 {
        var n: u8 = 0;
        if (self.wall_time.isAvailable()) n += 1;
        if (self.cpu_time.isAvailable()) n += 1;
        if (self.rss.isAvailable()) n += 1;
        if (self.peak_rss.isAvailable()) n += 1;
        if (self.energy.isAvailable()) n += 1;
        if (self.instructions.isAvailable()) n += 1;
        if (self.allocations.isAvailable()) n += 1;
        return n;
    }
};

/// Hash un champ Metric(T) : tag + valeur (si disponible).
fn hashField(hasher: *std.hash.Wyhash, name: []const u8, m: anytype) void {
    hasher.update(name);
    switch (m) {
        .measured => |v| {
            hasher.update(&[_]u8{1});
            hasher.update(std.mem.asBytes(&v));
        },
        .estimated => |v| {
            hasher.update(&[_]u8{2});
            hasher.update(std.mem.asBytes(&v));
        },
        .unavailable => {
            hasher.update(&[_]u8{3});
        },
    }
}

// ─────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────

test "Profile : empty a tous les champs unavailable" {
    const p = Profile.empty();
    try std.testing.expectEqual(@as(u8, 0), p.availableCount());
    try std.testing.expect(!p.wall_time.isAvailable());
    try std.testing.expect(!p.energy.isAvailable());
}

test "Profile : availableCount compte les champs disponibles" {
    var p = Profile.empty();
    p.wall_time = .{ .measured = 1234 };
    p.rss = .{ .measured = 4096 };
    p.energy = .{ .estimated = 42.5 };
    try std.testing.expectEqual(@as(u8, 3), p.availableCount());
}

test "Profile : computeId est deterministe" {
    var p1 = Profile.empty();
    p1.wall_time = .{ .measured = 1000 };
    p1.rss = .{ .measured = 4096 };
    _ = p1.computeId();

    var p2 = Profile.empty();
    p2.wall_time = .{ .measured = 1000 };
    p2.rss = .{ .measured = 4096 };
    _ = p2.computeId();

    try std.testing.expectEqual(p1.id, p2.id);
}

test "Profile : computeId differe si une metrique differe" {
    var p1 = Profile.empty();
    p1.wall_time = .{ .measured = 1000 };
    _ = p1.computeId();

    var p2 = Profile.empty();
    p2.wall_time = .{ .measured = 2000 };
    _ = p2.computeId();

    try std.testing.expect(p1.id != p2.id);
}

test "Profile : computeId differe si la precision differe" {
    var p1 = Profile.empty();
    p1.energy = .{ .measured = 42.5 };
    _ = p1.computeId();

    var p2 = Profile.empty();
    p2.energy = .{ .estimated = 42.5 };
    _ = p2.computeId();

    // Meme valeur, precision differente -> id different
    try std.testing.expect(p1.id != p2.id);
}

test "Profile : computeId tient compte du parent et du scope" {
    var p1 = Profile.empty();
    p1.parent = 1234;
    p1.scope = .nested;
    _ = p1.computeId();

    var p2 = Profile.empty();
    p2.parent = 1234;
    p2.scope = .local;
    _ = p2.computeId();

    try std.testing.expect(p1.id != p2.id);
}

test "Profile : energy en f64" {
    var p = Profile.empty();
    p.energy = .{ .measured = 42.5 };
    try std.testing.expectEqual(@as(f64, 42.5), p.energy.valueOrNull().?);
}

// ─────────────────────────────────────────────────────────────
// ProfileDiff : comparaison structuree de deux profils
// ─────────────────────────────────────────────────────────────

/// Statut d'un champ dans un diff.
pub const FieldStatus = enum {
    /// Present dans les deux, meme precision, meme valeur.
    identical,
    /// Present dans les deux, meme precision, valeurs differentes.
    changed,
    /// Present dans les deux, precision differente (ex: measured vs
    /// estimated). La comparaison numerique est alors ambigue.
    precision_changed,
    /// Present dans p1, absent dans p2.
    only_in_left,
    /// Absent dans p1, present dans p2.
    only_in_right,
    /// Absent dans les deux.
    absent_both,

    pub fn isComparable(self: FieldStatus) bool {
        return switch (self) {
            // Rien a comparer : les deux profils sont muets sur ce champ.
            .absent_both => true,
            // Comparaison numerique possible.
            .identical, .changed => true,
            // Ambigu ou asymetrique.
            .precision_changed, .only_in_left, .only_in_right => false,
        };
    }
};

/// Resultat d'un diff : un statut par champ.
pub const ProfileDiff = struct {
    wall_time: FieldStatus,
    cpu_time: FieldStatus,
    rss: FieldStatus,
    peak_rss: FieldStatus,
    energy: FieldStatus,
    instructions: FieldStatus,
    allocations: FieldStatus,

    const Self = @This();

    /// Deux profils sont numeriquement comparables si tous leurs
    /// champs differents ont la meme precision.
    pub fn isFullyComparable(self: Self) bool {
        return self.field_statuses().allComparable();
    }

    pub fn field_statuses(self: Self) FieldStatuses {
        return .{
            .wall_time = self.wall_time,
            .cpu_time = self.cpu_time,
            .rss = self.rss,
            .peak_rss = self.peak_rss,
            .energy = self.energy,
            .instructions = self.instructions,
            .allocations = self.allocations,
        };
    }
};

pub const FieldStatuses = struct {
    wall_time: FieldStatus,
    cpu_time: FieldStatus,
    rss: FieldStatus,
    peak_rss: FieldStatus,
    energy: FieldStatus,
    instructions: FieldStatus,
    allocations: FieldStatus,

    pub fn allComparable(self: @This()) bool {
        return self.wall_time.isComparable()
            and self.cpu_time.isComparable()
            and self.rss.isComparable()
            and self.peak_rss.isComparable()
            and self.energy.isComparable()
            and self.instructions.isComparable()
            and self.allocations.isComparable();
    }
};

pub fn diff(p1: Profile, p2: Profile) ProfileDiff {
    return .{
        .wall_time = fieldDiff(u64, p1.wall_time, p2.wall_time),
        .cpu_time = fieldDiff(u64, p1.cpu_time, p2.cpu_time),
        .rss = fieldDiff(u64, p1.rss, p2.rss),
        .peak_rss = fieldDiff(u64, p1.peak_rss, p2.peak_rss),
        .energy = fieldDiff(f64, p1.energy, p2.energy),
        .instructions = fieldDiff(u64, p1.instructions, p2.instructions),
        .allocations = fieldDiff(u64, p1.allocations, p2.allocations),
    };
}

fn fieldDiff(comptime T: type, m1: Metric(T), m2: Metric(T)) FieldStatus {
    const a1 = m1.isAvailable();
    const a2 = m2.isAvailable();
    if (!a1 and !a2) return .absent_both;
    if (a1 and !a2) return .only_in_left;
    if (!a1 and a2) return .only_in_right;
    if (m1.precision() != m2.precision()) return .precision_changed;
    // Memes precisions : comparer valeurs.
    const v1 = m1.valueOrNull().?;
    const v2 = m2.valueOrNull().?;
    if (v1 == v2) return .identical;
    return .changed;
}

// ─────────────────────────────────────────────────────────────
// Tests ProfileDiff
// ─────────────────────────────────────────────────────────────

test "diff : deux profils vides -> absent_both partout" {
    const p1 = Profile.empty();
    const p2 = Profile.empty();
    const d = diff(p1, p2);
    try std.testing.expectEqual(FieldStatus.absent_both, d.wall_time);
    try std.testing.expectEqual(FieldStatus.absent_both, d.energy);
}

test "diff : memes valeurs -> identical" {
    var p1 = Profile.empty();
    var p2 = Profile.empty();
    p1.wall_time = .{ .measured = 1000 };
    p2.wall_time = .{ .measured = 1000 };
    const d = diff(p1, p2);
    try std.testing.expectEqual(FieldStatus.identical, d.wall_time);
}

test "diff : valeurs differentes -> changed" {
    var p1 = Profile.empty();
    var p2 = Profile.empty();
    p1.rss = .{ .measured = 4096 };
    p2.rss = .{ .measured = 8192 };
    const d = diff(p1, p2);
    try std.testing.expectEqual(FieldStatus.changed, d.rss);
}

test "diff : precisions differentes -> precision_changed" {
    var p1 = Profile.empty();
    var p2 = Profile.empty();
    p1.energy = .{ .measured = 42.5 };
    p2.energy = .{ .estimated = 42.5 };
    const d = diff(p1, p2);
    // Meme valeur, precision differente
    try std.testing.expectEqual(FieldStatus.precision_changed, d.energy);
}

test "diff : disponible d'un cote seulement" {
    var p1 = Profile.empty();
    const p2 = Profile.empty();
    p1.instructions = .{ .measured = 1000 };
    const d = diff(p1, p2);
    try std.testing.expectEqual(FieldStatus.only_in_left, d.instructions);
    // Inverse
    const d2 = diff(p2, p1);
    try std.testing.expectEqual(FieldStatus.only_in_right, d2.instructions);
}

test "diff : isFullyComparable sur champs comparables" {
    var p1 = Profile.empty();
    var p2 = Profile.empty();
    p1.wall_time = .{ .measured = 1000 };
    p2.wall_time = .{ .measured = 2000 };
    p1.rss = .{ .measured = 4096 };
    p2.rss = .{ .measured = 4096 };
    const d = diff(p1, p2);
    try std.testing.expect(d.isFullyComparable());
}

test "diff : isFullyComparable=false si precision change" {
    var p1 = Profile.empty();
    var p2 = Profile.empty();
    p1.energy = .{ .measured = 42.5 };
    p2.energy = .{ .estimated = 42.5 };
    const d = diff(p1, p2);
    try std.testing.expect(!d.isFullyComparable());
}

test "diff : isFullyComparable=true si champs absents des deux" {
    var p1 = Profile.empty();
    var p2 = Profile.empty();
    p1.wall_time = .{ .measured = 1000 };
    p2.wall_time = .{ .measured = 2000 };
    const d = diff(p1, p2);
    // energy absent des deux -> absent_both -> comparable
    try std.testing.expect(d.isFullyComparable());
}

// ─────────────────────────────────────────────────────────────
// Politiques d'acces par precision (validation P3)
// ─────────────────────────────────────────────────────────────
//
// P3 de _platform.md : le compilateur refuse les usages implicites
// d'une precision insuffisante. Dans un langage dynamique comme
// Zig, on ne peut pas empecher un caller de lire un champ
// estimated -- mais on peut lui FORCER a choisir une politique
// explicite pour chaque niveau de precision.

/// Resultat d'une lecture avec fallback.
pub fn Reading(comptime T: type) type {
    return struct {
        value: ?T,
        /// Vrai si la valeur provient d'une estimation, pas d'une
        /// mesure. Un caller qui traite le resultat doit decider
        /// quoi faire de ce flag.
        estimated: bool,

        pub fn hasValue(self: @This()) bool {
            return self.value != null;
        }

        pub fn isMeasured(self: @This()) bool {
            return self.value != null and !self.estimated;
        }
    };
}

/// Exige une mesure. Retourne null si le champ est estime ou
/// indisponible. A utiliser quand une valeur fausse est pire que
/// pas de valeur (benchmark, optimisation energetique).
pub fn requireMeasuredEnergy(p: Profile) ?f64 {
    return switch (p.energy) {
        .measured => |v| v,
        else => null,
    };
}

/// Politique de fallback : accepte une estimation, signale le fait.
/// A utiliser quand une valeur approximative est utile mais doit
/// etre annotee.
pub fn energyWithFallback(p: Profile) Reading(f64) {
    return switch (p.energy) {
        .measured => |v| .{ .value = v, .estimated = false },
        .estimated => |v| .{ .value = v, .estimated = true },
        .unavailable => .{ .value = null, .estimated = false },
    };
}

/// Idem pour le temps mural (u64).
pub fn wallTimeWithFallback(p: Profile) Reading(u64) {
    return switch (p.wall_time) {
        .measured => |v| .{ .value = v, .estimated = false },
        .estimated => |v| .{ .value = v, .estimated = true },
        .unavailable => .{ .value = null, .estimated = false },
    };
}

// ─────────────────────────────────────────────────────────────
// Tests politiques d'acces
// ─────────────────────────────────────────────────────────────

test "requireMeasuredEnergy : accepte measured" {
    var p = Profile.empty();
    p.energy = .{ .measured = 42.5 };
    try std.testing.expectEqual(@as(?f64, 42.5), requireMeasuredEnergy(p));
}

test "requireMeasuredEnergy : refuse estimated" {
    var p = Profile.empty();
    p.energy = .{ .estimated = 42.5 };
    try std.testing.expectEqual(@as(?f64, null), requireMeasuredEnergy(p));
}

test "requireMeasuredEnergy : refuse unavailable" {
    const p = Profile.empty();
    try std.testing.expectEqual(@as(?f64, null), requireMeasuredEnergy(p));
}

test "energyWithFallback : distingue measured et estimated" {
    var p1 = Profile.empty();
    p1.energy = .{ .measured = 42.5 };
    const r1 = energyWithFallback(p1);
    try std.testing.expect(r1.isMeasured());
    try std.testing.expectEqual(@as(f64, 42.5), r1.value.?);

    var p2 = Profile.empty();
    p2.energy = .{ .estimated = 40.0 };
    const r2 = energyWithFallback(p2);
    try std.testing.expect(r2.hasValue());
    try std.testing.expect(!r2.isMeasured());
    try std.testing.expect(r2.estimated);
    try std.testing.expectEqual(@as(f64, 40.0), r2.value.?);
}

test "energyWithFallback : unavailable -> pas de valeur" {
    const p = Profile.empty();
    const r = energyWithFallback(p);
    try std.testing.expect(!r.hasValue());
    try std.testing.expect(!r.isMeasured());
    try std.testing.expect(!r.estimated);
}

test "wallTimeWithFallback : u64" {
    var p = Profile.empty();
    p.wall_time = .{ .measured = 1234 };
    const r = wallTimeWithFallback(p);
    try std.testing.expect(r.isMeasured());
    try std.testing.expectEqual(@as(u64, 1234), r.value.?);
}
