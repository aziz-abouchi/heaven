//! Test d'integration : ProfileAnnotations + EGraph.
//!
//! Valide la boucle Metrics -> EGraph -> Proof (docs/spec/_metrics.md
//! §Boucle). Un EGraph contient des classes equivalentes ; un profil
//! mesure le cout de chaque classe ; bestForMetric choisit la moins
//! chere sur la base des mesures REELLES.
//!
//! Ce test combine deux couches (egraph + abi) via le module `abi`
//! declare dans build.zig.

const std = @import("std");
const egraph_mod = @import("egraph");
const egraph_viz = @import("egraph_viz");
const abi = @import("abi");
const expr = @import("expr");

const EGraph = egraph_mod.EGraph;
const ClassId = egraph_mod.ClassId;
const Store = expr.Store;

const Profile = abi.Profile;
const ProfileTree = abi.ProfileTree;
const ProfileAnnotations = abi.ProfileAnnotations;
const MetricKind = abi.MetricKind;

test "boucle Metrics -> EGraph : bestForMetric choisit la classe la moins chere" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var g = EGraph.init(&store, allocator);
    defer g.deinit();

    // Deux expressions : 2 + 3 (class A) et 1 + 4 (class B)
    const two_three = try store.binop("+",
        try store.int(2), try store.int(3));
    const one_four = try store.binop("+",
        try store.int(1), try store.int(4));

    const class_a = try g.add(two_three);
    const class_b = try g.add(one_four);

    // Annoter chaque classe avec un profil mesure.
    var tree = ProfileTree.init(allocator);
    defer tree.deinit();

    var pa = Profile.empty();
    pa.wall_time = .{ .measured = 1000 }; // A mesure 1000 ns
    const pa_id = try tree.add(pa);

    var pb = Profile.empty();
    pb.wall_time = .{ .measured = 500 };  // B mesure 500 ns (plus rapide)
    const pb_id = try tree.add(pb);

    var annot = ProfileAnnotations.init(allocator);
    defer annot.deinit();
    try annot.annotate(&tree, class_a, pa_id);
    try annot.annotate(&tree, class_b, pb_id);

    // Choisir la meilleure sur wall_time.
    const candidates = [_]ClassId{ class_a, class_b };
    const best = abi.profile_annotations.bestForMetric(
        &annot, &tree, &candidates, .wall_time,
    ) orelse return error.TestUnexpectedResult;

    try std.testing.expectEqual(class_b, best.class_id);
    try std.testing.expectEqual(@as(f64, 500.0), best.value);
}

test "boucle Metrics -> EGraph : estimation ignoree meme si plus basse" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var g = EGraph.init(&store, allocator);
    defer g.deinit();

    const e1 = try store.int(1);
    const e2 = try store.int(2);
    const class_a = try g.add(e1);
    const class_b = try g.add(e2);

    var tree = ProfileTree.init(allocator);
    defer tree.deinit();

    // A : estimation 10ns (tres basse, mais non fiable)
    var pa = Profile.empty();
    pa.wall_time = .{ .estimated = 10 };
    const pa_id = try tree.add(pa);

    // B : mesure 1000ns
    var pb = Profile.empty();
    pb.wall_time = .{ .measured = 1000 };
    const pb_id = try tree.add(pb);

    var annot = ProfileAnnotations.init(allocator);
    defer annot.deinit();
    try annot.annotate(&tree, class_a, pa_id);
    try annot.annotate(&tree, class_b, pb_id);

    const candidates = [_]ClassId{ class_a, class_b };
    const best = abi.profile_annotations.bestForMetric(
        &annot, &tree, &candidates, .wall_time,
    ) orelse return error.TestUnexpectedResult;

    // class_b gagne : la classe A estimee n'est pas eligible.
    try std.testing.expectEqual(class_b, best.class_id);
    try std.testing.expectEqual(@as(f64, 1000.0), best.value);
}

test "boucle Metrics -> EGraph : null si aucune mesure fiable" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var g = EGraph.init(&store, allocator);
    defer g.deinit();

    const e1 = try store.int(1);
    const class_a = try g.add(e1);

    var tree = ProfileTree.init(allocator);
    defer tree.deinit();

    var pa = Profile.empty();
    pa.wall_time = .{ .estimated = 10 };
    const pa_id = try tree.add(pa);

    var annot = ProfileAnnotations.init(allocator);
    defer annot.deinit();
    try annot.annotate(&tree, class_a, pa_id);

    const candidates = [_]ClassId{class_a};
    const best = abi.profile_annotations.bestForMetric(
        &annot, &tree, &candidates, .wall_time,
    );
    try std.testing.expectEqual(@as(?abi.profile_annotations.Best, null), best);
}

test "egraph_viz — export JSON" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();
    var g = EGraph.init(&store, allocator);
    defer g.deinit();

    // Créer quelques expressions
    const x = try store.sym("x");
    const one = try store.int(1);
    const add_expr = try store.binop("+", x, one);

    const class_a = try g.add(add_expr);
    const class_b = try g.add(x);
    _ = try g.merge(class_a, class_b);

    // Exporter en JSON
    const json = try egraph_viz.exportToJson(&g, allocator);
    defer allocator.free(json);

    // Vérifier que le JSON contient les éléments attendus
    try std.testing.expect(std.mem.indexOf(u8, json, "\"classes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"nodes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"merges\"") != null);
}
