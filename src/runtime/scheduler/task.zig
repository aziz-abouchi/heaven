pub const TaskId = u64;
pub const ActorId = u64;
pub const Time = u64;

pub const TaskState = enum {
    ready,
    running,
    blocked,
    finished,
    cancelled,
};

pub const Task = struct {
    id: TaskId,
    actor_id: ?ActorId = null,

    deadline_ns: ?Time = null,
    period_ns: ?Time = null,
    priority: u8 = 128,
    state: TaskState = .ready,

    cpu_budget_ns: ?Time = null,
    energy_budget_pj: ?u64 = null,
};