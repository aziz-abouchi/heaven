const std = @import("std");
const net = @import("../../scut/network.zig");
const proto = @import("../../scut/swarm/protocol_swarm.zig");
const platform = @import("platform");

/// Global inbox for network thread to deposit tasks
pub var global_inbox: ?*std.ArrayListUnmanaged(proto.SwarmTask) = null;
/// Global results for network thread to deposit results
pub var global_results: ?*std.ArrayListUnmanaged(proto.SwarmResult) = null;

pub const SwarmNode = struct {
    id: u64,
    port: u16,
    energy: f32,
    load: f32,
    tasks_solved: u32,
};

pub const SwarmRuntime = struct {
    allocator: std.mem.Allocator,
    self_port: u16,
    pending_tasks: std.ArrayListUnmanaged(proto.SwarmTask),
    results: std.ArrayListUnmanaged(proto.SwarmResult),
    task_log: std.ArrayListUnmanaged(TaskLogEntry),

    pub const TaskLogEntry = struct {
        task_id: u64,
        kind: proto.TaskKind,
        expr: []const u8,
        result: ?[]const u8,
        solver_port: u16,
        status: proto.TaskStatus,
        time_ms: i64,
    };

    pub fn init(allocator: std.mem.Allocator, port: u16) SwarmRuntime {
        return .{
            .allocator = allocator,
            .self_port = port,
            .pending_tasks = .{},
            .results = .{},
            .task_log = .{},
        };
    }

    pub fn deinit(self: *SwarmRuntime) void {
        self.pending_tasks.deinit(self.allocator);
        self.results.deinit(self.allocator);
        self.task_log.deinit(self.allocator);
    }

    /// Créer et broadcaster une tâche au swarm
    pub fn broadcastTask(self: *SwarmRuntime, kind: proto.TaskKind, expression: []const u8) !u64 {
        const task = proto.SwarmTask.init(kind, self.self_port, expression);
        try self.pending_tasks.append(self.allocator, task);

        // Broadcast via UDP à tous les peers
        const payload = std.mem.asBytes(&task);
        for (net.known_peers.items) |peer| {
            if (peer.address.getPort() == self.self_port) continue;
            net.sendTo(peer.address, payload) catch continue;
        }

        platform.debug.print("[SWARM] Tâche broadcast: {s} ({s}) → {d} peers\n", .{
            expression,
            @tagName(kind),
            net.known_peers.items.len,
        });

        return task.id;
    }

    /// Recevoir et tenter de résoudre une tâche
    pub fn tryResolve(self: *SwarmRuntime, task: proto.SwarmTask, heaven: anytype) ?proto.SwarmResult {
        const expr = task.getExpr();
        platform.debug.print("[SWARM] Tentative résolution: {s} (de Bob:{d})\n", .{ expr, task.origin_port });

        const result_str: ?[]const u8 = switch (task.kind) {
            .solve => heaven.solve(expr, "x") catch null,
            .simplify => heaven.simplify(expr) catch null,
            .derive => heaven.derive(expr, "x") catch null,
            .integrate => heaven.integrate(expr, "x") catch null,
            .prove => blk: {
                if (std.mem.indexOfScalar(u8, expr, '=')) |eq| {
                    const lhs = std.mem.trim(u8, expr[0..eq], " ");
                    const rhs = std.mem.trim(u8, expr[eq + 1 ..], " ");
                    // Try direct simplification
                    const ls = heaven.simplify(lhs) catch lhs;
                    const rs = heaven.simplify(rhs) catch rhs;
                    if (std.mem.eql(u8, ls, rs)) {
                        break :blk self.allocator.dupe(u8, "\xe2\x9c\x93 proved by simplification") catch null;
                    }
                    // Try commutativity: a+b vs b+a
                    const op_a = std.mem.indexOfAny(u8, lhs, "+-");
                    const op_b = std.mem.indexOfAny(u8, rhs, "+-");
                    if (op_a != null and op_b != null) {
                        const a_l = std.mem.trim(u8, lhs[0..op_a.?], " ");
                        const a_r = std.mem.trim(u8, lhs[op_a.? + 1 ..], " ");
                        const b_l = std.mem.trim(u8, rhs[0..op_b.?], " ");
                        const b_r = std.mem.trim(u8, rhs[op_b.? + 1 ..], " ");
                        if (lhs[op_a.?] == rhs[op_b.?]) {
                            if (std.mem.eql(u8, a_l, b_r) and std.mem.eql(u8, a_r, b_l)) {
                                break :blk self.allocator.dupe(u8, "\xe2\x9c\x93 proved by commutativity") catch null;
                            }
                        }
                    }
                    // Try reflexivity
                    if (std.mem.eql(u8, lhs, rhs)) {
                        break :blk self.allocator.dupe(u8, "\xe2\x9c\x93 proved by reflexivity") catch null;
                    }
                }
                break :blk null;
            },
            else => heaven.eval(expr) catch null,
        };

        if (result_str) |res| {
            // platform.debug.print("[SWARM] ✓ Résolu: {s} → {s}\n", .{ expr, res });
            const sr = proto.SwarmResult.init(task.id, self.self_port, res, 1.0);

            // Log
            self.task_log.append(self.allocator, .{
                .task_id = task.id,
                .kind = task.kind,
                .expr = self.allocator.dupe(u8, expr) catch "",
                .result = self.allocator.dupe(u8, res) catch null,
                .solver_port = self.self_port,
                .status = .solved,
                .time_ms = std.time.milliTimestamp() - task.timestamp,
            }) catch {};

            return sr;
        }

        // platform.debug.print("[SWARM] ✗ Pas résolu: {s}\n", .{expr});
        return null;
    }

    /// Recevoir un résultat d'un autre Bob
    pub fn receiveResult(self: *SwarmRuntime, result: proto.SwarmResult) void {
        // Vérifier si on attend ce résultat
        for (self.pending_tasks.items, 0..) |*task, idx| {
            if (task.id == result.task_id) {
                task.status = .solved;
                self.results.append(self.allocator, result) catch {};

                platform.debug.print("[SWARM] Résultat reçu de Bob:{d}: {s}\n", .{
                    result.solver_port,
                    result.getResult(),
                });

                // Remove from pending
                _ = self.pending_tasks.orderedRemove(idx);
                return;
            }
        }
    }

    /// Récupérer le résultat d'une tâche en attente
    pub fn getResult(self: *SwarmRuntime, task_id: u64) ?[]const u8 {
        for (self.results.items) |r| {
            if (r.task_id == task_id) return r.getResult();
        }
        return null;
    }

    /// Statistiques du swarm
    pub fn formatStats(self: *SwarmRuntime, allocator: std.mem.Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        const w = buf.writer(allocator);
        try w.writeAll("  \xe2\x95\x90\xe2\x95\x90\xe2\x95\x90 Swarm Status \xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\n");
        try std.fmt.format(w, "  Bob:{d} | Peers: {d}\n", .{ self.self_port, net.known_peers.items.len });
        try std.fmt.format(w, "  Pending tasks: {d}\n", .{self.pending_tasks.items.len});
        try std.fmt.format(w, "  Completed: {d}\n", .{self.task_log.items.len});

        if (self.task_log.items.len > 0) {
            try w.writeAll("\n  Recent:\n");
            const start = if (self.task_log.items.len > 5) self.task_log.items.len - 5 else 0;
            for (self.task_log.items[start..]) |entry| {
                const res = entry.result orelse "(failed)";
                try std.fmt.format(w, "    [{s}] {s} \xe2\x86\x92 {s} (Bob:{d})\n", .{
                    @tagName(entry.kind), entry.expr, res, entry.solver_port,
                });
            }
        }
        return buf.toOwnedSlice(allocator);
    }
};
