//! ProfileAnnotations : association ClassId <-> ProfileId.
//!
//! Etape simple de la boucle Metrics -> EGraph -> Proof
//! (docs/spec/_metrics.md §Boucle).
//!
//! L'EGraph travaille sur des ClassId. Un profil mesure le cout
//! d'une implementation particuliere. ProfileAnnotations permet
//! d'associer a une classe (ou plusieurs classes equivalentes) les
//! profils qui l'ont mesuree, pour choisir la meilleure
//! implementation selon une metrique.
//!
//! Ce fichier ne depend PAS de egraph.zig : il ne connait que
//! ClassId (= u32, compatible egraph.ClassId) et Profile.
//! L'association est faite par le consommateur (l'optimiseur).

const std = @import("std");
const profile_mod = @import("profile.zig");
const profile_tree_mod = @import("profile_tree.zig");

pub const Profile = profile_mod.Profile;
pub const ProfileId = profile_mod.ProfileId;
pub const ProfileTree = profile_tree_mod.ProfileTree;

/// Identifiant de classe EGraph. Doit rester compatible avec
/// `egraph.ClassId` (= u32).
pub const ClassId = u32;

pub const AnnotateError = error{
    /// ProfileId inconnu du ProfileTree.
    UnknownProfile,
};

pub const ProfileAnnotations = struct {
    /// ClassId -> liste de ProfileId (plusieurs runs possibles).
    map: std.AutoHashMapUnmanaged(ClassId, std.ArrayListUnmanaged(ProfileId)),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .map = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.map.valueIterator();
        while (it.next()) |list| {
            list.deinit(self.allocator);
        }
        self.map.deinit(self.allocator);
    }

    /// Associe un profil (existant dans `tree`) a une classe.
    /// Refuse les doublons (meme class, meme profile).
    pub fn annotate(
        self: *Self,
        tree: *const ProfileTree,
        class_id: ClassId,
        profile_id: ProfileId,
    ) !void {
        if (tree.get(profile_id) == null) return AnnotateError.UnknownProfile;

        const gop = try self.map.getOrPut(self.allocator, class_id);
        if (!gop.found_existing) {
            gop.value_ptr.* = .empty;
        }
        for (gop.value_ptr.items) |existing| {
            if (existing == profile_id) return;
        }
        try gop.value_ptr.append(self.allocator, profile_id);
    }

    /// Profils associes a une classe. Retourne un slice vide si
    /// inconnue.
    pub fn profilesOf(self: *const Self, class_id: ClassId) []const ProfileId {
        const list = self.map.getPtr(class_id) orelse return &.{};
        return list.items;
    }

    /// Toutes les classes ayant recu au moins un profil.
    pub fn allClasses(self: *const Self, allocator: std.mem.Allocator) ![]ClassId {
        var out = std.ArrayList(ClassId).empty;
        errdefer out.deinit(allocator);
        var it = self.map.keyIterator();
        while (it.next()) |key| {
            try out.append(allocator, key.*);
        }
        return out.toOwnedSlice(allocator);
    }
};

// ─────────────────────────────────────────────────────────────
// Selection par metrique
// ─────────────────────────────────────────────────────────────

/// Metrique comparable pour la selection.
pub const MetricKind = enum {
    wall_time,
    energy,
    rss,
    instructions,
};

/// Resultat de la selection : la meilleure classe et sa valeur.
pub const Best = struct {
    class_id: ClassId,
    profile_id: ProfileId,
    value: f64,
};

/// Retourne la classe equivalente qui minimise la metrique choisie
/// parmi `candidates`. Ne considere que les profils dont la metrique
/// est `measured` (cf. requireMeasuredEnergy, P3 de _platform.md) :
/// une estimation n'est pas utilisee pour un choix d'optimisation.
///
/// Retourne null si aucune candidate n'a de mesure fiable pour la
/// metrique demandee.
pub fn bestForMetric(
    self: *const ProfileAnnotations,
    tree: *const ProfileTree,
    candidates: []const ClassId,
    kind: MetricKind,
) ?Best {
    var best: ?Best = null;
    for (candidates) |class_id| {
        const profiles = self.profilesOf(class_id);
        for (profiles) |pid| {
            const p = tree.get(pid) orelse continue;
            const measured = measureOf(p, kind) orelse continue;
            if (best == null or measured < best.?.value) {
                best = .{
                    .class_id = class_id,
                    .profile_id = pid,
                    .value = measured,
                };
            }
        }
    }
    return best;
}

/// Lit une metrique mesuree (jamais estimee). Retourne null si la
/// metrique n'est pas disponible en `measured`.
fn measureOf(p: Profile, kind: MetricKind) ?f64 {
    return switch (kind) {
        .wall_time => switch (p.wall_time) {
            .measured => |v| @floatFromInt(v),
            else => null,
        },
        .energy => switch (p.energy) {
            .measured => |v| v,
            else => null,
        },
        .rss => switch (p.rss) {
            .measured => |v| @floatFromInt(v),
            else => null,
        },
        .instructions => switch (p.instructions) {
            .measured => |v| @floatFromInt(v),
            else => null,
        },
    };
}

// ─────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────

const testing = std.testing;

test "ProfileAnnotations : annotate refuse un profil inconnu" {
    var tree = ProfileTree.init(testing.allocator);
    defer tree.deinit();
    var annot = ProfileAnnotations.init(testing.allocator);
    defer annot.deinit();

    try testing.expectError(
        AnnotateError.UnknownProfile,
        annot.annotate(&tree, 0, 0xDEADBEEF),
    );
}

test "ProfileAnnotations : annotate + profilesOf" {
    var tree = ProfileTree.init(testing.allocator);
    defer tree.deinit();
    var annot = ProfileAnnotations.init(testing.allocator);
    defer annot.deinit();

    var p = Profile.empty();
    p.wall_time = .{ .measured = 1000 };
    const id = try tree.add(p);

    try annot.annotate(&tree, 5, id);
    const profs = annot.profilesOf(5);
    try testing.expectEqual(@as(usize, 1), profs.len);
    try testing.expectEqual(id, profs[0]);
    try testing.expectEqual(@as(usize, 0), annot.profilesOf(999).len);
}

test "ProfileAnnotations : pas de doublon" {
    var tree = ProfileTree.init(testing.allocator);
    defer tree.deinit();
    var annot = ProfileAnnotations.init(testing.allocator);
    defer annot.deinit();

    var p = Profile.empty();
    p.wall_time = .{ .measured = 1000 };
    const id = try tree.add(p);

    try annot.annotate(&tree, 5, id);
    try annot.annotate(&tree, 5, id);
    try testing.expectEqual(@as(usize, 1), annot.profilesOf(5).len);
}

test "ProfileAnnotations : plusieurs profils par classe" {
    var tree = ProfileTree.init(testing.allocator);
    defer tree.deinit();
    var annot = ProfileAnnotations.init(testing.allocator);
    defer annot.deinit();

    var p1 = Profile.empty();
    p1.wall_time = .{ .measured = 1000 };
    const id1 = try tree.add(p1);

    var p2 = Profile.empty();
    p2.wall_time = .{ .measured = 2000 };
    const id2 = try tree.add(p2);

    try annot.annotate(&tree, 5, id1);
    try annot.annotate(&tree, 5, id2);
    try testing.expectEqual(@as(usize, 2), annot.profilesOf(5).len);
}

test "ProfileAnnotations : bestForMetric minimum wall_time" {
    var tree = ProfileTree.init(testing.allocator);
    defer tree.deinit();
    var annot = ProfileAnnotations.init(testing.allocator);
    defer annot.deinit();

    var p1 = Profile.empty();
    p1.wall_time = .{ .measured = 1000 };
    const id1 = try tree.add(p1);

    var p2 = Profile.empty();
    p2.wall_time = .{ .measured = 500 };
    const id2 = try tree.add(p2);

    var p3 = Profile.empty();
    p3.wall_time = .{ .measured = 750 };
    const id3 = try tree.add(p3);

    try annot.annotate(&tree, 1, id1);
    try annot.annotate(&tree, 2, id2);
    try annot.annotate(&tree, 3, id3);

    const candidates = [_]ClassId{ 1, 2, 3 };
    const best = bestForMetric(&annot, &tree, &candidates, .wall_time) orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(@as(ClassId, 2), best.class_id);
    try testing.expectEqual(@as(f64, 500.0), best.value);
}

test "ProfileAnnotations : bestForMetric ignore les estimations" {
    var tree = ProfileTree.init(testing.allocator);
    defer tree.deinit();
    var annot = ProfileAnnotations.init(testing.allocator);
    defer annot.deinit();

    var p1 = Profile.empty();
    p1.wall_time = .{ .estimated = 100 };
    const id1 = try tree.add(p1);

    var p2 = Profile.empty();
    p2.wall_time = .{ .measured = 1000 };
    const id2 = try tree.add(p2);

    try annot.annotate(&tree, 1, id1);
    try annot.annotate(&tree, 2, id2);

    const candidates = [_]ClassId{ 1, 2 };
    const best = bestForMetric(&annot, &tree, &candidates, .wall_time) orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(@as(ClassId, 2), best.class_id);
}

test "ProfileAnnotations : bestForMetric null si tout estime" {
    var tree = ProfileTree.init(testing.allocator);
    defer tree.deinit();
    var annot = ProfileAnnotations.init(testing.allocator);
    defer annot.deinit();

    var p1 = Profile.empty();
    p1.wall_time = .{ .estimated = 100 };
    const id1 = try tree.add(p1);

    try annot.annotate(&tree, 1, id1);
    const candidates = [_]ClassId{1};
    try testing.expectEqual(@as(?Best, null), bestForMetric(&annot, &tree, &candidates, .wall_time));
}

test "ProfileAnnotations : allClasses" {
    var tree = ProfileTree.init(testing.allocator);
    defer tree.deinit();
    var annot = ProfileAnnotations.init(testing.allocator);
    defer annot.deinit();

    var p = Profile.empty();
    p.wall_time = .{ .measured = 100 };
    const id = try tree.add(p);

    try annot.annotate(&tree, 10, id);
    try annot.annotate(&tree, 20, id);

    const classes = try annot.allClasses(testing.allocator);
    defer testing.allocator.free(classes);
    try testing.expectEqual(@as(usize, 2), classes.len);
}
