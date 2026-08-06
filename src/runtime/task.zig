const std = @import("std");

pub const Task = struct {
    node_id: u32,
    cost: u32,
    origin: []const u8,
};

pub const TaskQueue = struct {
    allocator: std.mem.Allocator,
    // CHANGEMENT : Passage en Unmanaged
    tasks: std.ArrayListUnmanaged(Task),

    pub fn init(allocator: std.mem.Allocator) TaskQueue {
        return .{
            .allocator = allocator,
            .tasks = .{}, // Initialisation à vide (équivalent de {} ou .init())
        };
    }

    pub fn push(self: *TaskQueue, task: Task) !void {
        // En Unmanaged, on doit passer l'allocateur à chaque append
        try self.tasks.append(self.allocator, task);
    }

    pub fn pop(self: *TaskQueue) ?Task {
        if (self.tasks.items.len == 0) return null;
        return self.tasks.pop(); // pop() ne nécessite pas d'allocateur
    }

    pub fn len(self: *TaskQueue) usize {
        return self.tasks.items.len;
    }

    pub fn deinit(self: *TaskQueue) void {
        self.tasks.deinit(self.allocator);
    }
};
