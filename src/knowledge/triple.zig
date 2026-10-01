const resource = @import("resource");

pub const KnowledgeId = resource.KnowledgeId;
pub const Node = resource.Node;

pub const Triple = struct {
    subject: Node,
    predicate: Node,
    object: Node,

    pub fn eql(a: Triple, b: Triple) bool {
        return a.subject.eql(b.subject) and
            a.predicate.eql(b.predicate) and
            a.object.eql(b.object);
    }
};

test "triple equality" {
    const t1 = Triple{
        .subject = .{ .resource = .{ .uri = "A" } },
        .predicate = .{ .resource = .{ .uri = "type" } },
        .object = .{ .resource = .{ .uri = "Person" } },
    };

    const t2 = Triple{
        .subject = .{ .resource = .{ .uri = "A" } },
        .predicate = .{ .resource = .{ .uri = "type" } },
        .object = .{ .resource = .{ .uri = "Person" } },
    };

    try @import("std").testing.expect(t1.eql(t2));
}
