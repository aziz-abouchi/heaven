const std = @import("std");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const Tag = expr.Tag;
const Lit = expr.Lit;

const elab = @import("elab");
const TypeChecker = elab.TypeChecker;
const TypingContext = elab.TypingContext;

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

pub fn typeSize(allocator: std.mem.Allocator, store: *const Store, ty: Type) u32 {
    const node = store.get(ty);
    switch (node.tag) {
        .sym => {
            const name = store.interner.resolve(node.payload);
            if (std.mem.eql(u8, name, "Int")) return 8;
            if (std.mem.eql(u8, name, "Bool")) return 1;
            if (std.mem.eql(u8, name, "Float")) return 8;
            if (std.mem.eql(u8, name, "Unit")) return 0;
            if (std.mem.eql(u8, name, "String")) return 16;
            // Les types comme "List", "Tuple", "->" sont des applications, pas des symboles seuls.
            return 1; // fallback pour les symboles inconnus
        },
        .apply => {
            const func_node = store.get(node.payload);
            if (func_node.tag != .sym) return 1;
            const func_name = store.interner.resolve(func_node.payload);
            const args = node.span_a.slice(store.pool.items);

            // Liste : (List elem)
            if (std.mem.eql(u8, func_name, "List")) {
                if (args.len == 1) {
                    const elem_size = typeSize(allocator, store, args[0]);
                    return 8 + elem_size; // estimation : 8 octets pour le pointeur + taille de l'élément
                }
                return 1;
            }

            // Tuple : (Tuple field1 field2 ...)
            if (std.mem.eql(u8, func_name, "Tuple")) {
                var total: u32 = 0;
                for (args) |arg| {
                    total += typeSize(allocator, store, arg);
                }
                return total;
            }

            // Flèche : (-> arg ret) ou (-> param arg ret) selon l'encodage
            if (std.mem.eql(u8, func_name, "->")) {
                // En général, une flèche a 2 ou 3 arguments : paramètre de type, domaine, codomaine
                // On ne prend que le domaine et le codomaine pour la taille
                if (args.len >= 2) {
                    const dom = args[args.len - 2]; // avant-dernier
                    const cod = args[args.len - 1]; // dernier
                    return typeSize(allocator, store, dom) + typeSize(allocator, store, cod);
                }
                return 16; // fallback
            }

            // Autres applications inconnues
            return 1;
        },
        // Autres tags (bind, lambda, etc.) → fallback
        else => return 1,
    }
}

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
    bindings: std.StringHashMap(Id),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TypeEnv {
        return .{
            .allocator = allocator,
            .bindings = std.StringHashMap(Id).init(allocator),
        };
    }

    pub fn deinit(self: *TypeEnv) void {
        var it = self.bindings.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.bindings.deinit();
    }

    pub fn put(self: *TypeEnv, name: []const u8, t: Id) !void {
        const key = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(key);
        try self.bindings.put(key, t);
    }

    pub fn get(self: *const TypeEnv, name: []const u8) ?Id {
        return self.bindings.get(name);
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

    fn inferApply(self: *Infer, apply_id: Id) !Id {
        const apply_node = self.store.get(apply_id);
        const func_type = try self.typeOf(apply_node.payload);
        if (func_type >= self.store.len()) return self.unknown();
        const func_node = self.store.get(func_type);

        if (func_node.tag != .apply) return self.unknown();

        const arrow_node = self.store.get(func_node.payload);
        if (arrow_node.tag != .sym) return self.unknown();
        const arrow_name = self.store.interner.resolve(arrow_node.payload);
        if (!std.mem.eql(u8, arrow_name, "->")) return self.unknown();

        const p = self.store.pool.items;

        if (func_node.span_a.start >= p.len) return self.unknown();
        if (func_node.span_a.start + func_node.span_a.len > p.len) return self.unknown();
        const arrow_len = func_node.span_a.len;
        if (arrow_len != 2 and arrow_len != 3) return self.unknown();

        // Pour une flèche normale : [domaine, codomaine]
        // Pour une flèche à 3 éléments : [paramètre de type, domaine, codomaine]
        const domain = if (arrow_len == 2)
            p[func_node.span_a.start]
        else
            p[func_node.span_a.start + 1];
        const codomain = p[func_node.span_a.start + arrow_len - 1];

        // Vérifier le span de l'application
        if (apply_node.span_a.start >= p.len) return self.unknown();
        if (apply_node.span_a.start + apply_node.span_a.len > p.len) return self.unknown();
        const app_len = apply_node.span_a.len;
        if (app_len == 0) return self.unknown();
        const arg = p[apply_node.span_a.start + app_len - 1];
        const arg_type = try self.typeOf(arg);

        if (domain < self.store.len()) {
            const domain_node = self.store.get(domain);
            if (domain_node.tag == .sym) {
                const domain_name = self.store.interner.resolve(domain_node.payload);
                if (std.mem.startsWith(u8, domain_name, "_t")) {
                    return try self.substInType(codomain, domain_name, arg_type);
                }
            }
        }
        return codomain;
    }

    fn substInType(self: *Infer, t: Id, var_name: []const u8, replacement: Id) !Id {
        const node = self.store.get(t);
        switch (node.tag) {
            .sym => {
                const name = self.store.interner.resolve(node.payload);
                if (std.mem.eql(u8, name, var_name)) return replacement;
                return t;
            },
            .apply => {
                const new_func = try self.substInType(node.payload, var_name, replacement);
                const p = self.store.pool.items;
                const args = node.span_a.slice(p);
                var new_args = std.ArrayListUnmanaged(Id){};
                defer new_args.deinit(self.env.allocator);
                for (args) |arg| {
                    try new_args.append(self.env.allocator, try self.substInType(arg, var_name, replacement));
                }
                return try @constCast(self.store).apply(new_func, new_args.items);
            },
            .bind => {
                const new_body = try self.substInType(node.aux, var_name, replacement);
                const p = self.store.pool.items;
                const children = node.span_a.slice(p);
                var new_children = std.ArrayListUnmanaged(Id){};
                defer new_children.deinit(self.env.allocator);
                for (children) |child| {
                    try new_children.append(self.env.allocator, try self.substInType(child, var_name, replacement));
                }
                const sa = try @constCast(self.store).pushSpan(new_children.items);
                return @constCast(self.store).addNode(.{
                    .tag = .bind,
                    .payload = node.payload,
                    .aux = new_body,
                    .span_a = sa,
                    .span_b = node.span_b,
                });
            },
            else => return t,
        }
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
                const name = self.store.interner.resolve(node.payload);
                // std.debug.print("sym: looking for '{s}'\n", .{name});
                if (self.env.get(name)) |t| {
                    // std.debug.print("sym: found type {d}\n", .{t});
                    return t;
                }
                // std.debug.print("sym: not found\n", .{});
                return self.unknown();
            },
            .lambda => {
                const p = self.store.pool.items;
                const body_span = node.span_a.slice(p);
                if (body_span.len == 0) return self.unknown();
                const body = body_span[body_span.len - 1];
                const param_sym = node.payload;
                const param_name = self.store.interner.resolve(param_sym);
                const param_type = try self.freshTypeVar();
                try self.env.put(param_name, param_type);
                const body_type = try self.typeOf(body);
                return try self.func(param_type, body_type);
            },
            .apply => {
                // Opérateurs binaires → Int
                const func_node = self.store.get(node.payload);
                if (func_node.tag == .sym) {
                    const name = self.store.interner.resolve(func_node.payload);
                    if (std.mem.eql(u8, name, "+") or std.mem.eql(u8, name, "-") or
                        std.mem.eql(u8, name, "*") or std.mem.eql(u8, name, "/"))
                    {
                        return self.int();
                    }
                }
                return try self.inferApply(id);
            },
            .bind => {
                const val_t = try self.typeOf(node.aux);
                const name = self.store.interner.resolve(node.payload);
                try self.env.put(name, val_t);
                return val_t;
            },
            .relation => self.relation(),
        };
    }

    pub fn typeStr(self: *Infer, subst: *const TypeSubst, t: Id, allocator: std.mem.Allocator) ![]u8 {
        if (t >= self.store.len()) return try allocator.dupe(u8, "?");
        const node = self.store.get(t);
        // std.debug.print("typeStr: t={d}, tag={s}\n", .{ t, @tagName(node.tag) });
        switch (node.tag) {
            .sym => {
                if (node.payload >= self.store.interner.list.items.len) {
                    return try allocator.dupe(u8, "?");
                }
                const name = self.store.interner.resolve(node.payload);
                if (std.mem.startsWith(u8, name, "_t")) {
                    return try allocator.dupe(u8, name);
                }
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
        const node = self.store.get(id);
        if (node.tag != .lit) return error.ExtensionNotLowered;
        if (node.aux >= self.store.lits.items.len) {
            // std.debug.print("litType: invalid aux={d}, lits.len={d}\n", .{ node.aux, self.store.lits.items.len });
            return self.unknown();
        }
        const lit = self.store.lits.items[node.aux];
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
