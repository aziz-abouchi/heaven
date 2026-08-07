const std = @import("std");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const Tag = expr.Tag;
const Lit = expr.Lit;

// ═══════════════════════════════════════════════════════════════════════════════
// HINDLEY-MILNER TYPE INFERENCE
//
// L'inférence ne manipule que les 6 primitives. Si une extension arrive,
// c'est un bug : elle aurait dû être lowered avant l'appel à typeOf().
//
// Type encoding :
//   int_t      → sym("Int")
//   float_t    → sym("Float")
//   bool_t     → sym("Bool")
//   str_t      → sym("String")
//   unit_t     → sym("Unit")
//   unknown_t  → sym("?")
//   func_t     → apply(sym("->"), [arg_t, ret_t])
//   relation_t → apply(sym("Relation"), [])
//   list_t     → apply(sym("List"), [elem_t])
// ═══════════════════════════════════════════════════════════════════════════════

pub const Type = expr.Id;
pub const TypeSubst = std.StringHashMapUnmanaged(Type);

pub const DependentChecker = struct {
    pub fn init(allocator: std.mem.Allocator) DependentChecker {
        _ = allocator;
        return .{};
    }
    pub fn deinit(self: *DependentChecker) void {
        _ = self;
    }
    pub fn vecType(self: *DependentChecker, n: i64, elem_type: u32) !u32 {
        _ = self;
        _ = n;
        _ = elem_type;
        return 0;
    }
    pub fn piType(self: *DependentChecker, param: []const u8, dom: u32, cod: u32) !u32 {
        _ = self;
        _ = param;
        _ = dom;
        _ = cod;
        return 0;
    }
    pub fn sigmaType(self: *DependentChecker, param: []const u8, fst: u32, snd: u32) !u32 {
        _ = self;
        _ = param;
        _ = fst;
        _ = snd;
        return 0;
    }
    pub fn checkVecAppend(self: *DependentChecker, n: i64, m: i64, elem_type: u32) !u32 {
        _ = self;
        _ = n;
        _ = m;
        _ = elem_type;
        return 0; // Retourne un u32 factice
    }
    pub fn formatJudgment(vt: u32, allocator: std.mem.Allocator) ![]u8 {
        _ = vt;
        return allocator.dupe(u8, "Judgment stub") catch return error.OutOfMemory;
    }
};

pub const Quantity = enum {
    zero,
    one,
    many,

    pub fn format(self: Quantity) []const u8 {
        return switch (self) {
            .zero => "0",
            .one => "1",
            .many => "many",
        };
    }
};

pub const LinearChecker = struct {
    usage: std.StringHashMapUnmanaged(Quantity) = .{},

    pub fn init(allocator: std.mem.Allocator) LinearChecker {
        _ = allocator;
        return .{};
    }
    pub fn deinit(self: *LinearChecker) void {
        _ = self;
    }
    pub fn declare(self: *LinearChecker, name: []const u8, qty: Quantity) !void {
        _ = self;
        _ = name;
        _ = qty;
    }
    pub fn use(self: *LinearChecker, name: []const u8) !void {
        _ = self;
        _ = name;
    }
    pub fn check(self: *LinearChecker) !void {
        _ = self;
    }
    pub fn hasErrors(self: *LinearChecker) bool {
        _ = self;
        return false;
    }
    pub fn formatErrors(self: *LinearChecker, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        return allocator.dupe(u8, "") catch return error.OutOfMemory;
    }
};

pub const TypeError = error{
    UnboundVariable,
    TypeMismatch,
    ArityMismatch,
    OutOfMemory,
    ExtensionNotLowered,
};

pub const TypeEnv = struct {
    bindings: std.AutoHashMapUnmanaged(u32, Id) = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TypeEnv {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *TypeEnv) void {
        self.bindings.deinit(self.allocator);
    }

    pub fn put(self: *TypeEnv, s: u32, t: Id) !void {
        try self.bindings.put(self.allocator, s, t);
    }

    pub fn get(self: *const TypeEnv, s: u32) ?Id {
        return self.bindings.get(s);
    }
};

pub const Infer = struct {
    store: *const Store,
    subst: TypeSubst = .{},
    env: TypeEnv,
    next_var: u32 = 0,

    pub fn init(store: *const Store, allocator: std.mem.Allocator) Infer {
        return .{ .store = store, .env = TypeEnv.init(allocator) };
    }

    pub fn deinit(self: *Infer) void {
        self.env.deinit();
    }

    pub fn typeOf(self: *Infer, id: Id) TypeError!Id {
        if (id >= self.store.len()) return self.unknown();
        const node = self.store.get(id);

        // Si ce n'est pas une primitive, c'est une erreur
        const prim = node.tag.asPrimitive() orelse {
            return error.ExtensionNotLowered;
        };

        return switch (prim) {
            .lit => self.litType(id),
            .sym => {
                if (self.env.get(node.payload)) |t| return t;
                return self.unknown();
            },
            .apply => {
                const func_node = self.store.get(node.payload);
                _ = func_node;
                return self.unknown();
            },
            .bind => {
                const val_t = try self.typeOf(node.aux);
                try self.env.put(node.payload, val_t);
                return val_t;
            },
            .lambda => {
                const body = node.span_a.slice(self.store.pool.items);
                if (body.len == 0) return self.unknown();
                const body_t = try self.typeOf(body[0]);
                _ = body_t;

                return 0; // Stub temporaire
            },
            .relation => self.relation(),
        };
    }

    pub fn typeStr(self: *Infer, subst: anytype, t: anytype, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        _ = subst;
        _ = t;
        // Stub temporaire pour faire compiler
        return allocator.dupe(u8, "TypeStr_Not_Implemented");
    }

    fn litType(self: *Infer, id: Id) !Id {
        const lit = self.store.getLit(id);
        return switch (lit) {
            .int => self.int(),
            .float => self.float(),
            .boolean => self.boolType(),
            .str => self.str(),
            .unit => self.unit(),
            .runtime => self.unknown(),
        };
    }

    fn int(self: *Infer) !Id {
        return @constCast(self.store).sym("Int");
    }
    fn float(self: *Infer) !Id {
        return @constCast(self.store).sym("Float");
    }
    fn boolType(self: *Infer) !Id {
        return @constCast(self.store).sym("Bool");
    }
    fn str(self: *Infer) !Id {
        return @constCast(self.store).sym("String");
    }
    fn unit(self: *Infer) !Id {
        return @constCast(self.store).sym("Unit");
    }
    fn unknown(self: *Infer) !Id {
        return @constCast(self.store).sym("?");
    }
    fn func(self: *Infer, arg: Id, ret: Id) !Id {
        const arrow = try self.store.sym("->");
        return self.store.apply(arrow, &.{ arg, ret });
    }
    fn list(self: *Infer, elem: Id) !Id {
        const list_sym = try self.store.sym("List");
        return self.store.apply(list_sym, &.{elem});
    }
    fn relation(self: *Infer) !Id {
        const rel_sym = try self.store.sym("Relation");
        return self.store.apply(rel_sym, &.{});
    }
};

// ─── Tests ───

test "infer — int literal" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var inf = Infer.init(&store, allocator);
    defer inf.deinit();

    const n = try store.int(42);
    const t = try inf.typeOf(n);
    const s = try expr.toString(&store, t, allocator);
    defer allocator.free(s);
    try std.testing.expectEqualStrings("Int", s);
}

test "infer — bool literal" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var inf = Infer.init(&store, allocator);
    defer inf.deinit();

    const b = try store.boolean(true);
    const t = try inf.typeOf(b);
    const s = try expr.toString(&store, t, allocator);
    defer allocator.free(s);
    try std.testing.expectEqualStrings("Bool", s);
}

test "infer — arithmetic" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var inf = Infer.init(&store, allocator);
    defer inf.deinit();

    const a = try store.int(1);
    const b = try store.int(2);
    const sum = try store.binop("+", a, b);
    const t = try inf.typeOf(sum);
    const s = try expr.toString(&store, t, allocator);
    defer allocator.free(s);
    try std.testing.expectEqualStrings("Int", s);
}

test "infer — relation" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var inf = Infer.init(&store, allocator);
    defer inf.deinit();

    const s = try store.sym("socrate");
    const rel = try store.relation("mortal", &.{s}, &.{});
    const t = try inf.typeOf(rel);
    const str = try expr.toString(&store, t, allocator);
    defer allocator.free(str);
    try std.testing.expectEqualStrings("Relation", str);
}
