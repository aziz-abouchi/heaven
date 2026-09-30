//! ProfileTree : hierarchie de profils (docs/spec/_metrics.md
//! §Profils imbriques).
//!
//! Un `Profile` porte un `parent: ?ProfileId`. `ProfileTree`
//! materialise la relation : elle indexe plusieurs profils et
//! permet de naviguer (enfants, ancetres, racine).
//!
//! Invariants :
//! - Un profil ajoute est content-addressed : son `id` est calcule
//!   par `computeId()` a l'ajout.
//! - Un parent reference doit exister dans l'arbre, sauf si c'est
//!   le premier (racine). Ajouter un enfant orphelin est une erreur.
//! - Aucun cycle (un parent ne peut pas etre son propre ancetre).

const std = @import("std");
const profile_mod = @import("profile.zig");

pub const Profile = profile_mod.Profile;
pub const ProfileId = profile_mod.ProfileId;

pub const TreeError = error{
    /// Parent reference inexistant.
    OrphanProfile,
    /// Le parent creerait un cycle.
    CycleDetected,
};

pub const ProfileTree = struct {
    profiles: std.AutoHashMapUnmanaged(ProfileId, Profile),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .profiles = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.profiles.deinit(self.allocator);
    }

    /// Ajoute un profil a l'arbre. Recalcule son `id` (content-
    /// addressed). Le parent doit deja exister ou etre null (racine).
    pub fn add(self: *Self, p_: Profile) !ProfileId {
        var p = p_;
        _ = p.computeId();

        if (p.parent) |parent_id| {
            if (!self.profiles.contains(parent_id)) {
                return TreeError.OrphanProfile;
            }
            // Verifier l'absence de cycle : le nouveau profil ne doit
            // pas etre un ancetre du parent declare.
            var current: ?ProfileId = parent_id;
            while (current) |cur_id| {
                if (cur_id == p.id) return TreeError.CycleDetected;
                const cur = self.profiles.get(cur_id) orelse break;
                current = cur.parent;
            }
        }

        try self.profiles.put(self.allocator, p.id, p);
        return p.id;
    }

    pub fn get(self: *const Self, id: ProfileId) ?Profile {
        return self.profiles.get(id);
    }

    pub fn count(self: *const Self) u32 {
        return self.profiles.count();
    }

// ─────────────────────────────────────────────────────────────
// Navigation
// ─────────────────────────────────────────────────────────────

/// Retourne les enfants directs d'un profil. Alloue le slice.
    pub fn children(
    self: *const ProfileTree,
    parent_id: ProfileId,
    allocator: std.mem.Allocator,
) ![]ProfileId {
    var out = std.ArrayList(ProfileId).empty;
    errdefer out.deinit(allocator);

    var it = self.profiles.valueIterator();
    while (it.next()) |p| {
        if (p.parent) |pid| {
            if (pid == parent_id) {
                try out.append(allocator, p.id);
            }
        }
    }
    return out.toOwnedSlice(allocator);
}

/// Retourne la chaine d'ancetres d'un profil, du parent direct
/// jusqu'a la racine. Ne contient pas le profil lui-meme.
    pub fn ancestors(
    self: *const ProfileTree,
    id: ProfileId,
    allocator: std.mem.Allocator,
) ![]ProfileId {
    var out = std.ArrayList(ProfileId).empty;
    errdefer out.deinit(allocator);

    var current = self.profiles.get(id) orelse return out.toOwnedSlice(allocator);
    while (current.parent) |pid| {
        try out.append(allocator, pid);
        current = self.profiles.get(pid) orelse break;
    }
    return out.toOwnedSlice(allocator);
}

/// Retourne l'id de la racine de la chaine contenant `id`.
/// Si le profil n'existe pas, retourne null.
    pub fn rootOf(self: *const ProfileTree, id: ProfileId) ?ProfileId {
    var current = self.profiles.get(id) orelse return null;
    while (current.parent) |pid| {
        current = self.profiles.get(pid) orelse return current.id;
    }
    return current.id;
}

/// Retourne la profondeur (nombre d'ancetres) d'un profil.
/// Racine = 0. Profil inexistant -> null.
    pub fn depth(self: *const ProfileTree, id: ProfileId) ?u32 {
        var current = self.profiles.get(id) orelse return null;
        var d: u32 = 0;
        while (current.parent) |pid| {
            d += 1;
            current = self.profiles.get(pid) orelse break;
        }
        return d;
    }
};

// ─────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────

const testing = std.testing;

fn emptyProfile() Profile {
    return Profile.empty();
}

test "ProfileTree : ajout d'une racine" {
    var tree = ProfileTree.init(testing.allocator);
    defer tree.deinit();

    var p = emptyProfile();
    p.wall_time = .{ .measured = 100 };
    const id = try tree.add(p);

    try testing.expectEqual(@as(u32, 1), tree.count());
    try testing.expect(tree.get(id) != null);
    try testing.expectEqual(@as(?ProfileId, id), tree.rootOf(id));
    try testing.expectEqual(@as(?u32, 0), tree.depth(id));
}

test "ProfileTree : ajout d'un enfant valide" {
    var tree = ProfileTree.init(testing.allocator);
    defer tree.deinit();

    var root = emptyProfile();
    root.wall_time = .{ .measured = 100 };
    const root_id = try tree.add(root);

    var child = emptyProfile();
    child.wall_time = .{ .measured = 50 };
    child.parent = root_id;
    child.scope = .nested;
    const child_id = try tree.add(child);

    try testing.expectEqual(@as(u32, 2), tree.count());
    try testing.expectEqual(@as(?ProfileId, root_id), tree.rootOf(child_id));
    try testing.expectEqual(@as(?u32, 1), tree.depth(child_id));
}

test "ProfileTree : refus d'un parent inexistant" {
    var tree = ProfileTree.init(testing.allocator);
    defer tree.deinit();

    var p = emptyProfile();
    p.parent = 0xDEADBEEF;
    try testing.expectError(TreeError.OrphanProfile, tree.add(p));
}

test "ProfileTree : children" {
    var tree = ProfileTree.init(testing.allocator);
    defer tree.deinit();

    var root = emptyProfile();
    root.wall_time = .{ .measured = 100 };
    const root_id = try tree.add(root);

    var c1 = emptyProfile();
    c1.wall_time = .{ .measured = 10 };
    c1.parent = root_id;
    c1.scope = .nested;
    const c1_id = try tree.add(c1);

    var c2 = emptyProfile();
    c2.wall_time = .{ .measured = 20 };
    c2.parent = root_id;
    c2.scope = .nested;
    const c2_id = try tree.add(c2);

    const kids = try tree.children(root_id, testing.allocator);
    defer testing.allocator.free(kids);

    try testing.expectEqual(@as(usize, 2), kids.len);
    var found_c1 = false;
    var found_c2 = false;
    for (kids) |k| {
        if (k == c1_id) found_c1 = true;
        if (k == c2_id) found_c2 = true;
    }
    try testing.expect(found_c1);
    try testing.expect(found_c2);
}

test "ProfileTree : ancestors d'un petit-fils" {
    var tree = ProfileTree.init(testing.allocator);
    defer tree.deinit();

    var root = emptyProfile();
    root.wall_time = .{ .measured = 100 };
    const root_id = try tree.add(root);

    var child = emptyProfile();
    child.wall_time = .{ .measured = 50 };
    child.parent = root_id;
    child.scope = .nested;
    const child_id = try tree.add(child);

    var grandchild = emptyProfile();
    grandchild.wall_time = .{ .measured = 25 };
    grandchild.parent = child_id;
    grandchild.scope = .nested;
    const gc_id = try tree.add(grandchild);

    const anc = try tree.ancestors(gc_id, testing.allocator);
    defer testing.allocator.free(anc);

    try testing.expectEqual(@as(usize, 2), anc.len);
    // ordre : parent direct d'abord, puis grand-parent
    try testing.expectEqual(child_id, anc[0]);
    try testing.expectEqual(root_id, anc[1]);
}

test "ProfileTree : depth sur trois niveaux" {
    var tree = ProfileTree.init(testing.allocator);
    defer tree.deinit();

    var root = emptyProfile();
    root.wall_time = .{ .measured = 100 };
    const root_id = try tree.add(root);

    var child = emptyProfile();
    child.wall_time = .{ .measured = 50 };
    child.parent = root_id;
    child.scope = .nested;
    const child_id = try tree.add(child);

    var gc = emptyProfile();
    gc.wall_time = .{ .measured = 25 };
    gc.parent = child_id;
    gc.scope = .nested;
    const gc_id = try tree.add(gc);

    try testing.expectEqual(@as(?u32, 0), tree.depth(root_id));
    try testing.expectEqual(@as(?u32, 1), tree.depth(child_id));
    try testing.expectEqual(@as(?u32, 2), tree.depth(gc_id));
}

test "ProfileTree : rootOf sur trois niveaux" {
    var tree = ProfileTree.init(testing.allocator);
    defer tree.deinit();

    var root = emptyProfile();
    root.wall_time = .{ .measured = 100 };
    const root_id = try tree.add(root);

    var child = emptyProfile();
    child.wall_time = .{ .measured = 50 };
    child.parent = root_id;
    child.scope = .nested;
    const child_id = try tree.add(child);

    var gc = emptyProfile();
    gc.wall_time = .{ .measured = 25 };
    gc.parent = child_id;
    gc.scope = .nested;
    const gc_id = try tree.add(gc);

    try testing.expectEqual(@as(?ProfileId, root_id), tree.rootOf(gc_id));
    try testing.expectEqual(@as(?ProfileId, root_id), tree.rootOf(child_id));
}

test "ProfileTree : dedup content-addressed" {
    var tree = ProfileTree.init(testing.allocator);
    defer tree.deinit();

    var p1 = emptyProfile();
    p1.wall_time = .{ .measured = 100 };
    const id1 = try tree.add(p1);

    var p2 = emptyProfile();
    p2.wall_time = .{ .measured = 100 };
    const id2 = try tree.add(p2);

    // Meme contenu -> meme id -> une seule entree (put ecrase).
    try testing.expectEqual(id1, id2);
    try testing.expectEqual(@as(u32, 1), tree.count());
}

test "ProfileTree : profils differents -> ids differents" {
    var tree = ProfileTree.init(testing.allocator);
    defer tree.deinit();

    var p1 = emptyProfile();
    p1.wall_time = .{ .measured = 100 };
    const id1 = try tree.add(p1);

    var p2 = emptyProfile();
    p2.wall_time = .{ .measured = 200 };
    const id2 = try tree.add(p2);

    try testing.expect(id1 != id2);
    try testing.expectEqual(@as(u32, 2), tree.count());
}
