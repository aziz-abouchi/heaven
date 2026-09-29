//! Prototype 3a-1 — Prompts délimités (voir docs/spec/_continuations.md).
//!
//! Un prompt est un marqueur de frontière dans la pile de continuations.
//! Les `captureCont` (3a-2) captureront jusqu'au prompt le plus proche,
//! pas au-delà. Aucune sémantique de capture ici : juste la pile.

const std = @import("std");

/// Identifiant unique d'un prompt. Monotone croissant pour éviter
/// toute confusion avec des ids recyclés entre pop/push.
pub const Prompt = u32;

pub const PromptStack = struct {
    items: std.ArrayList(Prompt),
    next_id: Prompt,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PromptStack {
        return .{
            .items = .empty,
            .next_id = 1, // 0 réservé = pas de prompt
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PromptStack) void {
        self.items.deinit(self.allocator);
    }

    /// Ouvre un prompt. Retourne son id unique.
    pub fn push(self: *PromptStack) !Prompt {
        const id = self.next_id;
        self.next_id += 1;
        try self.items.append(self.allocator, id);
        return id;
    }

    /// Ferme le prompt au sommet. Retourne son id, ou null si vide.
    pub fn pop(self: *PromptStack) ?Prompt {
        return self.items.pop();
    }

    /// Retourne l'id du prompt au sommet, sans le fermer.
    pub fn top(self: *const PromptStack) ?Prompt {
        if (self.items.items.len == 0) return null;
        return self.items.items[self.items.items.len - 1];
    }

    pub fn depth(self: *const PromptStack) u32 {
        return @intCast(self.items.items.len);
    }
};

test "prompt stack: push/pop LIFO" {
    var ps = PromptStack.init(std.testing.allocator);
    defer ps.deinit();
    const p1 = try ps.push();
    const p2 = try ps.push();
    const p3 = try ps.push();
    // LIFO : p3 sort en premier, puis p2, puis p1
    try std.testing.expectEqual(p3, ps.pop().?);
    try std.testing.expectEqual(p2, ps.pop().?);
    try std.testing.expectEqual(p1, ps.pop().?);
    try std.testing.expectEqual(@as(?Prompt, null), ps.pop());
}

test "prompt stack: ids uniques monotones" {
    var ps = PromptStack.init(std.testing.allocator);
    defer ps.deinit();
    const a = try ps.push();
    _ = ps.pop();
    const b = try ps.push();
    try std.testing.expect(b > a);
}

test "prompt stack: top et depth" {
    var ps = PromptStack.init(std.testing.allocator);
    defer ps.deinit();
    try std.testing.expectEqual(@as(?Prompt, null), ps.top());
    try std.testing.expectEqual(@as(u32, 0), ps.depth());
    const p = try ps.push();
    try std.testing.expectEqual(p, ps.top().?);
    try std.testing.expectEqual(@as(u32, 1), ps.depth());
    _ = try ps.push();
    try std.testing.expectEqual(@as(u32, 2), ps.depth());
    _ = ps.pop();
    try std.testing.expectEqual(p, ps.top().?);
}
