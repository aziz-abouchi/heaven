const std = @import("std");
const Allocator = std.mem.Allocator;
const ProofEnv = @import("proof").ProofEnv;
const expr = @import("expr");
const platform = @import("platform");

pub const Tactic = enum {
    intro, // Introduire les variables dans le contexte
    normalize, // Forme canonique via le CAS
    simplify, // Saturation E-graph avec les règles de la KB
    exact, // Clôture de la preuve (lhs == rhs après simplification)
    induction, // Induction sur Nat
};

pub const Skill = struct {
    name: []const u8,
    tactics: []const Tactic,
};

const BUILTIN_SKILLS = [_]Skill{
    .{ .name = "algebra", .tactics = &.{ .normalize, .simplify, .exact } },
    .{ .name = "induction", .tactics = &.{ .intro, .normalize, .induction } },
    .{ .name = "trivial", .tactics = &.{.exact} },
};

pub const ApplyResult = struct {
    proved: bool,
    tactics_run: u32,
    tactic_log: []const u8,
};

pub const SkillRegistry = struct {
    allocator: Allocator,
    custom: std.StringHashMapUnmanaged(Skill) = .{},

    pub fn init(allocator: Allocator) SkillRegistry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *SkillRegistry) void {
        var it = self.custom.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*); // libère le nom
            self.allocator.free(entry.value_ptr.*.tactics); // libère les tactiques
            // value_ptr.*.name == key_ptr.* donc déjà libéré
        }
        self.custom.deinit(self.allocator);
    }

    pub fn register(self: *SkillRegistry, name: []const u8, tactics: []const Tactic) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        const owned_tactics = try self.allocator.dupe(Tactic, tactics);
        try self.custom.put(self.allocator, owned_name, .{
            .name = owned_name, // même pointeur que la clé
            .tactics = owned_tactics,
        });
    }
    pub fn get(self: *const SkillRegistry, name: []const u8) ?Skill {
        // Cherche dans les customs d'abord
        if (self.custom.get(name)) |s| return s;
        // Puis dans les builtins
        for (BUILTIN_SKILLS) |s| {
            if (std.mem.eql(u8, s.name, name)) return s;
        }
        return null;
    }

    /// Applique un skill sur un théorème nommé.
    /// engine et store sont anytype pour éviter les dépendances circulaires.
    pub fn apply(
        self: *const SkillRegistry,
        skill_name: []const u8,
        theorem_name: []const u8,
        induction_var: []const u8,
        proofs: *ProofEnv,
        engine: anytype,
        heaven: anytype,
        store: *expr.Store,
    ) !ApplyResult {
        const skill = self.get(skill_name) orelse {
            // platform.debug.print("[SKILL] Skill inconnu: {s}\n", .{skill_name});
            return ApplyResult{ .proved = false, .tactics_run = 0, .tactic_log = "skill not found" };
        };

        var tactics_run: u32 = 0;
        var proved = false;

        for (skill.tactics) |tactic| {
            tactics_run += 1;
            switch (tactic) {
                .intro => {
                    // platform.debug.print("[SKILL] [{s}] intro\n", .{skill_name});
                },
                .normalize => {
                    // platform.debug.print("[SKILL] [{s}] normalize\n", .{skill_name});
                },
                .simplify => {
                    // platform.debug.print("[SKILL] [{s}] simplify\n", .{skill_name});
                    proved = try proofs.verifyBySimplify(theorem_name, heaven);
                    if (proved) break;
                },
                .exact => {
                    // platform.debug.print("[SKILL] [{s}] exact\n", .{skill_name});
                    proved = try proofs.verifyByEval(theorem_name, engine, store);
                    if (proved) break;
                },
                .induction => {
                    // platform.debug.print("[SKILL] [{s}] induction\n", .{skill_name});
                    // Variable d'induction par défaut : "n"
                    proved = try proofs.verifyByInduction(theorem_name, induction_var, engine, heaven, store);
                    if (proved) break;
                },
            }
        }

        return ApplyResult{
            .proved = proved,
            .tactics_run = tactics_run,
            .tactic_log = if (proved) "proved" else "unproved",
        };
    }
};

test "SkillRegistry — builtin algebra" {
    const allocator = std.testing.allocator;
    const registry = SkillRegistry.init(allocator);

    const skill = registry.get("algebra").?;
    try std.testing.expectEqualStrings("algebra", skill.name);
    try std.testing.expect(skill.tactics.len == 3);
}

test "SkillRegistry — custom skill" {
    const allocator = std.testing.allocator;
    var registry = SkillRegistry.init(allocator);
    defer registry.deinit();

    try registry.register("my_skill", &.{ .intro, .exact });
    const skill = registry.get("my_skill").?;
    try std.testing.expectEqualStrings("my_skill", skill.name);
    try std.testing.expect(skill.tactics[0] == .intro);
}
