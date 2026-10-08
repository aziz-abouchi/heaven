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

    // ─── D8 3a-3-c : corps executables ───
    /// Fonction `state -> valeur | (perform "yield")`.
    body_fn: ?u64 = null,
    /// Etat courant (mis a jour entre iterations).
    current_state: ?u64 = null,
    /// Etat capture par `yield` (consomme par le scheduler).
    pending_state: ?u64 = null,
};