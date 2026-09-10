const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;

pub const SessionType = union(enum) {
    send: struct { dest: []const u8, label: []const u8, ty: Id, next: *SessionType },
    receive: struct { src: []const u8, label: []const u8, ty: Id, next: *SessionType },
    end: void,
    
    pub fn isDual(self: SessionType, self_role: []const u8, other: SessionType, other_role: []const u8, store: *Store) bool {
        return switch (self) {
            .send => |s| if (other == .receive) {
                return std.mem.eql(u8, s.dest, other_role) and
                       std.mem.eql(u8, other.receive.src, self_role) and
                       std.mem.eql(u8, s.label, other.receive.label) and
                       s.ty == other.receive.ty and
                       s.next.isDual(self_role, other.receive.next.*, other_role, store);
            } else false,
            .receive => |r| if (other == .send) {
                return std.mem.eql(u8, r.src, other_role) and
                       std.mem.eql(u8, other.send.dest, self_role) and
                       std.mem.eql(u8, r.label, other.send.label) and
                       r.ty == other.send.ty and
                       r.next.isDual(self_role, other.send.next.*, other_role, store);
            } else false,
            .end => other == .end,
        };
    }
};

pub const GlobalProtocol = struct {
    from: []const u8,
    to: []const u8,
    label: []const u8,
    ty: Id,
    next: ?*GlobalProtocol,

    pub fn deinit(self: *GlobalProtocol, allocator: Allocator) void {
        if (self.next) |n| {
            n.deinit(allocator);
            allocator.destroy(n);
        }
    }

    pub fn project(self: *const GlobalProtocol, role: []const u8, allocator: Allocator) !SessionType {
        if (std.mem.eql(u8, self.from, role)) {
            const next_st = if (self.next) |n|
                try n.project(role, allocator)
            else
                SessionType.end;
            const ptr = try allocator.create(SessionType);
            ptr.* = next_st;
            return .{ .send = .{ .dest = self.to, .label = self.label, .ty = self.ty, .next = ptr } };
        } else if (std.mem.eql(u8, self.to, role)) {
            const next_st = if (self.next) |n|
                try n.project(role, allocator)
            else
                SessionType.end;
            const ptr = try allocator.create(SessionType);
            ptr.* = next_st;
            return .{ .receive = .{ .src = self.from, .label = self.label, .ty = self.ty, .next = ptr } };
        } else {
            if (self.next) |n| {
                return try n.project(role, allocator);
            } else {
                return SessionType.end;
            }
        }
    }
};
