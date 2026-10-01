const std = @import("std");
const assertion = @import("assertion");

pub const Store = struct {
    allocator: std.mem.Allocator,
    assertions: std.ArrayListUnmanaged(assertion.Assertion) = .{},

    pub fn init(allocator: std.mem.Allocator) Store {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Store) void {
        self.assertions.deinit(self.allocator);
    }

    pub fn add(
        self: *Store,
        value: assertion.Assertion,
    ) !usize {
        try self.assertions.append(self.allocator, value);
        return self.assertions.items.len - 1;
    }

    pub fn count(self: *const Store) usize {
        return self.assertions.items.len;
    }

    pub fn get(
        self: *const Store,
        index: usize,
    ) ?assertion.Assertion {
        if (index >= self.assertions.items.len) return null;
        return self.assertions.items[index];
    }

    /// Retourne la première assertion portant exactement le triple demandé.
    /// Le Store ne déduplique pas et ne fusionne pas les assertions.
    pub fn find(
        self: *const Store,
        wanted: assertion.triple.Triple,
    ) ?assertion.Assertion {
        for (self.assertions.items) |item| {
            if (item.triple.eql(wanted)) {
                return item;
            }
        }

        return null;
    }
};

test "same triple can have multiple provenance records" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    const t = assertion.Assertion{
        .triple = .{
            .subject = .{ .resource = .{ .uri = "A" } },
            .predicate = .{ .resource = .{ .uri = "type" } },
            .object = .{ .resource = .{ .uri = "Person" } },
        },
        .status = .imported,
        .confidence = .high,
        .provenance = .{
            .source = .wikidata,
            .source_id = "Q42",
        },
    };

    var t2 = t;
    t2.provenance = .{
        .source = .user,
        .source_id = "local",
    };

    _ = try store.add(t);
    _ = try store.add(t2);

    try std.testing.expectEqual(@as(usize, 2), store.count());

    const found = store.find(t.triple) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(assertion.SourceKind.wikidata, found.provenance.source);
}

test "find returns null for an absent triple" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    const wanted = assertion.triple.Triple{
        .subject = .{ .resource = .{ .uri = "Missing" } },
        .predicate = .{ .resource = .{ .uri = "type" } },
        .object = .{ .resource = .{ .uri = "Person" } },
    };

    try std.testing.expect(store.find(wanted) == null);
}

test "get returns assertion by insertion index" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    const value = assertion.Assertion{
        .triple = .{
            .subject = .{ .resource = .{ .uri = "A" } },
            .predicate = .{ .resource = .{ .uri = "name" } },
            .object = .{ .literal = .{ .lexical = "Alice" } },
        },
        .status = .asserted,
        .provenance = .{
            .source = .user,
        },
    };

    const index = try store.add(value);

    try std.testing.expectEqual(@as(usize, 0), index);

    const found = store.get(index) orelse return error.TestExpectedEqual;
    try std.testing.expect(found.triple.eql(value.triple));
    try std.testing.expectEqual(assertion.Status.asserted, found.status);
}
