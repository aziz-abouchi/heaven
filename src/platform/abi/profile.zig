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
