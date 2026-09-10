const std = @import("std");

const lifecycle = @import("lifecycle");
const mailbox_mod = @import("mailbox");
const Task = @import("scheduler_task").Task;

pub const ActorId = mailbox_mod.ActorId;
pub const ActorState = lifecycle.ActorState;
pub const Lifecycle = lifecycle.Lifecycle;
pub const Mailbox = mailbox_mod.Mailbox;

pub const Actor = struct {
    allocator: std.mem.Allocator,
    id: ActorId,
    lifecycle: Lifecycle,
    mailbox: Mailbox,
    priority: u8 = 128,

    pub fn init(
        allocator: std.mem.Allocator,
        id: ActorId,
    ) Actor {
        return .{
            .allocator = allocator,
            .id = id,
            .lifecycle = Lifecycle.init(),
            .mailbox = Mailbox.init(allocator),
        };
    }

    pub fn deinit(self: *Actor) void {
        self.mailbox.deinit();
    }

    pub fn state(self: *const Actor) ActorState {
        return self.lifecycle.state;
    }

    pub fn start(self: *Actor) !void {
        try self.lifecycle.start();
    }

    pub fn run(self: *Actor) !void {
        try self.lifecycle.run();
    }

    pub fn block(self: *Actor) !void {
        try self.lifecycle.block();
    }

    pub fn resumeActor(self: *Actor) !void {
        try self.lifecycle.resumeActor();
    }

    pub fn stop(self: *Actor) !void {
        try self.lifecycle.stop();
    }

    pub fn fail(self: *Actor) !void {
        try self.lifecycle.fail();
    }

    pub fn send(
        self: *Actor,
        sender: ?ActorId,
        payload: []const u8,
    ) !mailbox_mod.MessageId {
        return self.mailbox.send(sender, payload);
    }

    pub fn hasWork(self: *const Actor) bool {
        return !self.mailbox.isEmpty();
    }

    pub fn mailboxLen(self: *const Actor) usize {
        return self.mailbox.len();
    }

    pub fn makeTask(
        self: *const Actor,
        task_id: u64,
    ) Task {
        return .{
            .id = task_id,
            .actor_id = self.id,
            .priority = self.priority,
            .state = .ready,
        };
    }
};

test "actor — lifecycle and mailbox" {
    var actor = Actor.init(std.testing.allocator, 7);
    defer actor.deinit();

    try std.testing.expectEqual(
        @as(ActorId, 7),
        actor.id,
    );

    try std.testing.expectEqual(
        ActorState.created,
        actor.state(),
    );

    try actor.start();

    try std.testing.expectEqual(
        ActorState.ready,
        actor.state(),
    );

    _ = try actor.send(1, "hello");

    try std.testing.expect(actor.hasWork());
    try std.testing.expectEqual(
        @as(usize, 1),
        actor.mailboxLen(),
    );

    try actor.run();

    try std.testing.expectEqual(
        ActorState.running,
        actor.state(),
    );
}
