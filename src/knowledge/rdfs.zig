const std = @import("std");
const assertion = @import("assertion");
const store_mod = @import("knowledge_store");
const resource = @import("resource");

pub const RDFS_SUBCLASS_OF =
    "http://www.w3.org/2000/01/rdf-schema#subClassOf";

pub const Reasoner = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Reasoner {
        return .{
            .allocator = allocator,
        };
    }

    /// Calcule la fermeture transitive de rdfs:subClassOf.
    ///
    /// Le Store source n'est jamais modifié.
    /// Les assertions inférées sont retournées séparément.
    pub fn close(
        self: *const Reasoner,
        store: *const store_mod.Store,
    ) !std.ArrayListUnmanaged(assertion.Assertion) {
        var result: std.ArrayListUnmanaged(assertion.Assertion) = .{};

        var edges: std.ArrayListUnmanaged(Edge) = .{};
        defer edges.deinit(self.allocator);

        for (store.assertions.items) |item| {
            if (!isSubclassAssertion(item)) continue;

            try edges.append(self.allocator, .{
                .from = item.triple.subject,
                .to = item.triple.object,
            });
        }

        // Pour chaque sommet de départ, calcul de la fermeture transitive.
        for (edges.items) |start| {
            var frontier: std.ArrayListUnmanaged(resource.Node) = .{};
            defer frontier.deinit(self.allocator);

            var visited: std.ArrayListUnmanaged(resource.Node) = .{};
            defer visited.deinit(self.allocator);

            try frontier.append(self.allocator, start.to);

            while (frontier.items.len > 0) {
                const current = frontier.items[frontier.items.len - 1];
                frontier.items.len -= 1;

                if (containsNode(visited.items, current)) continue;
                try visited.append(self.allocator, current);

                // Pas de réflexivité implicite.
                // Une relation déjà présente dans le Store n'est pas
                // retournée comme nouvelle inférence.
                if (!current.eql(start.from) and
                    !hasDirectEdge(edges.items, start.from, current))
                {
                    try result.append(self.allocator, .{
                        .triple = .{
                            .subject = start.from,
                            .predicate = .{
                                .resource = .{
                                    .uri = RDFS_SUBCLASS_OF,
                                },
                            },
                            .object = current,
                        },
                        .status = .inferred,
                        .provenance = .{
                            .source = .rdfs,
                        },
                    });
                }

                for (edges.items) |edge| {
                    if (edge.from.eql(current) and
                        !containsNode(visited.items, edge.to))
                    {
                        try frontier.append(self.allocator, edge.to);
                    }
                }
            }
        }

        return result;
    }
};

const Edge = struct {
    from: resource.Node,
    to: resource.Node,
};

fn isSubclassAssertion(value: assertion.Assertion) bool {
    return switch (value.triple.predicate) {
        .resource => |r| switch (r) {
            .uri => |uri| std.mem.eql(u8, uri, RDFS_SUBCLASS_OF),
            .blank => false,
        },
        .literal => false,
    };
}

fn containsNode(
    nodes: []const resource.Node,
    wanted: resource.Node,
) bool {
    for (nodes) |node| {
        if (node.eql(wanted)) return true;
    }

    return false;
}

fn hasDirectEdge(
    edges: []const Edge,
    from: resource.Node,
    to: resource.Node,
) bool {
    for (edges) |edge| {
        if (edge.from.eql(from) and edge.to.eql(to)) {
            return true;
        }
    }

    return false;
}

fn nodeUri(uri: []const u8) resource.Node {
    return .{
        .resource = .{
            .uri = uri,
        },
    };
}

fn subclass(
    subject: []const u8,
    object: []const u8,
) assertion.Assertion {
    return .{
        .triple = .{
            .subject = nodeUri(subject),
            .predicate = nodeUri(RDFS_SUBCLASS_OF),
            .object = nodeUri(object),
        },
        .status = .asserted,
        .provenance = .{
            .source = .user,
        },
    };
}

test "RDFS transitivity infers A subclassOf C" {
    var store = store_mod.Store.init(std.testing.allocator);
    defer store.deinit();

    _ = try store.add(subclass("A", "B"));
    _ = try store.add(subclass("B", "C"));

    const reasoner = Reasoner.init(std.testing.allocator);
    var closure = try reasoner.close(&store);
    defer closure.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), closure.items.len);

    const inferred = closure.items[0];

    try std.testing.expect(inferred.triple.eql(subclass("A", "C").triple));
    try std.testing.expectEqual(
        assertion.Status.inferred,
        inferred.status,
    );
    try std.testing.expectEqual(
        assertion.SourceKind.rdfs,
        inferred.provenance.source,
    );
}

test "RDFS does not infer reflexive subclassOf" {
    var store = store_mod.Store.init(std.testing.allocator);
    defer store.deinit();

    _ = try store.add(subclass("A", "B"));

    const reasoner = Reasoner.init(std.testing.allocator);
    var closure = try reasoner.close(&store);
    defer closure.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), closure.items.len);
}

test "RDFS preserves the source Store" {
    var store = store_mod.Store.init(std.testing.allocator);
    defer store.deinit();

    _ = try store.add(subclass("A", "B"));
    _ = try store.add(subclass("B", "C"));

    const before = store.count();

    const reasoner = Reasoner.init(std.testing.allocator);
    var closure = try reasoner.close(&store);
    defer closure.deinit(std.testing.allocator);

    try std.testing.expectEqual(before, store.count());
}

test "RDFS ignores unrelated predicates" {
    var store = store_mod.Store.init(std.testing.allocator);
    defer store.deinit();

    _ = try store.add(.{
        .triple = .{
            .subject = nodeUri("A"),
            .predicate = nodeUri("knows"),
            .object = nodeUri("B"),
        },
        .status = .asserted,
        .provenance = .{
            .source = .user,
        },
    });

    _ = try store.add(subclass("B", "C"));

    const reasoner = Reasoner.init(std.testing.allocator);
    var closure = try reasoner.close(&store);
    defer closure.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), closure.items.len);
}

test "RDFS computes multi-hop transitivity" {
    var store = store_mod.Store.init(std.testing.allocator);
    defer store.deinit();

    _ = try store.add(subclass("A", "B"));
    _ = try store.add(subclass("B", "C"));
    _ = try store.add(subclass("C", "D"));

    const reasoner = Reasoner.init(std.testing.allocator);
    var closure = try reasoner.close(&store);
    defer closure.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), closure.items.len);
}
