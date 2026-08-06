pub const SkillStep = enum {
    intro,
    simplify,
    rewrite,
    exact,
};

pub const Skill = struct {
    name: []const u8,
    steps: []SkillStep,
};
