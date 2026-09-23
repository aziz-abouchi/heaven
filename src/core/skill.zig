const std = @import("std");
const Allocator = std.mem.Allocator;
const ProofEnv = @import("proof").ProofEnv;
const expr = @import("expr");
const platform = @import("platform");

/// Une compétence = un nom + un corps au format `tactics.Tactic`.
/// Le corps est parsé puis appliqué via `ProofSession`.
pub const Skill = struct {
    name: []const u8,
    body: []const u8,
};

const BUILTIN_SKILLS = [_]Skill{
    .{ .name = "trivial", .body = "reflexivity" },
    .{ .name = "algebra", .body = "simplify; reflexivity" },
    .{ .name = "induction", .body = "induction {var}; simplify; reflexivity" },
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
            self.allocator.free(entry.key_ptr.*); // libère le nom (clé)
            self.allocator.free(entry.value_ptr.*.body); // libère le corps
            // value_ptr.*.name == key_ptr.* → déjà libéré
        }
        self.custom.deinit(self.allocator);
    }

    pub fn register(self: *SkillRegistry, name: []const u8, body: []const u8) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        const owned_body = try self.allocator.dupe(u8, body);
        errdefer self.allocator.free(owned_body);
        try self.custom.put(self.allocator, owned_name, .{
            .name = owned_name,
            .body = owned_body,
        });
    }

    pub fn get(self: *const SkillRegistry, name: []const u8) ?Skill {
        if (self.custom.get(name)) |s| return s;
        for (BUILTIN_SKILLS) |s| {
            if (std.mem.eql(u8, s.name, name)) return s;
        }
        return null;
    }

    /// Applique un skill sur un théorème nommé via ProofSession.
    /// `heaven` est `anytype` (dépendance circulaire : heaven_expr → skill).
    pub fn apply(
        self: *const SkillRegistry,
        skill_name: []const u8,
        theorem_name: []const u8,
        induction_var: []const u8,
        allocator: Allocator,
        heaven: anytype,
    ) !ApplyResult {
        const skill = self.get(skill_name) orelse {
            return ApplyResult{ .proved = false, .tactics_run = 0, .tactic_log = "skill not found" };
        };

        // Substitution {var}
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(allocator);
        var i: usize = 0;
        while (i < skill.body.len) {
            if (std.mem.startsWith(u8, skill.body[i..], "{var}")) {
                try buf.appendSlice(allocator, induction_var);
                i += 5;
            } else {
                try buf.append(allocator, skill.body[i]);
                i += 1;
            }
        }

        const session = try heaven.startProof(theorem_name);
        defer session.deinit();

        const report = try session.applyLine(buf.items);
        defer allocator.free(report);

        const proved = try session.finish();
        // tactics_run : compte les `;` + 1 (approximation)
        var count: u32 = 1;
        for (skill.body) |c| if (c == ';') {
            count += 1;
        };
        return ApplyResult{
            .proved = proved,
            .tactics_run = count,
            .tactic_log = report,
        };
    }
};

test "SkillRegistry — builtin algebra" {
    const allocator = std.testing.allocator;
    const registry = SkillRegistry.init(allocator);

    const skill = registry.get("algebra").?;
    try std.testing.expectEqualStrings("algebra", skill.name);
    try std.testing.expectEqualStrings("simplify; reflexivity", skill.body);
}

test "SkillRegistry — custom skill" {
    const allocator = std.testing.allocator;
    var registry = SkillRegistry.init(allocator);
    defer registry.deinit();

    try registry.register("my_skill", "simplify; reflexivity");
    const skill = registry.get("my_skill").?;
    try std.testing.expectEqualStrings("my_skill", skill.name);
    try std.testing.expectEqualStrings("simplify; reflexivity", skill.body);
}
