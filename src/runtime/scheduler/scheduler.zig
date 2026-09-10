const std = @import("std");
const scheduler_task = @import("scheduler_task");

const Task = scheduler_task.Task;
const TaskState = scheduler_task.TaskState;
const TaskId = scheduler_task.TaskId;

const Policy = @import("policy.zig").Policy;

pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    tasks: std.ArrayListUnmanaged(Task),
    policy: Policy = .priority,
    now_ns: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) Scheduler {
        return .{
            .allocator = allocator,
            .tasks = .{},
        };
    }

    pub fn deinit(self: *Scheduler) void {
        self.tasks.deinit(self.allocator);
    }

    pub fn add(self: *Scheduler, task: Task) !void {
        try self.tasks.append(self.allocator, task);
    }

    pub fn tick(self: *Scheduler, delta_ns: u64) void {
        self.now_ns += delta_ns;
    }

    pub fn next(self: *Scheduler) ?*Task {
        var best: ?*Task = null;

        for (self.tasks.items) |*task| {
            if (task.state != .ready) continue;

            if (best == null) {
                best = task;
                continue;
            }

            switch (self.policy) {
                .edf => {
                    const bd = best.?.deadline_ns orelse std.math.maxInt(u64);
                    const td = task.deadline_ns orelse std.math.maxInt(u64);
                    if (td < bd) best = task;
                },
                .priority => {
                    if (task.priority < best.?.priority) best = task;
                },
                .fifo, .energy_aware => {},
            }
        }

        return best;
    }
};
