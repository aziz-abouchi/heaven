// src/kernel/strategy.zig
const std = @import("std");
const TTA = @import("tta.zig").TTA; // Adaptez le chemin
const KnowledgeBase = @import("kb.zig").KnowledgeBase; // Adaptez le chemin

pub const Plan = struct {
    steps: []const Step,
};

pub const Step = struct {
    engine: []const u8,
    op: []const u8,
};

pub const Strategy = struct {
    name: []const u8,
    match: *const fn (source: TTA, target: TTA, kb: *KnowledgeBase) bool,
    build: *const fn (allocator: std.mem.Allocator, source: TTA, target: TTA) anyerror!Plan,
};

// C'est ici que vous enregistrez vos stratégies
pub const REGISTRY = [_]Strategy{
    .{ .name = "arithmetic", .match = matchArithmetic, .build = buildArithmeticPlan },
    // Ajoutez les futures stratégies ici
};

// Vos fonctions de dispatch
fn matchArithmetic(source: TTA, target: TTA, kb: *KnowledgeBase) bool {
    // Logique de détection
    return true; 
}

fn buildArithmeticPlan(allocator: std.mem.Allocator, source: TTA, target: TTA) anyerror!Plan {
    // Logique de construction
    return Plan{ .steps = &.{} };
}
