const std = @import("std");
const resource = @import("resource");
const triple = @import("triple");
const assertion = @import("assertion");
const store = @import("knowledge_store");
const rdfs = @import("knowledge_rdfs");

test "Knowledge modules are wired" {
    _ = resource;
    _ = triple;
    _ = assertion;
    _ = store;
    _ = rdfs;

    try std.testing.expect(true);
}
