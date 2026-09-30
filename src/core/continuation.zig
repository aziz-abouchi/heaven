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

// ─────────────────────────────────────────────────────────────
// Prototype 3a-2 — captureCont / throwCont
// ─────────────────────────────────────────────────────────────
//
// Modele V2 : la pile d'execution est simulee par une CaptureStack
// de frames symboliques. Chaque frame porte :
//   - prompt   : sous quel prompt elle vit
//   - position : position opaque dans l'expression (sera un PC dans
//                le vrai runtime)
//   - env      : identifiant opaque de l'environnement capture
//                (sera un Id dans le Store reel)
//
// captureCont copie le segment depuis le sommet jusqu'a un prompt
// cible, dans une Continuation. throwCont restaure ce segment sur
// la pile courante, en preservant les frames sous le prompt cible.
//
// Ce modele ne gere PAS encore :
//   - l'evaluation reelle (side effects, allocation)
//   - la liaison avec engine_expr.evaluate
//   - le scheduler
// Ces etapes sont 3a-3.

/// Une frame d'execution.
pub const Frame = struct {
    prompt: Prompt,
    position: u32,
    env: u64,
};

/// Pile d'execution simulee. Le sommet est le dernier element.
pub const CaptureStack = struct {
    items: std.ArrayList(Frame),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CaptureStack {
        return .{ .items = .empty, .allocator = allocator };
    }

    pub fn deinit(self: *CaptureStack) void {
        self.items.deinit(self.allocator);
    }

    pub fn push(self: *CaptureStack, frame: Frame) !void {
        try self.items.append(self.allocator, frame);
    }

    pub fn pop(self: *CaptureStack) ?Frame {
        return self.items.pop();
    }

    pub fn depth(self: *const CaptureStack) u32 {
        return @intCast(self.items.items.len);
    }

    pub fn top(self: *const CaptureStack) ?Frame {
        if (self.items.items.len == 0) return null;
        return self.items.items[self.items.items.len - 1];
    }

    /// Retourne l'index (depuis la base) du frame d'ENTREE dans le
    /// prompt cible : le plus bas du bloc contigu de frames ayant ce
    /// prompt. C'est ce frame qui sert de marqueur pour captureCont
    /// et throwCont.
    pub fn findPrompt(self: *const CaptureStack, prompt: Prompt) ?usize {
        for (self.items.items, 0..) |frame, i| {
            if (frame.prompt == prompt) return i;
        }
        return null;
    }
};

/// Segment capture entre le sommet et un prompt inclus.
pub const Continuation = struct {
    /// Frames capturees, ordonnees du bas vers le haut (comme la
    /// pile au moment de la capture).
    frames: []Frame,
    /// Prompt cible de la capture. La reprise arretera ici.
    target: Prompt,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Continuation) void {
        self.allocator.free(self.frames);
    }

    pub fn depth(self: *const Continuation) u32 {
        return @intCast(self.frames.len);
    }
};

/// Capture les frames depuis le sommet jusqu'au prompt cible
/// (inclus). Le prompt doit exister dans la pile.
///
/// Ne modifie pas la pile source : la capture est non destructive.
pub fn captureCont(
    stack: *const CaptureStack,
    target: Prompt,
    allocator: std.mem.Allocator,
) !Continuation {
    const idx = stack.findPrompt(target) orelse return error.PromptNotFound;
    const len = stack.items.items.len - idx;
    const frames = try allocator.alloc(Frame, len);
    errdefer allocator.free(frames);
    @memcpy(frames, stack.items.items[idx..]);
    return .{ .frames = frames, .target = target, .allocator = allocator };
}

/// Restaure les frames d'une continuation sur la pile courante.
///
/// Semantique : la pile est tronquee jusqu'au prompt cible
/// (exclu), puis les frames de k sont ajoutees au-dessus.
/// Les frames originales sous le prompt cible sont preservees.
///
/// Apres throwCont, stack.depth() == idx_prompt + k.depth().
pub fn throwCont(stack: *CaptureStack, k: *const Continuation) !void {
    const idx = stack.findPrompt(k.target) orelse return error.PromptNotFound;
    // Tronquer jusqu'au prompt (exclu : on garde les frames
    // strictement en dessous).
    stack.items.shrinkRetainingCapacity(idx);
    // Re-empiler les frames de k.
    for (k.frames) |frame| {
        try stack.push(frame);
    }
}

// ─────────────────────────────────────────────────────────────
// Tests 3a-2
// ─────────────────────────────────────────────────────────────

test "captureCont : prompt introuvable" {
    var stack = CaptureStack.init(std.testing.allocator);
    defer stack.deinit();
    try std.testing.expectError(
        error.PromptNotFound,
        captureCont(&stack, 42, std.testing.allocator),
    );
}

test "captureCont : capture une seule frame" {
    var stack = CaptureStack.init(std.testing.allocator);
    defer stack.deinit();
    try stack.push(.{ .prompt = 1, .position = 0, .env = 100 });
    try stack.push(.{ .prompt = 1, .position = 5, .env = 200 });
    try stack.push(.{ .prompt = 1, .position = 10, .env = 300 });

    var k = try captureCont(&stack, 1, std.testing.allocator);
    defer k.deinit();

    // Le prompt 1 est en bas -> capture toute la pile.
    try std.testing.expectEqual(@as(u32, 3), k.depth());
    try std.testing.expectEqual(@as(Prompt, 1), k.target);
    try std.testing.expectEqual(@as(u32, 0), k.frames[0].position);
    try std.testing.expectEqual(@as(u32, 10), k.frames[2].position);
}

test "captureCont : ne capture que le sommet" {
    var stack = CaptureStack.init(std.testing.allocator);
    defer stack.deinit();
    // Prompt "externe" en bas
    try stack.push(.{ .prompt = 1, .position = 0, .env = 100 });
    // Prompt cible au milieu
    try stack.push(.{ .prompt = 2, .position = 5, .env = 200 });
    // Frames du prompt 2 au-dessus
    try stack.push(.{ .prompt = 2, .position = 10, .env = 300 });
    try stack.push(.{ .prompt = 2, .position = 15, .env = 400 });

    var k = try captureCont(&stack, 2, std.testing.allocator);
    defer k.deinit();

    // Seules les frames du prompt 2 sont capturees (les 3 dernieres).
    try std.testing.expectEqual(@as(u32, 3), k.depth());
    try std.testing.expectEqual(@as(u64, 200), k.frames[0].env);
    try std.testing.expectEqual(@as(u64, 400), k.frames[2].env);
}

test "throwCont : restaure apres troncature" {
    var stack = CaptureStack.init(std.testing.allocator);
    defer stack.deinit();
    try stack.push(.{ .prompt = 1, .position = 0, .env = 100 });
    try stack.push(.{ .prompt = 1, .position = 5, .env = 200 });

    // Capture l'etat initial
    var k = try captureCont(&stack, 1, std.testing.allocator);
    defer k.deinit();

    // Modifie la pile : ajoute une frame en plus
    try stack.push(.{ .prompt = 1, .position = 10, .env = 300 });
    try std.testing.expectEqual(@as(u32, 3), stack.depth());

    // Restaure
    try throwCont(&stack, &k);
    try std.testing.expectEqual(@as(u32, 2), stack.depth());
    try std.testing.expectEqual(@as(u64, 100), stack.items.items[0].env);
    try std.testing.expectEqual(@as(u64, 200), stack.items.items[1].env);
}

test "throwCont : preserve les frames sous le prompt" {
    var stack = CaptureStack.init(std.testing.allocator);
    defer stack.deinit();
    // Prompt externe 1
    try stack.push(.{ .prompt = 1, .position = 0, .env = 100 });
    // Prompt cible 2
    try stack.push(.{ .prompt = 2, .position = 5, .env = 200 });

    var k = try captureCont(&stack, 2, std.testing.allocator);
    defer k.deinit();

    // Modifie : ajoute des frames au-dessus du prompt 2
    try stack.push(.{ .prompt = 2, .position = 10, .env = 300 });
    try stack.push(.{ .prompt = 2, .position = 15, .env = 400 });
    try std.testing.expectEqual(@as(u32, 4), stack.depth());

    // Restaure
    try throwCont(&stack, &k);

    // La frame du prompt 1 est preservee
    try std.testing.expectEqual(@as(u32, 2), stack.depth());
    try std.testing.expectEqual(@as(Prompt, 1), stack.items.items[0].prompt);
    try std.testing.expectEqual(@as(Prompt, 2), stack.items.items[1].prompt);
    try std.testing.expectEqual(@as(u64, 200), stack.items.items[1].env);
}

test "throwCont : continuations imbriquees" {
    var stack = CaptureStack.init(std.testing.allocator);
    defer stack.deinit();
    try stack.push(.{ .prompt = 1, .position = 0, .env = 100 });
    try stack.push(.{ .prompt = 1, .position = 5, .env = 200 });

    var k1 = try captureCont(&stack, 1, std.testing.allocator);
    defer k1.deinit();

    // Nouvelle frame, nouvelle capture (au-dessus)
    try stack.push(.{ .prompt = 1, .position = 10, .env = 300 });
    var k2 = try captureCont(&stack, 1, std.testing.allocator);
    defer k2.deinit();

    try std.testing.expectEqual(@as(u32, 2), k1.depth());
    try std.testing.expectEqual(@as(u32, 3), k2.depth());

    // Restaurer k1 puis k2
    try throwCont(&stack, &k1);
    try std.testing.expectEqual(@as(u32, 2), stack.depth());
    try throwCont(&stack, &k2);
    try std.testing.expectEqual(@as(u32, 3), stack.depth());
    try std.testing.expectEqual(@as(u64, 300), stack.items.items[2].env);
}
