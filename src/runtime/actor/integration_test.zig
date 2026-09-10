const std = @import("std");

const actor_mod = @import("actor");
const Actor = actor_mod.Actor;
const ActorRegistry = @import("registry").ActorRegistry;

const scheduler_task = @import("scheduler_task");
const scheduler = @import("scheduler");

const TaskState = scheduler_task.TaskState;
const Scheduler = scheduler.Scheduler;

test "actor → mailbox → task → scheduler" {
    const allocator = std.testing.allocator;

    var actor = Actor.init(allocator, 42);
    defer actor.deinit();

    var registry = ActorRegistry.init(allocator);
    defer registry.deinit();

    try registry.register(&actor);

    try actor.start();

    _ = try actor.send(null, "hello");

    try std.testing.expect(actor.hasWork());

    var sched = Scheduler.init(allocator);
    defer sched.deinit();

    try sched.add(.{
        .id = 1001,
        .actor_id = actor.id,
        .priority = actor.priority,
        .state = .ready,
    });

    const task = sched.next() orelse {
        return error.ExpectedTask;
    };

    try std.testing.expectEqual(
        @as(u64, 1001),
        task.id,
    );

    try std.testing.expectEqual(
        @as(?u64, 42),
        task.actor_id,
    );

    try std.testing.expectEqual(
        TaskState.ready,
        task.state,
    );

    const registered = registry.get(42) orelse {
        return error.ActorNotFound;
    };

    try std.testing.expectEqual(
        @as(usize, 1),
        registered.mailboxLen(),
    );
}
