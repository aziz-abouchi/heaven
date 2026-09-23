const std = @import("std");

pub const UniverseLevel = union(enum) {
    concrete: u32,
    max: struct {
        a: *const UniverseLevel,
        b: *const UniverseLevel,
    },

    pub fn getConcrete(self: UniverseLevel) ?u32 {
        return switch (self) {
            .concrete => |c| c,
            .max => |m| if (m.a.getConcrete()) |c1|
                if (m.b.getConcrete()) |c2| @max(c1, c2) else null
            else
                null,
        };
    }

    pub fn maxWith(self: UniverseLevel, other: UniverseLevel, allocator: std.mem.Allocator) !UniverseLevel {
        if (self.getConcrete()) |c1| {
            if (other.getConcrete()) |c2| {
                return UniverseLevel{ .concrete = @max(c1, c2) };
            }
        }
        const a_ptr = try allocator.create(UniverseLevel);
        const b_ptr = try allocator.create(UniverseLevel);
        a_ptr.* = self;
        b_ptr.* = other;
        return UniverseLevel{ .max = .{ .a = a_ptr, .b = b_ptr } };
    }
};

pub const Sort = union(enum) {
    prop,
    type_sort: UniverseLevel,
};

pub const Term = union(enum) {
    sort: Sort,
    variable: usize, // Index de De Bruijn
    pi: struct {
        name: []const u8,
        domain: *const Term,
        codomain: *const Term,
    },
    lambda: struct {
        name: []const u8,
        domain: *const Term,
        body: *const Term,
    },
    app: struct {
        func: *const Term,
        arg: *const Term,
    },
    // Primitive Types Quotients
    quot: struct {
        type_a: *const Term,
        relation_r: *const Term, // R : A -> A -> Prop
    },
    class: struct {
        quot_type: *const Term, // Quot(A, R)
        element: *const Term, // x : A
    },
    lift: struct {
        quot_type: *const Term, // Quot(A, R)
        target_b: *const Term, // Type d'arrivée B
        func_f: *const Term, // f : A -> B
        proof: *const Term, // Preuve que f resp. R
    },
};
