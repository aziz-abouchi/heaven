const std = @import("std");

/// Types de tâches que le swarm peut résoudre
pub const TaskKind = enum(u8) {
    solve = 1, // Résoudre une équation
    simplify = 2, // Simplifier une expression
    prove = 3, // Prouver une égalité
    derive = 4, // Dériver
    integrate = 5, // Intégrer
    optimize = 6, // Choisir le meilleur algorithme
    fact_query = 7, // Chercher un fait Prolog
    custom = 255, // Tâche custom
};

pub const TaskStatus = enum(u8) {
    pending = 0,
    claimed = 1,
    solved = 2,
    failed = 3,
    timeout = 4,
};

/// Une tâche distribuée dans le swarm
pub const SwarmTask = struct {
    magic: u32 = 0x5441534B, // "TASK"
    id: u64, // ID unique
    kind: TaskKind,
    origin_port: u16, // Bob qui demande
    expr: [256]u8, // Expression à traiter
    expr_len: u16,
    status: TaskStatus,
    timestamp: i64,

    pub fn init(kind: TaskKind, origin: u16, expression: []const u8) SwarmTask {
        var task = SwarmTask{
            .id = std.crypto.random.int(u64),
            .kind = kind,
            .origin_port = origin,
            .expr = undefined,
            .expr_len = @intCast(@min(expression.len, 256)),
            .status = .pending,
            .timestamp = std.time.timestamp(),
        };
        @memcpy(task.expr[0..task.expr_len], expression[0..task.expr_len]);
        return task;
    }

    pub fn getExpr(self: *const SwarmTask) []const u8 {
        return self.expr[0..self.expr_len];
    }
};

/// Résultat renvoyé par un Bob qui a résolu
pub const SwarmResult = struct {
    magic: u32 = 0x52455355, // "RESU"
    task_id: u64, // Réfère au SwarmTask.id
    solver_port: u16, // Bob qui a résolu
    result: [256]u8,
    result_len: u16,
    confidence: f32, // 0.0 à 1.0
    status: TaskStatus,

    pub fn init(task_id: u64, solver: u16, res: []const u8, confidence: f32) SwarmResult {
        var r = SwarmResult{
            .task_id = task_id,
            .solver_port = solver,
            .result = undefined,
            .result_len = @intCast(@min(res.len, 256)),
            .confidence = confidence,
            .status = .solved,
        };
        @memcpy(r.result[0..r.result_len], res[0..r.result_len]);
        return r;
    }

    pub fn getResult(self: *const SwarmResult) []const u8 {
        return self.result[0..self.result_len];
    }
};

/// Packet swarm pour le transport UDP
pub const SwarmPacket = struct {
    magic: u32 = 0x5357524D, // "SWRM"
    kind: PacketKind,
    payload_len: u16,

    pub const PacketKind = enum(u8) {
        task_broadcast = 1, // Diffuser une tâche
        task_claim = 2, // "Je prends cette tâche"
        task_result = 3, // Résultat
        task_cancel = 4, // Annuler
        heartbeat = 5, // Heartbeat swarm
    };
};

pub const WsSwarmMessage = struct {
    type: []const u8, // "TASK" ou "RESULT"
    task_type: []const u8, // "solve", "simplify", "derive", "prove"
    msg_id: u64,
    origin_bob: u16,
    payload: []const u8,
};
