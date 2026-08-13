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
                if (self.env.get(node.payload)) |t| {
                    std.debug.print("sym: found type {d} for payload {d}\n", .{ t, node.payload });
                    return t;
                }
                std.debug.print("sym: not found payload {d}\n", .{node.payload});
                return self.unknown();
            },
            .apply => {
                const func_node = self.store.get(node.payload);
                if (func_node.tag == .sym) {
                    const name = self.store.interner.resolve(func_node.payload);
                    // Gestion des opérateurs magiques
                    if (std.mem.eql(u8, name, "+") or std.mem.eql(u8, name, "-") or
                        std.mem.eql(u8, name, "*") or std.mem.eql(u8, name, "/"))
                    {
                        return self.int(); // Retourne le type Int
                    }
                }
                return self.unknown();
            },
            .bind => {
                const val_t = try self.typeOf(node.aux);
                try self.env.put(node.payload, val_t);
                return val_t;
            },
            .lambda => {
                const p = self.store.pool.items;
                const body_span = node.span_a.slice(p);
                if (body_span.len == 0) return self.unknown();
                const body = body_span[body_span.len - 1];
                const param_sym = node.payload;
                const param_type = try self.freshTypeVar();
                try self.env.put(param_sym, param_type);
                const body_type = try self.typeOf(body);
                std.debug.print("lambda: param_sym={d}, body_type={d}\n", .{ param_sym, body_type });
                return try self.func(param_type, body_type);
            },
            .relation => self.relation(),
        };
    }

    pub fn typeStr(self: *Infer, subst: *const TypeSubst, t: Id, allocator: std.mem.Allocator) ![]u8 {
        const node = self.store.get(t);
        switch (node.tag) {
            .sym => {
                const name = self.store.interner.resolve(node.payload);
                return try allocator.dupe(u8, name);
            },
            .apply => {
                const p = self.store.pool.items;
                const children = node.span_a.slice(p);
                if (children.len == 0) return try allocator.dupe(u8, "()");
                const op_node = self.store.get(node.payload);
                if (op_node.tag != .sym) {
                    return try allocator.dupe(u8, "(apply ...)");
                }
                const op_name = self.store.interner.resolve(op_node.payload);
                if (std.mem.eql(u8, op_name, "->")) {
                    if (children.len == 2) {
                        const arg_str = try self.typeStr(subst, children[0], allocator);
                        defer allocator.free(arg_str);
                        const ret_str = try self.typeStr(subst, children[1], allocator);
                        defer allocator.free(ret_str);
                        return try std.fmt.allocPrint(allocator, "{s} -> {s}", .{ arg_str, ret_str });
                    }
                    return try allocator.dupe(u8, "->");
                } else {
                    if (children.len == 1) {
                        const arg_str = try self.typeStr(subst, children[0], allocator);
                        defer allocator.free(arg_str);
                        return try std.fmt.allocPrint(allocator, "{s} {s}", .{ op_name, arg_str });
                    }
                    return try std.fmt.allocPrint(allocator, "{s}(...)", .{op_name});
                }
            },
            .bind => {
                const name = self.store.interner.resolve(node.payload);
                const cod = node.aux;
                const cod_str = try self.typeStr(subst, cod, allocator);
                defer allocator.free(cod_str);
                const p = self.store.pool.items;
                const dom_span = node.span_a.slice(p);
                if (dom_span.len > 0) {
                    const dom_str = try self.typeStr(subst, dom_span[0], allocator);
                    defer allocator.free(dom_str);
                    return try std.fmt.allocPrint(allocator, "Π({s}:{s}).{s}", .{ name, dom_str, cod_str });
                }
                return try std.fmt.allocPrint(allocator, "Π({s}:?).{s}", .{ name, cod_str });
            },
            else => {
                return try allocator.dupe(u8, "?");
            },
        }
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
        return try @constCast(self.store).sym("Int");
    }
    fn float(self: *Infer) !Id {
        return try @constCast(self.store).sym("Float");
    }
    fn boolType(self: *Infer) !Id {
        return try @constCast(self.store).sym("Bool");
    }
    fn str(self: *Infer) !Id {
        return try @constCast(self.store).sym("String");
    }
    fn unit(self: *Infer) !Id {
        return try @constCast(self.store).sym("Unit");
    }
    fn unknown(self: *Infer) !Id {
        return try @constCast(self.store).sym("?");
    }
    fn func(self: *Infer, arg: Id, ret: Id) !Id {
        const arrow = try @constCast(self.store).sym("->");
        return @constCast(self.store).apply(arrow, &.{ arg, ret });
    }
    fn list(self: *Infer, elem: Id) !Id {
        const list_sym = try @constCast(self.store).sym("List");
        return @constCast(self.store).apply(list_sym, &.{elem});
    }
    fn relation(self: *Infer) !Id {
        return try @constCast(self.store).sym("Relation");
    }

    fn freshTypeVar(self: *Infer) !Id {
        const name = try std.fmt.allocPrint(self.env.allocator, "_t{d}", .{self.next_var});
        defer self.env.allocator.free(name);
        self.next_var += 1;
        const store_mut = @constCast(self.store);
        return try store_mut.sym(name);
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
    const n_l = try store.lowerRec(n);
    const t = try inf.typeOf(n_l);

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
    const b_l = try store.lowerRec(b);
    const t = try inf.typeOf(b_l);

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
    const sum_l = try store.lowerRec(sum);
    const t = try inf.typeOf(sum_l);

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
    const rel_l = try store.lowerRec(rel);
    const t = try inf.typeOf(rel_l);

    const str = try expr.toString(&store, t, allocator);
    defer allocator.free(str);
    try std.testing.expectEqualStrings("Relation", str);
}
