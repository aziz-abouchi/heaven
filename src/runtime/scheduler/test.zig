const std = @import("std");
const Scheduler = @import("scheduler.zig").Scheduler;
const scheduler_task = @import("scheduler_task");

const Task = scheduler_task.Task;
const TaskState = scheduler_task.TaskState;
const TaskId = scheduler_task.TaskId;
const Policy = @import("policy.zig").Policy;

test "scheduler — EDF chooses earliest deadline" {
    var scheduler = Scheduler.init(std.testing.allocator);
    defer scheduler.deinit();

    scheduler.policy = .edf;

    try scheduler.add(.{
        .id = 1,
        .deadline_ns = 100,
        .state = .ready,
    });

    try scheduler.add(.{
        .id = 2,
        .deadline_ns = 50,
        .state = .ready,
    });

    const next = scheduler.next() orelse return error.ExpectedTask;
    try std.testing.expectEqual(@as(u64, 2), next.id);
}

test "scheduler — priority chooses highest priority" {
    var scheduler = Scheduler.init(std.testing.allocator);
    defer scheduler.deinit();

    scheduler.policy = .priority;

    try scheduler.add(.{
        .id = 1,
        .priority = 100,
        .state = .ready,
    });

    try scheduler.add(.{
        .id = 2,
        .priority = 10,
        .state = .ready,
    });

    const next = scheduler.next() orelse return error.ExpectedTask;
    try std.testing.expectEqual(@as(u64, 2), next.id);
}
