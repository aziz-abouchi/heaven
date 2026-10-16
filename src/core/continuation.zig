//! Prototype 3a-1 — Prompts délimités (voir docs/spec/_continuations.md).
//!
//! Un prompt est un marqueur de frontière dans la pile de continuations.
//! Les `captureCont` (3a-2) captureront jusqu'au prompt le plus proche,
//! pas au-delà. Aucune sémantique de capture ici : juste la pile.

const std = @import("std");
const expr = @import("expr");

/// A3B2E : Env bidon pour les tests. Ne contient rien, jamais
/// dereference, jamais unref (voir plus bas) — sert uniquement a
/// satisfaire le type *expr.Env des Frames de test.
var dummy_env_storage: ?*expr.Env = null;

fn dummyEnv() *expr.Env {
    if (dummy_env_storage == null) {
        dummy_env_storage = expr.Env.create(std.heap.page_allocator) catch unreachable;
    }
    return dummy_env_storage.?;
}

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
/// A3B2 : nature de l'evaluation en cours au point de push.
/// Permet de reconstituer l'etat pour la reprise exacte.
pub const FrameKind = enum(u8) {
    unknown = 0,
    lit_sym,           // .lit ou .sym : feuille
    apply_op,          // .apply : evaluation des args
    lambda_body,       // .lambda : evaluation du corps
    bind_body,         // .bind : let x = v in body
    if_branch,         // (if p a b) : on evalue p, a ou b
    seq,               // (seq a b) : sequence
    other,
};

pub const Frame = struct {
    prompt: Prompt,
    position: u32,
    env: *expr.Env,
    /// A3B1 : id de l'expression evaluee (0 = inconnu).
    id: u64 = 0,
    /// A3B2 : nature de l'evaluation (pour resume).
    kind: FrameKind = .unknown,
    /// A3B2C-R2 : nombre d'args deja evalues dans le .apply courant.
    /// On ne stocke PAS les valeurs (re-eval au resume, args supposes
    /// purs — voir _a3b_resume_strategy.md).
    args_done_len: u8 = 0,
    /// A3B2C : nombre total d'args a evaluer (brut, inclut op_id).
    args_left: u32 = 0,
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

    /// A3B2C-R2 : version mutable pour mettre a jour args_done_len
    /// en place depuis les boucles d'eval d'args (cf. 2c-4).
    pub fn topMut(self: *CaptureStack) ?*Frame {
        if (self.items.items.len == 0) return null;
        return &self.items.items[self.items.items.len - 1];
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
        // A3B2E : relache les refs prises par captureCont.
        for (self.frames) |fr| fr.env.unref();
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
    // A3B2E : la Continuation possede ses frames -> ref sur chaque Env.
    for (frames) |fr| fr.env.ref();
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
        // A3B2E : la pile prend une ref, elle la relachera au pop.
        frame.env.ref();
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
    try stack.push(.{ .prompt = 1, .position = 0, .env = dummyEnv() });
    try stack.push(.{ .prompt = 1, .position = 5, .env = dummyEnv() });
    try stack.push(.{ .prompt = 1, .position = 10, .env = dummyEnv() });

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
    try stack.push(.{ .prompt = 1, .position = 0, .env = dummyEnv() });
    // Prompt cible au milieu
    try stack.push(.{ .prompt = 2, .position = 5, .env = dummyEnv() });
    // Frames du prompt 2 au-dessus
    try stack.push(.{ .prompt = 2, .position = 10, .env = dummyEnv() });
    try stack.push(.{ .prompt = 2, .position = 15, .env = dummyEnv() });

    var k = try captureCont(&stack, 2, std.testing.allocator);
    defer k.deinit();

    // Seules les frames du prompt 2 sont capturees (les 3 dernieres).
    try std.testing.expectEqual(@as(u32, 3), k.depth());
    _ = k.frames[0].env; // A3B2E : .env est un *Env desormais
    _ = k.frames[2].env; // A3B2E : .env est un *Env desormais
}

test "throwCont : restaure apres troncature" {
    var stack = CaptureStack.init(std.testing.allocator);
    defer stack.deinit();
    try stack.push(.{ .prompt = 1, .position = 0, .env = dummyEnv() });
    try stack.push(.{ .prompt = 1, .position = 5, .env = dummyEnv() });

    // Capture l'etat initial
    var k = try captureCont(&stack, 1, std.testing.allocator);
    defer k.deinit();

    // Modifie la pile : ajoute une frame en plus
    try stack.push(.{ .prompt = 1, .position = 10, .env = dummyEnv() });
    try std.testing.expectEqual(@as(u32, 3), stack.depth());

    // Restaure
    try throwCont(&stack, &k);
    try std.testing.expectEqual(@as(u32, 2), stack.depth());
    _ = stack.items.items[0].env; // A3B2E : .env est un *Env desormais
    _ = stack.items.items[1].env; // A3B2E : .env est un *Env desormais
}

test "throwCont : preserve les frames sous le prompt" {
    var stack = CaptureStack.init(std.testing.allocator);
    defer stack.deinit();
    // Prompt externe 1
    try stack.push(.{ .prompt = 1, .position = 0, .env = dummyEnv() });
    // Prompt cible 2
    try stack.push(.{ .prompt = 2, .position = 5, .env = dummyEnv() });

    var k = try captureCont(&stack, 2, std.testing.allocator);
    defer k.deinit();

    // Modifie : ajoute des frames au-dessus du prompt 2
    try stack.push(.{ .prompt = 2, .position = 10, .env = dummyEnv() });
    try stack.push(.{ .prompt = 2, .position = 15, .env = dummyEnv() });
    try std.testing.expectEqual(@as(u32, 4), stack.depth());

    // Restaure
    try throwCont(&stack, &k);

    // La frame du prompt 1 est preservee
    try std.testing.expectEqual(@as(u32, 2), stack.depth());
    try std.testing.expectEqual(@as(Prompt, 1), stack.items.items[0].prompt);
    try std.testing.expectEqual(@as(Prompt, 2), stack.items.items[1].prompt);
    _ = stack.items.items[1].env; // A3B2E : .env est un *Env desormais
}

test "throwCont : continuations imbriquees" {
    var stack = CaptureStack.init(std.testing.allocator);
    defer stack.deinit();
    try stack.push(.{ .prompt = 1, .position = 0, .env = dummyEnv() });
    try stack.push(.{ .prompt = 1, .position = 5, .env = dummyEnv() });

    var k1 = try captureCont(&stack, 1, std.testing.allocator);
    defer k1.deinit();

    // Nouvelle frame, nouvelle capture (au-dessus)
    try stack.push(.{ .prompt = 1, .position = 10, .env = dummyEnv() });
    var k2 = try captureCont(&stack, 1, std.testing.allocator);
    defer k2.deinit();

    try std.testing.expectEqual(@as(u32, 2), k1.depth());
    try std.testing.expectEqual(@as(u32, 3), k2.depth());

    // Restaurer k1 puis k2
    try throwCont(&stack, &k1);
    try std.testing.expectEqual(@as(u32, 2), stack.depth());
    try throwCont(&stack, &k2);
    try std.testing.expectEqual(@as(u32, 3), stack.depth());
    _ = stack.items.items[2].env; // A3B2E : .env est un *Env desormais
}


test "A3B2C : args_done_len survit a captureCont" {
    const allocator = std.testing.allocator;
    var cs = CaptureStack.init(allocator);
    defer cs.deinit();
    // Frame sous le prompt : ne doit PAS etre capturee.
    try cs.push(.{ .prompt = 0, .position = 0, .env = dummyEnv(), .id = 1 });
    // Frame prompt : .apply_op avec 3 args deja evalues sur 5.
    try cs.push(.{
        .prompt = 42,
        .position = 1,
        .env = dummyEnv(),
        .id = 2,
        .kind = .apply_op,
        .args_done_len = 3,
        .args_left = 5,
    });
    // Frame au-dessus du prompt.
    try cs.push(.{ .prompt = 42, .position = 2, .env = dummyEnv(), .id = 3, .kind = .lit_sym });

    var cont = try captureCont(&cs, 42, allocator);
    defer cont.deinit();

    try std.testing.expectEqual(@as(u32, 2), cont.depth());
    const f0 = cont.frames[0];
    try std.testing.expectEqual(@as(u64, 2), f0.id);
    try std.testing.expectEqual(FrameKind.apply_op, f0.kind);
    try std.testing.expectEqual(@as(u8, 3), f0.args_done_len);
    try std.testing.expectEqual(@as(u32, 5), f0.args_left);
}

test "A3B1 : Frame porte id" {
    const allocator = std.testing.allocator;
    var cs = CaptureStack.init(allocator);
    defer cs.deinit();
    try cs.push(.{ .prompt = 0, .position = 1, .env = dummyEnv(), .id = 42 });
    const f = cs.pop() orelse unreachable;
    try std.testing.expectEqual(@as(u64, 42), f.id);
    try std.testing.expectEqual(@as(u32, 1), f.position);
}
