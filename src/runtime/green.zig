const std = @import("std");
const Allocator = std.mem.Allocator;
const platform = @import("platform");

pub const TaskState = enum { pending, running, done, failed };

pub const GreenTask = struct {
    id: u32,
    expression: []const u8,
    result: ?[]const u8,
    state: TaskState,
    thread: ?platform.Thread,
};

pub const Hook = struct {
    event: []const u8,
    agent_expr: []const u8,
};

pub const GreenScheduler = struct {
    allocator: Allocator,
    tasks: std.ArrayListUnmanaged(GreenTask),
    hooks: std.ArrayListUnmanaged(Hook),
    next_id: u32,
    eval_fn: ?*const fn ([]const u8, Allocator) ?[]const u8,

    pub fn init(allocator: Allocator) GreenScheduler {
        return .{
            .allocator = allocator,
            .tasks = .{},
            .hooks = .{},
            .next_id = 1,
            .eval_fn = null,
        };
    }

    pub fn deinit(self: *GreenScheduler) void {
        for (self.tasks.items) |*t| {
            if (t.result) |r| self.allocator.free(r);
            self.allocator.free(t.expression);
        }
        self.tasks.deinit(self.allocator);
        for (self.hooks.items) |h| {
            self.allocator.free(h.event);
            self.allocator.free(h.agent_expr);
        }
        self.hooks.deinit(self.allocator);
    }

    pub fn registerHook(self: *GreenScheduler, event: []const u8, agent_expr: []const u8) !void {
        try self.hooks.append(self.allocator, .{
            .event = try self.allocator.dupe(u8, event),
            .agent_expr = try self.allocator.dupe(u8, agent_expr),
        });
    }

    pub fn fireEvent(self: *GreenScheduler, event: []const u8) !void {
        for (self.hooks.items) |h| {
            if (std.mem.eql(u8, h.event, event)) {
                // platform.dbg("[HOOK] Event '{s}' → spawning '{s}'\n", .{ event, h.agent_expr });
                _ = try self.spawn(h.agent_expr);
            }
        }
    }

    pub fn spawn(self: *GreenScheduler, expr: []const u8) !u32 {
        const id = self.next_id;
        self.next_id += 1;

        const expr_copy = try self.allocator.dupe(u8, expr);

        // Evaluate immediately (safe: sequential on main store)
        var result: ?[]const u8 = null;
        var state: TaskState = .failed;
        if (self.eval_fn) |ef| {
            if (ef(expr, self.allocator)) |res| {
                result = res;
                state = .done;
            }
        }

        try self.tasks.append(self.allocator, .{
            .id = id,
            .expression = expr_copy,
            .result = result,
            .state = state,
            .thread = null,
        });

        return id;
    }

    pub fn getTask(self: *GreenScheduler, id: u32) ?*GreenTask {
        for (self.tasks.items) |*t| {
            if (t.id == id) return t;
        }
        return null;
    }

    pub fn await(self: *GreenScheduler, id: u32) ?[]const u8 {
        const task = self.getTask(id) orelse return null;
        if (task.thread) |t| {
            t.join();
            task.thread = null;
        }
        return task.result;
    }

    pub fn formatStatus(self: *GreenScheduler, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        const w = buf.writer(allocator);
        try w.writeAll("  \xe2\x95\x90\xe2\x95\x90\xe2\x95\x90 Green Threads \xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\n");

        var running: u32 = 0;
        var done: u32 = 0;
        var failed: u32 = 0;

        for (self.tasks.items) |t| {
            const status_icon: []const u8 = switch (t.state) {
                .pending => "\xe2\x8f\xb3", // ⏳
                .running => "\xf0\x9f\x94\x84", // 🔄
                .done => "\xe2\x9c\x93", // ✓
                .failed => "\xe2\x9c\x97", // ✗
            };
            const result_str = t.result orelse "(...)";
            const short_expr = if (t.expression.len > 30) t.expression[0..30] else t.expression;
            try std.fmt.format(w, "  GT-{d} {s} {s}", .{ t.id, status_icon, short_expr });
            if (t.state == .done) {
                const short_result = if (result_str.len > 30) result_str[0..30] else result_str;
                try std.fmt.format(w, " \xe2\x86\x92 {s}", .{short_result});
            }
            try w.writeAll("\n");

            switch (t.state) {
                .running => running += 1,
                .done => done += 1,
                .failed => failed += 1,
                else => {},
            }
        }
        try std.fmt.format(w, "\n  Total: {d} | Running: {d} | Done: {d} | Failed: {d}\n", .{
            self.tasks.items.len, running, done, failed,
        });
        return buf.toOwnedSlice(allocator);
    }
};
