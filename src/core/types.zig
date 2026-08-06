const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const Tag = expr.Tag;

/// Type expressions
/// QTT Quantities: how many times a variable can be used
pub const Quantity = enum(u8) {
    zero = 0, // erased (compile-time only, like Idris 0)
    one = 1, // linear (exactly once, like Rust ownership)
    many = 255, // unrestricted (like normal variables)

    pub fn add(a: Quantity, b: Quantity) Quantity {
        if (a == .zero and b == .zero) return .zero;
        if (a == .zero) return b;
        if (b == .zero) return a;
        if (a == .one and b == .one) return .many; // 1 + 1 = ω
        return .many;
    }

    pub fn mul(a: Quantity, b: Quantity) Quantity {
        if (a == .zero or b == .zero) return .zero;
        if (a == .one) return b;
        if (b == .one) return a;
        return .many;
    }

    pub fn compatible(have: Quantity, need: Quantity) bool {
        if (need == .many) return true;
        if (need == .zero) return have == .zero;
        if (need == .one) return have == .one;
        return false;
    }

    pub fn format(self: Quantity) []const u8 {
        return switch (self) {
            .zero => "0",
            .one => "1",
            .many => "\xcf\x89",
        };
    }
};

pub const Type = union(enum) {
    /// Primitive types
    int_t,
    float_t,
    bool_t,
    string_t,
    unit_t,
    runtime_t,
    /// Type variable (for inference
    var_t: u32,
    /// Function type: a -> b
    arrow: struct { from: *const Type, to: *const Type },
    /// Quantitative type: q * T (QTT)
    qtype: struct { quantity: Quantity, inner: *const Type },
    /// Polymorphic: forall a. T
    forall: struct { var_id: u32, body: *const Type },
    /// Pi type (dependent function): (x : A) -> B(x)
    pi: struct { param_name: []const u8, domain: *const Type, codomain: *const Type },
    /// Sigma type (dependent pair): (x : A, B(x))
    sigma: struct { param_name: []const u8, fst_type: *const Type, snd_type: *const Type },
    /// Indexed type: Type(index) e.g. Vec(3, Int)
    indexed: struct { base: []const u8, index: *const Type, param: *const Type },
    /// Nat type (for indices)
    nat_t,
    /// Type-level literal (e.g. 3 as a type index)
    type_lit: i64,
    /// Propositional equality: a = b
    eq_type: struct { lhs: *const Type, rhs: *const Type },

    pub fn eql(a: Type, b: Type) bool {
        switch (a) {
            .int_t => return b == .int_t,
            .float_t => return b == .float_t,
            .bool_t => return b == .bool_t,
            .string_t => return b == .string_t,
            .unit_t => return b == .unit_t,
            .runtime_t => return b == .runtime_t,
            .var_t => |va| switch (b) {
                .var_t => |vb| return va == vb,
                else => return false,
            },
            .arrow => |aa| switch (b) {
                .arrow => |ab| return aa.from.eql(ab.from.*) and aa.to.eql(ab.to.*),
                else => return false,
            },
            .qtype => |qa| switch (b) {
                .qtype => |qb| return qa.quantity == qb.quantity and qa.inner.eql(qb.inner.*),
                else => return false,
            },
            .pi => |pa| switch (b) {
                .pi => |pb| return std.mem.eql(u8, pa.param_name, pb.param_name) and pa.domain.eql(pb.domain.*) and pa.codomain.eql(pb.codomain.*),
                else => return false,
            },
            .sigma => |sa| switch (b) {
                .sigma => |sb| return std.mem.eql(u8, sa.param_name, sb.param_name) and sa.fst_type.eql(sb.fst_type.*) and sa.snd_type.eql(sb.snd_type.*),
                else => return false,
            },
            .indexed => |ia| switch (b) {
                .indexed => |ib| return std.mem.eql(u8, ia.base, ib.base) and ia.index.eql(ib.index.*) and ia.param.eql(ib.param.*),
                else => return false,
            },
            .nat_t => return b == .nat_t,
            .type_lit => |va| switch (b) {
                .type_lit => |vb| return va == vb,
                else => return false,
            },
            .eq_type => |ea| switch (b) {
                .eq_type => |eb| return ea.lhs.eql(eb.lhs.*) and ea.rhs.eql(eb.rhs.*),
                else => return false,
            },
            .forall => return false,
        }
    }
};

/// Type substitution (type variables → types)
pub const TypeSubst = struct {
    map: std.AutoHashMapUnmanaged(u32, Type) = .{},
    allocator: Allocator,

    pub fn init(allocator: Allocator) TypeSubst {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *TypeSubst) void {
        self.map.deinit(self.allocator);
    }
    pub fn bind(self: *TypeSubst, v: u32, t: Type) !void {
        // Éviter l'infini: si on bind ?1 -> ?2 et ?2 -> ?1
        if (t == .var_t and t.var_t == v) return;
        try self.map.put(self.allocator, v, t);
    }
    pub fn lookup(self: *const TypeSubst, v: u32) ?Type {
        return self.map.get(v);
    }

    /// Apply substitution to a type (alloue de la mémoire pour les types composites)
    pub fn apply(self: *const TypeSubst, t: Type) Type {
        switch (t) {
            .var_t => |v| {
                if (self.lookup(v)) |bound| return self.apply(bound);
                return t;
            },
            .arrow => |a| {
                const from = self.apply(a.from.*);
                const to = self.apply(a.to.*);
                const new_from = self.allocator.create(Type) catch return t;
                new_from.* = from;
                const new_to = self.allocator.create(Type) catch return t;
                new_to.* = to;
                return Type{ .arrow = .{ .from = new_from, .to = new_to } };
            },
            .pi => |p| {
                const d = self.apply(p.domain.*);
                const c = self.apply(p.codomain.*);
                const new_d = self.allocator.create(Type) catch return t;
                new_d.* = d;
                const new_c = self.allocator.create(Type) catch return t;
                new_c.* = c;
                return Type{ .pi = .{ .param_name = p.param_name, .domain = new_d, .codomain = new_c } };
            },
            // Pour l'instant, on ne substitute pas en profondeur dans les autres types
            // car on en a pas besoin pour l'inférence basique.
            else => return t,
        }
    }
};

/// Type inference engine
pub const Infer = struct {
    store: *const Store,
    allocator: Allocator,
    subst: TypeSubst,
    /// Type environment: symbol → type
    env: std.AutoHashMapUnmanaged(u32, Type) = .{},
    /// Next fresh type variable
    next_var: u32 = 0,

    pub fn init(store: *const Store, allocator: Allocator) Infer {
        return .{
            .store = store,
            .allocator = allocator,
            .subst = TypeSubst.init(allocator),
        };
    }

    pub fn deinit(self: *Infer) void {
        self.subst.deinit();
        self.env.deinit(self.allocator);
    }

    pub fn fresh(self: *Infer) Type {
        const v = self.next_var;
        self.next_var += 1;
        return .{ .var_t = v };
    }

    /// Infer the type of an expression
    pub fn infer(self: *Infer, id: Id) !Type {
        const node = self.store.get(id);
        const pool = self.store.pool.items;

        switch (node.tag) {
            .lit => {
                const l = self.store.lits.items[node.aux];
                return switch (l) {
                    .int => .int_t,
                    .float => .float_t,
                    .boolean => .bool_t,
                    .str => .string_t,
                    .unit => .unit_t,
                    .runtime => .runtime_t,
                };
            },
            .sym => {
                // Look up in env
                if (self.env.get(node.payload)) |t| return t;
                // Unknown → fresh variable
                const t = self.fresh();
                try self.env.put(self.allocator, node.payload, t);
                return t;
            },
            .apply => {
                const func_node = self.store.get(node.payload);
                const args = node.span_a.slice(pool);

                if (func_node.tag == .sym) {
                    const name = self.store.interner.resolve(func_node.payload);
                    // Built-in arithmetic → int → int → int
                    if (isArith(name) and args.len == 2) {
                        const ta = try self.infer(args[0]);
                        const tb = try self.infer(args[1]);

                        // Si l'un des deux est Float, le résultat est Float
                        if (ta == .float_t or tb == .float_t) {
                            try self.unify(ta, .float_t);
                            try self.unify(tb, .float_t);
                            return .float_t;
                        }

                        // Sinon, c'est du Int
                        try self.unify(ta, .int_t);
                        try self.unify(tb, .int_t);
                        return .int_t;
                    }
                    // Comparison → int → int → bool
                    if (isCmp(name) and args.len == 2) {
                        const ta = try self.infer(args[0]);
                        const tb = try self.infer(args[1]);
                        try self.unify(ta, .int_t);
                        try self.unify(tb, .int_t);
                        return .bool_t;
                    }
                    // if → bool, T, T → T
                    if (std.mem.eql(u8, name, "if") and args.len >= 2) {
                        const tc = try self.infer(args[0]);
                        try self.unify(tc, .bool_t);
                        const tt = try self.infer(args[1]);
                        if (args.len > 2) {
                            const te = try self.infer(args[2]);
                            try self.unify(tt, te);
                        }
                        return tt;
                    }
                    // Σ, Π → int
                    if (std.mem.eql(u8, name, "\xCE\xA3") or std.mem.eql(u8, name, "\xCE\xA0")) {
                        return .int_t;
                    }
                }
                // Generic function call → fresh type
                return self.fresh();
            },
            .bind => {
                const val_type = try self.infer(node.aux);
                try self.env.put(self.allocator, node.payload, val_type);
                return val_type;
            },
            .hole => return self.fresh(),
            .relation => return .bool_t,
            .list_nil, .list_cons => return error.DependentListsNotImplemented,
            else => return error.UnsupportedNode,
        }
    }

    /// Unify two types
    pub fn unify(self: *Infer, a: Type, b: Type) !void {
        const ra = self.subst.apply(a);
        const rb = self.subst.apply(b);

        if (ra.eql(rb)) return;

        switch (ra) {
            .var_t => |v| {
                try self.subst.bind(v, rb);
                return;
            },
            else => {},
        }
        switch (rb) {
            .var_t => |v| {
                try self.subst.bind(v, ra);
                return;
            },
            else => {},
        }

        return error.TypeMismatch;
    }

    /// Get the resolved type of an expression
    pub fn typeOf(self: *Infer, id: Id) !Type {
        const t = try self.infer(id);
        return self.subst.apply(t);
    }

    /// Format a type as string
    pub fn typeToString(subst: *const TypeSubst, t: Type, buf: *std.ArrayListUnmanaged(u8), alloc: Allocator) !void {
        const resolved = subst.apply(t);

        switch (resolved) {
            .int_t => try buf.appendSlice(alloc, "Int"),
            .float_t => try buf.appendSlice(alloc, "Float"),
            .bool_t => try buf.appendSlice(alloc, "Bool"),
            .string_t => try buf.appendSlice(alloc, "String"),
            .unit_t => try buf.appendSlice(alloc, "()"),
            .runtime_t => try buf.appendSlice(alloc, "Runtime"),
            .var_t => |v| {
                try buf.append(alloc, '?');
                var tmp: [16]u8 = undefined;
                try buf.appendSlice(alloc, std.fmt.bufPrint(&tmp, "{d}", .{v}) catch "?");
            },
            .arrow => |a| {
                try buf.append(alloc, '(');
                try typeToString(subst, a.from.*, buf, alloc);
                try buf.appendSlice(alloc, " -> ");
                try typeToString(subst, a.to.*, buf, alloc);
                try buf.append(alloc, ')');
            },
            .nat_t => try buf.appendSlice(alloc, "Nat"),
            else => try buf.appendSlice(alloc, "UnknownType"),
        }
    }

    pub fn typeStr(subst: *const TypeSubst, t: Type, alloc: Allocator) ![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(alloc);
        try typeToString(subst, t, &buf, alloc);
        return buf.toOwnedSlice(alloc);
    }

    fn isArith(name: []const u8) bool {
        return std.mem.eql(u8, name, "+") or std.mem.eql(u8, name, "-") or
            std.mem.eql(u8, name, "*") or std.mem.eql(u8, name, "/");
    }
    fn isCmp(name: []const u8) bool {
        return std.mem.eql(u8, name, "==") or std.mem.eql(u8, name, "!=") or
            std.mem.eql(u8, name, "<") or std.mem.eql(u8, name, ">") or
            std.mem.eql(u8, name, "<=") or std.mem.eql(u8, name, ">=");
    }
};

/// Dependent Type Checker — verifies indexed types
pub const DependentChecker = struct {
    allocator: Allocator,
    type_env: std.StringHashMapUnmanaged(Type),

    pub fn init(allocator: Allocator) DependentChecker {
        return .{ .allocator = allocator, .type_env = .{} };
    }

    pub fn deinit(self: *DependentChecker) void {
        self.type_env.deinit(self.allocator);
    }

    /// Create a Pi type: (x : A) -> B
    pub fn piType(self: *DependentChecker, name: []const u8, domain: Type, codomain: Type) !Type {
        const d = try self.allocator.create(Type);
        d.* = domain;
        const c2 = try self.allocator.create(Type);
        c2.* = codomain;
        return Type{ .pi = .{ .param_name = name, .domain = d, .codomain = c2 } };
    }

    /// Create a Sigma type: (x : A, B(x))
    pub fn sigmaType(self: *DependentChecker, name: []const u8, fst: Type, snd: Type) !Type {
        const f = try self.allocator.create(Type);
        f.* = fst;
        const s = try self.allocator.create(Type);
        s.* = snd;
        return Type{ .sigma = .{ .param_name = name, .fst_type = f, .snd_type = s } };
    }

    /// Create Vec(n, A)
    pub fn vecType(self: *DependentChecker, n: i64, elem: Type) !Type {
        const idx = try self.allocator.create(Type);
        idx.* = Type{ .type_lit = n };
        const p = try self.allocator.create(Type);
        p.* = elem;
        return Type{ .indexed = .{ .base = "Vec", .index = idx, .param = p } };
    }

    /// Create equality type: a ≡ b
    pub fn eqType(self: *DependentChecker, lhs: Type, rhs: Type) !Type {
        const l = try self.allocator.create(Type);
        l.* = lhs;
        const r = try self.allocator.create(Type);
        r.* = rhs;
        return Type{ .eq_type = .{ .lhs = l, .rhs = r } };
    }

    /// Check Vec append: Vec(n) ++ Vec(m) → Vec(n+m)
    pub fn checkVecAppend(self: *DependentChecker, n: i64, m: i64, elem: Type) !Type {
        return self.vecType(n + m, elem);
    }

    /// Check if n + 0 = n (reflexivity)
    pub fn checkAddZero(_: *DependentChecker, n: i64) bool {
        return n + 0 == n; // trivially true, but the TYPE is the proof
    }

    /// Bind a name to a type
    pub fn bind(self: *DependentChecker, name: []const u8, t: Type) !void {
        try self.type_env.put(self.allocator, name, t);
    }

    /// Lookup a type
    pub fn lookup(self: *DependentChecker, name: []const u8) ?Type {
        return self.type_env.get(name);
    }

    /// Format a dependent type judgment
    pub fn formatJudgment(t: Type, allocator: Allocator) ![]u8 {
        var dummy_subst = TypeSubst.init(allocator);
        defer dummy_subst.deinit();
        return Infer.typeStr(&dummy_subst, t, allocator);
    }
};

/// QTT Linear Checker — verifies quantitative usage
pub const LinearChecker = struct {
    allocator: Allocator,
    /// Maps variable name -> (declared quantity, usage count)
    usage: std.StringHashMapUnmanaged(struct { qty: Quantity, count: u32 }),
    errors: std.ArrayListUnmanaged([]const u8),

    pub fn init(allocator: Allocator) LinearChecker {
        return .{
            .allocator = allocator,
            .usage = .{},
            .errors = .{},
        };
    }

    pub fn deinit(self: *LinearChecker) void {
        self.usage.deinit(self.allocator);
        self.errors.deinit(self.allocator);
    }

    /// Declare a variable with a quantity
    pub fn declare(self: *LinearChecker, name: []const u8, qty: Quantity) !void {
        try self.usage.put(self.allocator, name, .{ .qty = qty, .count = 0 });
    }

    /// Record a use of a variable
    pub fn use(self: *LinearChecker, name: []const u8) !void {
        if (self.usage.getPtr(name)) |entry| {
            entry.count += 1;
        }
    }

    /// Check all variables satisfy their quantity constraints
    pub fn check(self: *LinearChecker) !void {
        var it = self.usage.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            const info = entry.value_ptr.*;
            switch (info.qty) {
                .zero => {
                    if (info.count > 0) {
                        const msg = try std.fmt.allocPrint(self.allocator, "erased variable '{s}' used {d} time(s) (must be 0)", .{ name, info.count });
                        try self.errors.append(self.allocator, msg);
                    }
                },
                .one => {
                    if (info.count == 0) {
                        const msg = try std.fmt.allocPrint(self.allocator, "linear variable '{s}' never used (must be exactly 1)", .{name});
                        try self.errors.append(self.allocator, msg);
                    } else if (info.count > 1) {
                        const msg = try std.fmt.allocPrint(self.allocator, "linear variable '{s}' used {d} times (must be exactly 1)", .{ name, info.count });
                        try self.errors.append(self.allocator, msg);
                    }
                },
                .many => {}, // No constraint
            }
        }
    }

    pub fn hasErrors(self: *const LinearChecker) bool {
        return self.errors.items.len > 0;
    }

    pub fn formatErrors(self: *const LinearChecker, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        const w = buf.writer(allocator);
        for (self.errors.items) |err| {
            try w.writeAll("  QTT error: ");
            try w.writeAll(err);
            try w.writeAll("\n");
        }
        return buf.toOwnedSlice(allocator);
    }
};

// ═══════════════════════════════════════════════════ // Tests // ═══════════════════════════════════════════════════

test "infer — literal int" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var inf = Infer.init(&store, allocator);
    defer inf.deinit();

    const id = try store.int(42);
    const t = try inf.typeOf(id);
    try std.testing.expect(t == .int_t);
}

test "infer — literal bool" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var inf = Infer.init(&store, allocator);
    defer inf.deinit();

    const id = try store.boolean(true);
    const t = try inf.typeOf(id);
    try std.testing.expect(t == .bool_t);
}

test "infer — addition" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var inf = Infer.init(&store, allocator);
    defer inf.deinit();

    const sum = try store.binop("+", try store.int(1), try store.int(2));
    const t = try inf.typeOf(sum);
    try std.testing.expect(t == .int_t);
}

test "infer — comparison" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var inf = Infer.init(&store, allocator);
    defer inf.deinit();

    const cmp = try store.binop("<", try store.int(1), try store.int(2));
    const t = try inf.typeOf(cmp);
    try std.testing.expect(t == .bool_t);
}

test "infer — bind propagates" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var inf = Infer.init(&store, allocator);
    defer inf.deinit();

    const val = try store.int(42);
    const b = try store.bind("x", val);
    const t = try inf.typeOf(b);
    try std.testing.expect(t == .int_t);

    // Now inferring x should give Int
    const x = try store.sym("x");
    const tx = try inf.typeOf(x);
    try std.testing.expect(tx == .int_t);
}

test "infer — type mismatch" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var inf = Infer.init(&store, allocator);
    defer inf.deinit();

    // true + 1 should fail
    const bad = try store.binop("+", try store.boolean(true), try store.int(1));
    const result = inf.typeOf(bad);
    try std.testing.expectError(error.TypeMismatch, result);
}

test "infer — format type" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var inf = Infer.init(&store, allocator);
    defer inf.deinit();
    const s = try Infer.typeStr(&inf.subst, .int_t, allocator);
    defer allocator.free(s);
    try std.testing.expectEqualStrings("Int", s);
}
