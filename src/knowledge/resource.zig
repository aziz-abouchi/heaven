const std = @import("std");

pub const KnowledgeId = u32;
pub const NULL_ID: KnowledgeId = std.math.maxInt(KnowledgeId);

pub const Resource = union(enum) {
    uri: []const u8,
    blank: KnowledgeId,

    pub fn eql(a: Resource, b: Resource) bool {
        return switch (a) {
            .uri => |au| switch (b) {
                .uri => |bu| std.mem.eql(u8, au, bu),
                else => false,
            },
            .blank => |ab| switch (b) {
                .blank => |bb| ab == bb,
                else => false,
            },
        };
    }
};

pub const Literal = struct {
    lexical: []const u8,
    datatype: ?[]const u8 = null,
    language: ?[]const u8 = null,

    pub fn eql(a: Literal, b: Literal) bool {
        if (!std.mem.eql(u8, a.lexical, b.lexical)) return false;

        const ad = a.datatype orelse "";
        const bd = b.datatype orelse "";
        if (!std.mem.eql(u8, ad, bd)) return false;

        const al = a.language orelse "";
        const bl = b.language orelse "";
        return std.mem.eql(u8, al, bl);
    }
};

pub const Node = union(enum) {
    resource: Resource,
    literal: Literal,

    pub fn eql(a: Node, b: Node) bool {
        return switch (a) {
            .resource => |ar| switch (b) {
                .resource => |br| ar.eql(br),
                else => false,
            },
            .literal => |al| switch (b) {
                .literal => |bl| al.eql(bl),
                else => false,
            },
        };
    }
};

test "resource URI equality" {
    const a = Resource{ .uri = "https://example.org/Alice" };
    const b = Resource{ .uri = "https://example.org/Alice" };

    try std.testing.expect(a.eql(b));
}

test "different URI are not equal" {
    const a = Resource{ .uri = "https://example.org/Alice" };
    const b = Resource{ .uri = "https://example.org/Bob" };

    try std.testing.expect(!a.eql(b));
}

test "blank nodes compare by KnowledgeId" {
    const a = Resource{ .blank = 1 };
    const b = Resource{ .blank = 1 };
    const c = Resource{ .blank = 2 };

    try std.testing.expect(a.eql(b));
    try std.testing.expect(!a.eql(c));
}
