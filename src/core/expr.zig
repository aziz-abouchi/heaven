const std = @import("std");
const Allocator = std.mem.Allocator;

// ═══════════════════════════════════════════════════════════════════════════════
// HEAVEN CORE EXPRESSION SYSTEM
//
// Noyau minimal : 6 primitives fondamentales.
// Toute expression evaluable se réduit à ces 6 constructeurs.
//
// 1. lit      — Valeurs immédiates (int, float, str, bool, unit, runtime)
// 2. sym      — Symboles / variables / références
// 3. apply    — Application n-aire : (f a b c)
// 4. bind     — Binding global : name := value
// 5. lambda   — Abstraction fonctionnelle : λx.body
// 6. relation — Relation / règle de réécriture : head(args) :- body
//
// Tout le reste est EXTENSION (sucre syntaxique ou représentation intermédiaire)
// et doit être éliminé (lowered) en primitives avant évaluation.
// ═══════════════════════════════════════════════════════════════════════════════

pub const Id = u32;
pub const NULL: Id = std.math.maxInt(Id);
pub const Sym = u32;

pub const Span = struct {
    start: u32,
    len: u16,

    pub const EMPTY: Span = .{ .start = 0, .len = 0 };

    pub fn slice(self: Span, pool: []const Id) []const Id {
        return pool[self.start..][0..self.len];
    }
};

pub const RuntimeRef = union(enum) {
    theorem: u32,
    proof: u32,
    skill: u32,
    agent: u32,
};

pub const Lit = union(enum) {
    int: i64,
    float: f64,
    str: Sym,
    boolean: bool,
    unit,
    runtime: RuntimeRef,

    pub fn eql(a: Lit, b: Lit) bool {
        switch (a) {
            .int => |va| switch (b) {
                .int => |vb| return va == vb,
                else => return false,
            },
            .float => |va| switch (b) {
                .float => |vb| return va == vb,
                else => return false,
            },
            .str => |va| switch (b) {
                .str => |vb| return va == vb,
                else => return false,
            },
            .boolean => |va| switch (b) {
                .boolean => |vb| return va == vb,
                else => return false,
            },
            .unit => switch (b) {
                .unit => return true,
                else => return false,
            },
            .runtime => |va| switch (b) {
                .runtime => |vb| return std.meta.eql(va, vb),
                else => return false,
            },
        }
    }

    pub fn hash(self: Lit) u64 {
        var h: u64 = 0xcbf29ce484222325;
        const prime: u64 = 0x100000001b3;
        switch (self) {
            .int => |v| {
                h ^= 0;
                h *%= prime;
                h ^= @bitCast(v);
            },
            .float => |v| {
                h ^= 1;
                h *%= prime;
                h ^= @bitCast(v);
            },
            .str => |v| {
                h ^= 2;
                h *%= prime;
                h ^= @as(u64, v);
            },
            .boolean => |v| {
                h ^= 3;
                h *%= prime;
                h ^= @intFromBool(v);
            },
            .unit => {
                h ^= 4;
                h *%= prime;
            },
            .runtime => |v| {
                h ^= 5;
                h *%= prime;
                h ^= @intFromEnum(v);
                switch (v) {
                    .theorem => |vid| { h ^= @as(u64, vid); h *%= prime; },
                    .proof   => |vid| { h ^= @as(u64, vid); h *%= prime; },
                    .skill   => |vid| { h ^= @as(u64, vid); h *%= prime; },
                    .agent   => |vid| { h ^= @as(u64, vid); h *%= prime; },
                }
            },
        }
        return h;
    }
};

// ─── 6 PRIMITIVES FONDAMENTALES ───
pub const Primitive = enum(u8) {
    lit = 0,
    sym = 1,
    apply = 2,
    bind = 3,
    lambda = 4,
    relation = 5,

    pub const COUNT: u8 = 6;
};

// ─── EXTENSIONS (non-primitives, désucrables) ───
pub const Extension = enum(u8) {
    // Sucres syntaxiques (6–11)
    let_in = 6,   // let x = v in b  →  apply(lambda(x, b), v)
    hole = 7,     // _n  →  sym("_") [traitement spécial matcher]
    quote = 8,    // 'e  →  apply(quote, e)
    unquote = 9,  // ~e  →  apply(unquote, e)
    perform = 10, // perform(op, args)  →  apply(perform, op, args...)
    handle = 11,  // handle(body, h)    →  apply(handle, body, h)

    // Types dépendants (12–14)
    universe = 12, // Type_i  →  sym("Type_i")
    pi = 13,       // Π(x:A).B  →  bind(x, apply(Π, A, B))
    type_ann = 14, // e : T     →  apply(:, e, T)

    // Listes (15–16)
    list_nil = 15,  // []  →  sym("Nil")
    list_cons = 16, // h::t → apply(Cons, h, t)

    // Frontend / Parsing (20–39) — ne doivent jamais atteindre l'évaluateur
    source_file = 20,
    fn_decl, eq_decl, var_decl, assign,
    call, binary, if_stmt, while_stmt, block,
    store_stmt, store_expr, store,
    identifier, int, float, str, bool_lit,
    theorem_decl, prove_cmd, skill_decl,

    // Tests (40–42)
    test_decl = 41,
    assert_eq,
    assert_err,

    // Macros (43)
    macro_def = 44,
};

// ─── TAG UNIFIÉ ───
pub const Tag = enum(u8) {
    // ═══ PRIMITIVES (0–5) ═══
    lit = 0,
    sym = 1,
    apply = 2,
    bind = 3,
    lambda = 4,
    relation = 5,

    // ═══ EXTENSIONS : SUCRES (6–11) ═══
    let_in = 6,
    hole = 7,
    quote = 8,
    unquote = 9,
    perform = 10,
    handle = 11,

    // ═══ EXTENSIONS : TYPES (12–14) ═══
    universe = 12,
    pi = 13,
    type_ann = 14,

    // ═══ EXTENSIONS : LISTES (15–16) ═══
    list_nil = 15,
    list_cons = 16,

    // ═══ EXTENSIONS : FRONTEND (20–39) ═══
    source_file = 20,
    fn_decl,
    eq_decl,
    var_decl,
    assign,
    call,
    binary,
    if_stmt,
    while_stmt,
    block,
    store_stmt,
    store_expr,
    store,
    identifier,
    int,
    float,
    str,
    bool_lit,
    theorem_decl,
    prove_cmd,
    skill_decl,

    // ═══ EXTENSIONS : TESTS (40–42) ═══
    test_decl = 41,
    assert_eq,
    assert_err,

    // ═══ EXTENSIONS : MACROS (43) ═══
    macro_def = 44,

    // ─── Méthodes de classification ───

    pub inline fn isPrimitive(self: Tag) bool {
        return @intFromEnum(self) < Primitive.COUNT;
    }

    pub inline fn asPrimitive(self: Tag) ?Primitive {
        return if (self.isPrimitive())
            @enumFromInt(@intFromEnum(self))
        else
            null;
    }

    pub inline fn isExtension(self: Tag) bool {
        return !self.isPrimitive();
    }

    pub inline fn isSugar(self: Tag) bool {
        const v = @intFromEnum(self);
        return v >= 6 and v <= 19;
    }

    pub inline fn isFrontend(self: Tag) bool {
        const v = @intFromEnum(self);
        return v >= 20 and v <= 39;
    }

    pub inline fn isLowerable(self: Tag) bool {
        return self.isSugar() or (self.isExtension() and !self.isFrontend());
    }
};

pub const Expr = struct {
    tag: Tag = .sym,
    payload: u32 = 0,
    aux: u32 = 0,
    span_a: Span = Span.EMPTY,
    span_b: Span = Span.EMPTY,
};

const INFIX_OPS = [_][]const u8{ "+", "-", "*", "/", "^", "==", "!=", "<", ">", "<=", ">=", "∧", "∨", "→", "⊸" };

fn isInfix(op: []const u8) bool {
    for (INFIX_OPS) |o| if (std.mem.eql(u8, op, o)) return true;
    return false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// STORE
// ═══════════════════════════════════════════════════════════════════════════════

pub const Store = struct {
    nodes: std.ArrayListUnmanaged(Expr) = .{},
    lits: std.ArrayListUnmanaged(Lit) = .{},
    pool: std.ArrayListUnmanaged(Id) = .{},
    interner: Interner,
    allocator: Allocator,

    pub fn init(allocator: Allocator) Store {
        return .{
            .interner = Interner.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Store) void {
        self.nodes.deinit(self.allocator);
        self.lits.deinit(self.allocator);
        self.pool.deinit(self.allocator);
        self.interner.deinit();
    }

    pub fn get(self: *const Store, id: Id) Expr {
        return self.nodes.items[id];
    }

    pub fn getLit(self: *const Store, id: Id) Lit {
        const node = self.nodes.items[id];
        return self.lits.items[node.aux];
    }

    pub fn childPool(self: *const Store) []const Id {
        return self.pool.items;
    }

    pub fn len(self: *const Store) u32 {
        return @intCast(self.nodes.items.len);
    }

    // ─────────────────────────────────────────────────────────
    // PRIMITIVES (6 fondamentales)
    // ─────────────────────────────────────────────────────────

    /// Primitive 1/6 : Valeur immédiate
    pub fn lit(self: *Store, value: Lit) !Id {
        const lit_idx: u32 = @intCast(self.lits.items.len);
        try self.lits.append(self.allocator, value);
        return self.push(.{ .tag = .lit, .aux = lit_idx });
    }

    /// Primitive 2/6 : Symbole / variable
    pub fn sym(self: *Store, name: []const u8) !Id {
        const s = try self.interner.intern(name);
        return self.push(.{ .tag = .sym, .payload = s });
    }

    pub fn symId(self: *Store, s: Sym) !Id {
        return self.push(.{ .tag = .sym, .payload = s });
    }

    /// Primitive 3/6 : Application n-aire
    pub fn apply(self: *Store, func_id: Id, arg_ids: []const Id) !Id {
        const span = try self.pushSpan(arg_ids);
        return self.push(.{ .tag = .apply, .payload = func_id, .span_a = span });
    }

    /// Primitive 4/6 : Binding global
    pub fn bind(self: *Store, name: []const u8, value: Id) !Id {
        const s = try self.interner.intern(name);
        return self.push(.{ .tag = .bind, .payload = s, .aux = value });
    }

    pub fn bindSym(self: *Store, name_sym: Sym, value: Id) !Id {
        return self.push(.{ .tag = .bind, .payload = name_sym, .aux = value });
    }

    pub fn bindSymWithBody(self: *Store, name_sym: Sym, value: Id, body: Id) !Id {
        const span = try self.pushSpan(&.{body});
        return self.push(.{ .tag = .bind, .payload = name_sym, .aux = value, .span_a = span });
    }

    /// Primitive 5/6 : Abstraction fonctionnelle
    pub fn lambdaNative(self: *Store, param: []const u8, body_id: Id) !Id {
        const s = try self.interner.intern(param);
        const span = try self.pushSpan(&.{body_id});
        return self.push(.{ .tag = .lambda, .payload = s, .span_a = span });
    }

    /// Primitive 6/6 : Relation / règle de réécriture
    pub fn relation(self: *Store, head: []const u8, arg_ids: []const Id, body_ids: []const Id) !Id {
        const s = try self.interner.intern(head);
        const sa = try self.pushSpan(arg_ids);
        const sb = try self.pushSpan(body_ids);
        return self.push(.{ .tag = .relation, .payload = s, .span_a = sa, .span_b = sb });
    }

    // ─────────────────────────────────────────────────────────
    // EXTENSIONS : SUCRES SYNTAXIQUES
    // Ces builders produisent des tags Extension.
    // Ils doivent être lowered avant évaluation.
    // ─────────────────────────────────────────────────────────

    /// Extension : let x = v in b
    /// Lowering : apply(lambda(x, b), v)
    pub fn letIn(self: *Store, name: []const u8, value_id: Id, body_id: Id) !Id {
        const s = try self.interner.intern(name);
        const span = try self.pushSpan(&.{body_id});
        return self.push(.{ .tag = .let_in, .payload = s, .aux = value_id, .span_a = span });
    }

    /// Extension : trou de pattern matching
    /// Lowering : sym("_") [le matcher traite _ spécialement]
    pub fn hole(self: *Store, index: u32) !Id {
        return self.push(.{ .tag = .hole, .payload = index });
    }

    /// Extension : quote macro
    /// Lowering : apply(quote, e)
    pub fn quote(self: *Store, expr_id: Id) !Id {
        return self.push(.{ .tag = .quote, .payload = expr_id });
    }

    /// Extension : unquote macro
    /// Lowering : apply(unquote, e)
    pub fn unquote(self: *Store, expr_id: Id) !Id {
        return self.push(.{ .tag = .unquote, .payload = expr_id });
    }

    /// Extension : effet algébrique perform
    /// Lowering : apply(perform, op, args...)
    pub fn perform(self: *Store, name: []const u8, args: []const Id) !Id {
        const name_sym = try self.interner.intern(name);
        const span = try self.pushSpan(args);
        return self.push(.{ .tag = .perform, .payload = name_sym, .span_a = span });
    }

    /// Extension : handler d'effet algébrique
    /// Lowering : apply(handle, body, handler)
    pub fn handle(self: *Store, body_id: Id, handler_id: Id) !Id {
        return self.push(.{ .tag = .handle, .payload = body_id, .aux = handler_id });
    }

    // ─────────────────────────────────────────────────────────
    // EXTENSIONS : TYPES DÉPENDANTS
    // ─────────────────────────────────────────────────────────

    /// Extension : universe Type_i
    /// Lowering : sym("Type_i")
    pub fn universe(self: *Store, level: u32) !Id {
        var buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "Type_{d}", .{level}) catch return error.OutOfMemory;
        return self.sym(name);
    }

    /// Extension : type dépendant Π(x:A).B
    /// Lowering : bind(x, apply(Π, A, B))
    pub fn pi(self: *Store, param_name: []const u8, param_type: Id, body_type: Id) !Id {
        const pi_sym = try self.sym("Π");
        const args = [_]Id{ param_type, body_type };
        const pi_app = try self.apply(pi_sym, &args);
        return self.bind(param_name, pi_app);
    }

    /// Extension : annotation de type e : T
    /// Lowering : apply(:, e, T)
    pub fn typeAnn(self: *Store, term: Id, typ: Id) !Id {
        const ann_sym = try self.sym(":");
        const args = [_]Id{ term, typ };
        return self.apply(ann_sym, &args);
    }

    // ─────────────────────────────────────────────────────────
    // EXTENSIONS : LISTES
    // ─────────────────────────────────────────────────────────

    /// Extension : liste vide
    /// Lowering : sym("Nil")
    pub fn listNil(self: *Store) !Id {
        return self.push(.{ .tag = .list_nil });
    }

    /// Extension : cons
    /// Lowering : apply(Cons, h, t)
    pub fn listCons(self: *Store, head: Id, tail: Id) !Id {
        return self.push(.{ .tag = .list_cons, .span_a = .{ .start = head, .len = 0 }, .span_b = .{ .start = tail, .len = 0 } });
    }

    // ─────────────────────────────────────────────────────────
    // LOWERING : Extension → Primitive
    // ─────────────────────────────────────────────────────────

    /// Convertit une extension en primitives fondamentales.
    /// Idempotente sur les primitives.
    pub fn lower(self: *Store, id: Id) !Id {
        if (id >= self.len()) return id;
        const node = self.get(id);
        if (node.tag.isPrimitive()) return id;

        return switch (node.tag) {
            .let_in => {
                const name = self.interner.resolve(node.payload);
                const body = node.span_a.slice(self.pool.items)[0];
                const lam = try self.lambdaNative(name, body);
                return self.apply(lam, &.{node.aux});
            },
            .hole => self.sym("_"),
            .quote => {
                const q = try self.sym("quote");
                return self.apply(q, &.{node.payload});
            },
            .unquote => {
                const u = try self.sym("unquote");
                return self.apply(u, &.{node.payload});
            },
            .perform => {
                const p = try self.sym("perform");
                const op_name = try self.sym(self.interner.resolve(node.payload));
                const args = node.span_a.slice(self.pool.items);
                var all = std.ArrayListUnmanaged(Id){};
                defer all.deinit(self.allocator);
                try all.append(self.allocator, op_name);
                try all.appendSlice(self.allocator, args);
                return self.apply(p, all.items);
            },
            .handle => {
                const h = try self.sym("handle");
                return self.apply(h, &.{ node.payload, node.aux });
            },
            .universe => {
                var buf: [32]u8 = undefined;
                const name = std.fmt.bufPrint(&buf, "Type_{d}", .{node.payload}) catch return error.OutOfMemory;
                return self.sym(name);
            },
            .pi => {
                const name = self.interner.resolve(node.payload);
                const args = node.span_a.slice(self.pool.items);
                if (args.len < 2) return error.InvalidPi;
                const pi_sym = try self.sym("Π");
                const app = try self.apply(pi_sym, args[0..2]);
                return self.bind(name, app);
            },
            .type_ann => {
                const colon = try self.sym(":");
                const args = node.span_a.slice(self.pool.items);
                if (args.len < 2) return error.InvalidTypeAnn;
                return self.apply(colon, args[0..2]);
            },
            .list_nil => self.sym("Nil"),
            .list_cons => {
                const c = try self.sym("Cons");
                const h = node.span_a.start;
                const t = node.span_b.start;
                return self.apply(c, &.{h, t});
            },
            else => error.CannotLowerFrontendTag,
        };
    }

    /// Lowering récursif en profondeur.
    pub fn lowerRec(self: *Store, id: Id) !Id {
        if (id >= self.len()) return id;
        const node = self.get(id);

        // D'abord lower les enfants
        var new_payload = node.payload;
        var new_aux = node.aux;
        var new_span_a = node.span_a;
        var new_span_b = node.span_b;

        switch (node.tag) {
            .apply => {
                new_payload = try self.lowerRec(node.payload);
                var new_args = std.ArrayListUnmanaged(Id){};
                defer new_args.deinit(self.allocator);
                for (node.span_a.slice(self.pool.items)) |arg| {
                    try new_args.append(self.allocator, try self.lowerRec(arg));
                }
                new_span_a = try self.pushSpan(new_args.items);
            },
            .bind, .let_in, .lambda => {
                new_aux = try self.lowerRec(node.aux);
                var new_body = std.ArrayListUnmanaged(Id){};
                defer new_body.deinit(self.allocator);
                for (node.span_a.slice(self.pool.items)) |child| {
                    try new_body.append(self.allocator, try self.lowerRec(child));
                }
                new_span_a = try self.pushSpan(new_body.items);
            },
            .relation => {
                var new_args = std.ArrayListUnmanaged(Id){};
                defer new_args.deinit(self.allocator);
                for (node.span_a.slice(self.pool.items)) |arg| {
                    try new_args.append(self.allocator, try self.lowerRec(arg));
                }
                new_span_a = try self.pushSpan(new_args.items);

                var new_body = std.ArrayListUnmanaged(Id){};
                defer new_body.deinit(self.allocator);
                for (node.span_b.slice(self.pool.items)) |b| {
                    try new_body.append(self.allocator, try self.lowerRec(b));
                }
                new_span_b = try self.pushSpan(new_body.items);
            },
            .list_cons => {
                new_span_a = .{ .start = try self.lowerRec(node.span_a.start), .len = 0 };
                new_span_b = .{ .start = try self.lowerRec(node.span_b.start), .len = 0 };
            },
            else => {},
        }

        // Reconstruire le nœud avec les enfants lowerés
        const lowered_id = try self.push(.{
            .tag = node.tag,
            .payload = new_payload,
            .aux = new_aux,
            .span_a = new_span_a,
            .span_b = new_span_b,
        });

        // Puis lower le nœud lui-même
        return self.lower(lowered_id);
    }

    // ─────────────────────────────────────────────────────────
    // HELPERS (produisent des primitives directement)
    // ─────────────────────────────────────────────────────────

    pub fn int(self: *Store, v: i64) !Id { return self.lit(.{ .int = v }); }
    pub fn float(self: *Store, v: f64) !Id { return self.lit(.{ .float = v }); }
    pub fn boolean(self: *Store, v: bool) !Id { return self.lit(.{ .boolean = v }); }
    pub fn unitLit(self: *Store) !Id { return self.lit(.unit); }

    pub fn call(self: *Store, name: []const u8, arg_ids: []const Id) !Id {
        const f = try self.sym(name);
        return self.apply(f, arg_ids);
    }

    pub fn binop(self: *Store, op: []const u8, lhs: Id, rhs: Id) !Id {
        const op_id = try self.sym(op);
        const arg_ids = [_]Id{ lhs, rhs };
        return self.apply(op_id, &arg_ids);
    }

    /// Sucre : multi-paramètre → curryfié en apply(λ, params..., body)
    pub fn lambda(self: *Store, params: []const []const u8, body_id: Id) !Id {
        var param_ids = std.ArrayListUnmanaged(Id){};
        defer param_ids.deinit(self.allocator);
        for (params) |p| {
            try param_ids.append(self.allocator, try self.sym(p));
        }
        try param_ids.append(self.allocator, body_id);
        const lam = try self.sym("λ");
        return self.apply(lam, param_ids.items);
    }

    pub fn aggregate(self: *Store, op: []const u8, variable: []const u8, lo: Id, hi: Id, body_id: Id) !Id {
        const var_id = try self.sym(variable);
        const op_id = try self.sym(op);
        const arg_ids = [_]Id{ var_id, lo, hi, body_id };
        return self.apply(op_id, &arg_ids);
    }

    pub fn macroDef(self: *Store, name: []const u8, param: []const u8, body_id: Id) !Id {
        const name_sym = try self.interner.intern(name);
        const param_sym = try self.interner.intern(param);
        const span = try self.pushSpan(&.{ param_sym, body_id });
        return self.push(.{ .tag = .macro_def, .payload = name_sym, .span_a = span });
    }

    // ─────────────────────────────────────────────────────────
    // Internal
    // ─────────────────────────────────────────────────────────

    pub fn push(self: *Store, node: Expr) !Id {
        const id: Id = @intCast(self.nodes.items.len);
        try self.nodes.append(self.allocator, node);
        return id;
    }

    pub fn pushSpan(self: *Store, ids: []const Id) !Span {
        if (ids.len == 0) return Span.EMPTY;
        const start: u32 = @intCast(self.pool.items.len);
        try self.pool.appendSlice(self.allocator, ids);
        return .{ .start = start, .len = @intCast(ids.len) };
    }

    pub fn forEachChild(store: *const Store, id: Id, context: anytype, comptime callback: fn (ctx: @TypeOf(context), child_id: Id) void) void {
        const node = store.get(id);
        const pool = store.pool.items;

        switch (node.tag) {
            .apply => {
                callback(context, node.payload);
                for (node.span_a.slice(pool)) |child| callback(context, child);
            },
            .bind => callback(context, node.aux),
            .let_in, .lambda => {
                callback(context, node.aux);
                for (node.span_a.slice(pool)) |child| callback(context, child);
            },
            .relation => {
                for (node.span_a.slice(pool)) |child| callback(context, child);
                for (node.span_b.slice(pool)) |child| callback(context, child);
            },
            .list_cons => {
                callback(context, node.span_a.start);
                callback(context, node.span_b.start);
            },
            else => {},
        }
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// INTERNER
// ═══════════════════════════════════════════════════════════════════════════════

pub const Interner = struct {
    map: std.StringHashMapUnmanaged(Sym) = .{},
    names: std.ArrayListUnmanaged([]const u8) = .{},
    allocator: Allocator,

    pub fn init(allocator: Allocator) Interner {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Interner) void {
        for (self.names.items) |name| {
            self.allocator.free(name);
        }
        self.names.deinit(self.allocator);
        self.map.deinit(self.allocator);
    }

    pub fn intern(self: *Interner, name: []const u8) !Sym {
        if (self.map.get(name)) |id| return id;
        const id: Sym = @intCast(self.names.items.len);
        const owned = try self.allocator.dupe(u8, name);
        try self.names.append(self.allocator, owned);
        try self.map.put(self.allocator, owned, id);
        return id;
    }

    pub fn resolve(self: *const Interner, id: Sym) []const u8 {
        return self.names.items[id];
    }

    pub fn lookup(self: *const Interner, name: []const u8) ?Sym {
        return self.map.get(name);
    }

    pub fn getOrCreateIntZero(self: *Store) !Id {
        return self.int(0);
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// HASHING
// ═══════════════════════════════════════════════════════════════════════════════

pub fn nodeHash(store: *const Store, id: Id) u64 {
    const node = store.get(id);
    var h: u64 = 0xcbf29ce484222325;
    const prime: u64 = 0x100000001b3;
    h ^= @as(u64, @intFromEnum(node.tag));
    h *%= prime;

    switch (node.tag) {
        .sym, .hole => {
            h ^= @as(u64, node.payload);
            h *%= prime;
        },
        .lit => {
            h ^= store.getLit(id).hash();
            h *%= prime;
        },
        .apply => {
            h ^= @as(u64, node.payload);
            h *%= prime;
            for (node.span_a.slice(store.pool.items)) |child| {
                h ^= nodeHash(store, child);
                h *%= prime;
            }
        },
        .bind, .let_in, .lambda => {
            h ^= @as(u64, node.payload);
            h *%= prime;
            h ^= @as(u64, node.aux);
            h *%= prime;
            for (node.span_a.slice(store.pool.items)) |child| {
                h ^= nodeHash(store, child);
                h *%= prime;
            }
        },
        .relation => {
            h ^= @as(u64, node.payload);
            h *%= prime;
            for (node.span_a.slice(store.pool.items)) |child| {
                h ^= nodeHash(store, child);
                h *%= prime;
            }
            for (node.span_b.slice(store.pool.items)) |child| {
                h ^= nodeHash(store, child);
                h *%= prime;
            }
        },
        .list_nil => return 0x9e3779b9,
        .list_cons => {
            const h_head = nodeHash(store, node.span_a.start);
            const h_tail = nodeHash(store, node.span_b.start);
            return h_head ^ (h_tail +% 0x9e3779b9 +% (h_head << 6) +% (h_head >> 2));
        },
        .quote, .unquote => {
            h ^= nodeHash(store, node.payload);
            h *%= prime;
        },
        .perform => {
            h ^= @as(u64, node.payload);
            h *%= prime;
            for (node.span_a.slice(store.pool.items)) |child| {
                h ^= nodeHash(store, child);
                h *%= prime;
            }
        },
        .handle => {
            h ^= nodeHash(store, node.payload);
            h *%= prime;
            h ^= nodeHash(store, node.aux);
            h *%= prime;
        },
        else => {},
    }
    return h;
}

pub fn nodeEql(store: *const Store, a: Id, b: Id) bool {
    if (a == b) return true;
    const na = store.get(a);
    const nb = store.get(b);
    if (na.tag != nb.tag) return false;

    if (na.tag == .apply) {
        if (!nodeEql(store, na.payload, nb.payload)) return false;
    } else {
        if (na.payload != nb.payload) return false;
    }
    if (na.aux != nb.aux) return false;

    const p = store.pool.items;
    if (!std.mem.eql(Id, na.span_a.slice(p), nb.span_a.slice(p))) return false;
    return std.mem.eql(Id, na.span_b.slice(p), nb.span_b.slice(p));
}

// ═══════════════════════════════════════════════════════════════════════════════
// FORMAT
// ═══════════════════════════════════════════════════════════════════════════════

pub fn format(store: *const Store, id: Id, buf: *std.ArrayListUnmanaged(u8), alloc: Allocator) !void {
    const node = store.get(id);
    const p = store.pool.items;

    switch (node.tag) {
        .sym => try buf.appendSlice(alloc, store.interner.resolve(node.payload)),
        .lit => {
            const l = store.lits.items[node.aux];
            switch (l) {
                .int => |v| {
                    var tmp: [32]u8 = undefined;
                    try buf.appendSlice(alloc, std.fmt.bufPrint(&tmp, "{d}", .{v}) catch "?");
                },
                .float => |v| {
                    var tmp: [64]u8 = undefined;
                    try buf.appendSlice(alloc, std.fmt.bufPrint(&tmp, "{d:.4}", .{v}) catch "?");
                },
                .str => |v| {
                    try buf.append(alloc, '"');
                    try buf.appendSlice(alloc, store.interner.resolve(v));
                    try buf.append(alloc, '"');
                },
                .boolean => |v| try buf.appendSlice(alloc, if (v) "true" else "false"),
                .unit => try buf.appendSlice(alloc, "()"),
                .runtime => |v| {
                    try buf.appendSlice(alloc, "@runtime(");
                    switch (v) {
                        .theorem => |vid| {
                            var tmp: [16]u8 = undefined;
                            try buf.appendSlice(alloc, "theorem:");
                            try buf.appendSlice(alloc, std.fmt.bufPrint(&tmp, "{d}", .{vid}) catch "?");
                        },
                        .proof => |vid| {
                            var tmp: [16]u8 = undefined;
                            try buf.appendSlice(alloc, "proof:");
                            try buf.appendSlice(alloc, std.fmt.bufPrint(&tmp, "{d}", .{vid}) catch "?");
                        },
                        .skill => |vid| {
                            var tmp: [16]u8 = undefined;
                            try buf.appendSlice(alloc, "skill:");
                            try buf.appendSlice(alloc, std.fmt.bufPrint(&tmp, "{d}", .{vid}) catch "?");
                        },
                        .agent => |vid| {
                            var tmp: [16]u8 = undefined;
                            try buf.appendSlice(alloc, "agent:");
                            try buf.appendSlice(alloc, std.fmt.bufPrint(&tmp, "{d}", .{vid}) catch "?");
                        },
                    }
                    try buf.append(alloc, ')');
                },
            }
        },
        .apply => {
            try buf.append(alloc, '(');
            try format(store, node.payload, buf, alloc);
            for (node.span_a.slice(p)) |arg| {
                try buf.append(alloc, ' ');
                try format(store, arg, buf, alloc);
            }
            try buf.append(alloc, ')');
        },
        .bind => {
            try buf.appendSlice(alloc, store.interner.resolve(node.payload));
            try buf.appendSlice(alloc, " := ");
            try format(store, node.aux, buf, alloc);
        },
        .relation => {
            try buf.appendSlice(alloc, store.interner.resolve(node.payload));
            try buf.append(alloc, '(');
            for (node.span_a.slice(p), 0..) |arg, i| {
                if (i > 0) try buf.appendSlice(alloc, ", ");
                try format(store, arg, buf, alloc);
            }
            try buf.append(alloc, ')');
            const body_slice = node.span_b.slice(p);
            if (body_slice.len > 0) {
                try buf.appendSlice(alloc, " :- ");
                for (body_slice, 0..) |cond, i| {
                    if (i > 0) try buf.appendSlice(alloc, ", ");
                    try format(store, cond, buf, alloc);
                }
            }
            try buf.append(alloc, '.');
        },
        .hole => {
            try buf.append(alloc, '_');
            var tmp: [16]u8 = undefined;
            try buf.appendSlice(alloc, std.fmt.bufPrint(&tmp, "{d}", .{node.payload}) catch "?");
        },
        .list_nil => try buf.appendSlice(alloc, "[]"),
        .source_file, .block => {
            try buf.append(alloc, '{');
            for (node.span_a.slice(p), 0..) |child, i| {
                if (i > 0) try buf.appendSlice(alloc, "; ");
                try format(store, child, buf, alloc);
            }
            try buf.append(alloc, '}');
        },
        .list_cons => try buf.appendSlice(alloc, "(cons)"),
        .let_in => {
            try buf.appendSlice(alloc, "(let ");
            try buf.appendSlice(alloc, store.interner.resolve(node.payload));
            try buf.appendSlice(alloc, " = ");
            try format(store, node.aux, buf, alloc);
            try buf.appendSlice(alloc, " in ");
            if (node.span_a.slice(p).len > 0) try format(store, node.span_a.slice(p)[0], buf, alloc);
            try buf.appendSlice(alloc, ")");
        },
        .lambda => {
            try buf.appendSlice(alloc, "(\\");
            try buf.appendSlice(alloc, store.interner.resolve(node.payload));
            try buf.appendSlice(alloc, ". ");
            if (node.span_a.slice(p).len > 0) try format(store, node.span_a.slice(p)[0], buf, alloc);
            try buf.appendSlice(alloc, ")");
        },
        .quote => {
            try buf.appendSlice(alloc, "(quote ");
            try format(store, node.payload, buf, alloc);
            try buf.append(alloc, ')');
        },
        .unquote => {
            try buf.appendSlice(alloc, "(unquote ");
            try format(store, node.payload, buf, alloc);
            try buf.append(alloc, ')');
        },
        else => try buf.appendSlice(alloc, ""),
    }
}

pub fn toString(store: *const Store, id: Id, allocator: Allocator) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);
    try format(store, id, &buf, allocator);
    return buf.toOwnedSlice(allocator);
}

pub fn formatInfix(store: *const Store, id: Id, buf: *std.ArrayListUnmanaged(u8), alloc: Allocator) !void {
    const node = store.get(id);
    const p = store.pool.items;

    switch (node.tag) {
        .apply => {
            const op_node = store.get(node.payload);
            if (op_node.tag == .sym) {
                const op_name = store.interner.resolve(op_node.payload);
                const args = node.span_a.slice(p);
                if (args.len == 2 and isInfix(op_name)) {
                    try buf.append(alloc, '(');
                    try formatInfix(store, args[0], buf, alloc);
                    try buf.append(alloc, ' ');
                    try buf.appendSlice(alloc, op_name);
                    try buf.append(alloc, ' ');
                    try formatInfix(store, args[1], buf, alloc);
                    try buf.append(alloc, ')');
                    return;
                }
                if (args.len > 2 and isInfix(op_name)) {
                    try buf.append(alloc, '(');
                    for (args, 0..) |arg, i| {
                        if (i > 0) {
                            try buf.append(alloc, ' ');
                            try buf.appendSlice(alloc, op_name);
                            try buf.append(alloc, ' ');
                        }
                        try formatInfix(store, arg, buf, alloc);
                    }
                    try buf.append(alloc, ')');
                    return;
                }
            }
            try buf.append(alloc, '(');
            try formatInfix(store, node.payload, buf, alloc);
            for (node.span_a.slice(p)) |arg| {
                try buf.append(alloc, ' ');
                try formatInfix(store, arg, buf, alloc);
            }
            try buf.append(alloc, ')');
        },
        .let_in => {
            try buf.appendSlice(alloc, "(let ");
            try buf.appendSlice(alloc, store.interner.resolve(node.payload));
            try buf.appendSlice(alloc, " = ");
            try format(store, node.aux, buf, alloc);
            try buf.appendSlice(alloc, " in ");
            if (node.span_a.slice(p).len > 0) try format(store, node.span_a.slice(p)[0], buf, alloc);
            try buf.appendSlice(alloc, ")");
        },
        .lambda => {
            try buf.appendSlice(alloc, "(\\");
            try buf.appendSlice(alloc, store.interner.resolve(node.payload));
            try buf.appendSlice(alloc, ". ");
            if (node.span_a.slice(p).len > 0) try format(store, node.span_a.slice(p)[0], buf, alloc);
            try buf.appendSlice(alloc, ")");
        },
        .quote => {
            try buf.appendSlice(alloc, "(quote ");
            try format(store, node.payload, buf, alloc);
            try buf.append(alloc, ')');
        },
        .unquote => {
            try buf.appendSlice(alloc, "(unquote ");
            try format(store, node.payload, buf, alloc);
            try buf.append(alloc, ')');
        },
        else => try format(store, id, buf, alloc),
    }
}

pub fn toStringInfix(store: *const Store, id: Id, allocator: Allocator) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);
    try formatInfix(store, id, &buf, allocator);
    return buf.toOwnedSlice(allocator);
}

// ═══════════════════════════════════════════════════════════════════════════════
// SUBSTITUTION
// ═══════════════════════════════════════════════════════════════════════════════

pub fn substitute(store: *Store, root: Id, bindings: []const ?Id) !Id {
    const node = store.get(root);
    const p = store.pool.items;

    switch (node.tag) {
        .hole => {
            if (node.payload < bindings.len) {
                if (bindings[node.payload]) |bound| return bound;
            }
            return root;
        },
        .sym, .lit => return root,
        .apply => {
            const new_func = try substitute(store, node.payload, bindings);
            var new_args = std.ArrayListUnmanaged(Id){};
            defer new_args.deinit(store.allocator);
            for (node.span_a.slice(p)) |arg| {
                try new_args.append(store.allocator, try substitute(store, arg, bindings));
            }
            return store.apply(new_func, new_args.items);
        },
        .bind => {
            const new_val = try substitute(store, node.aux, bindings);
            return store.push(.{ .tag = .bind, .payload = node.payload, .aux = new_val });
        },
        .relation => {
            var new_args = std.ArrayListUnmanaged(Id){};
            defer new_args.deinit(store.allocator);
            for (node.span_a.slice(p)) |arg| {
                try new_args.append(store.allocator, try substitute(store, arg, bindings));
            }
            var new_body = std.ArrayListUnmanaged(Id){};
            defer new_body.deinit(store.allocator);
            for (node.span_b.slice(p)) |b| {
                try new_body.append(store.allocator, try substitute(store, b, bindings));
            }
            const sa = try store.pushSpan(new_args.items);
            const sb = try store.pushSpan(new_body.items);
            return store.push(.{ .tag = .relation, .payload = node.payload, .span_a = sa, .span_b = sb });
        },
        .let_in, .lambda => {
            const new_aux = try substitute(store, node.aux, bindings);
            var new_span = std.ArrayListUnmanaged(Id){};
            defer new_span.deinit(store.allocator);
            for (node.span_a.slice(p)) |child| {
                try new_span.append(store.allocator, try substitute(store, child, bindings));
            }
            const sa = try store.pushSpan(new_span.items);
            return store.push(.{ .tag = node.tag, .payload = node.payload, .aux = new_aux, .span_a = sa });
        },
        .list_nil => return root,
        .list_cons => {
            const new_head = try substitute(store, node.span_a.start, bindings);
            const new_tail = try substitute(store, node.span_b.start, bindings);
            return store.push(.{
                .tag = .list_cons,
                .span_a = .{ .start = new_head, .len = 0 },
                .span_b = .{ .start = new_tail, .len = 0 },
            });
        },
        .quote, .unquote => {
            const new_payload = try substitute(store, node.payload, bindings);
            return store.push(.{ .tag = node.tag, .payload = new_payload });
        },
        .perform => {
            var new_args = std.ArrayListUnmanaged(Id){};
            defer new_args.deinit(store.allocator);
            for (node.span_a.slice(p)) |arg| {
                try new_args.append(store.allocator, try substitute(store, arg, bindings));
            }
            const sa = try store.pushSpan(new_args.items);
            return store.push(.{ .tag = .perform, .payload = node.payload, .span_a = sa });
        },
        .handle => {
            const new_payload = try substitute(store, node.payload, bindings);
            const new_aux = try substitute(store, node.aux, bindings);
            return store.push(.{ .tag = .handle, .payload = new_payload, .aux = new_aux });
        },
        else => return root,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "factorial" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const n = try store.sym("n");
    const one = try store.int(1);
    const k = try store.sym("k");
    const prod = try store.aggregate("Π", "k", one, n, k);
    const lam = try store.lambda(&.{"n"}, prod);
    const def = try store.bind("factorial", lam);

    const s = try toString(&store, def, allocator);
    defer allocator.free(s);
    try std.testing.expectEqualStrings("factorial := (λ n (Π k 1 n k))", s);
}

test "mortal" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const socrate = try store.sym("socrate");
    const fact = try store.relation("mortal", &.{socrate}, &.{});
    const s1 = try toString(&store, fact, allocator);
    defer allocator.free(s1);
    try std.testing.expectEqualStrings("mortal(socrate).", s1);
}

test "physics" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const m = try store.sym("m");
    const a = try store.sym("a");
    const ma = try store.binop("*", m, a);
    const def = try store.bind("F", ma);

    const s = try toString(&store, def, allocator);
    defer allocator.free(s);
    try std.testing.expectEqualStrings("F := (* m a)", s);
}

test "hash consistency" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const a1 = try store.call("+", &.{ try store.int(1), try store.int(2) });
    try std.testing.expect(nodeHash(&store, a1) == nodeHash(&store, a1));

    const a2 = try store.call("*", &.{ try store.int(1), try store.int(2) });
    try std.testing.expect(nodeHash(&store, a1) != nodeHash(&store, a2));
}

test "substitution" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const h = try store.hole(0);
    const pattern = try store.call("mortal", &.{h});
    const socrate = try store.sym("socrate");
    const result = try substitute(&store, pattern, &.{socrate});

    const s = try toString(&store, result, allocator);
    defer allocator.free(s);
    try std.testing.expectEqualStrings("(mortal socrate)", s);
}

test "lower let_in to apply+lambda" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const x = try store.sym("x");
    const five = try store.int(5);
    const body = try store.binop("+", x, x);

    // let x = 5 in x + x  (extension)
    const let_expr = try store.letIn("x", five, body);
    try std.testing.expect(store.get(let_expr).tag == .let_in);

    // Lowering → apply(lambda(x, x+x), 5)  (primitives uniquement)
    const lowered = try store.lower(let_expr);
    const node = store.get(lowered);
    try std.testing.expect(node.tag == .apply);

    const func = store.get(node.payload);
    try std.testing.expect(func.tag == .lambda);

    const args = node.span_a.slice(store.pool.items);
    try std.testing.expect(args.len == 1);
    try std.testing.expect(args[0] == five);
}

test "lower hole to sym" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const h = try store.hole(42);
    const lowered = try store.lower(h);
    const node = store.get(lowered);
    try std.testing.expect(node.tag == .sym);
    try std.testing.expect(std.mem.eql(u8, store.interner.resolve(node.payload), "_"));
}

test "lower list to apply" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const a = try store.int(1);
    const b = try store.int(2);
    const cons = try store.listCons(a, b);
    const lowered = try store.lower(cons);
    const node = store.get(lowered);
    try std.testing.expect(node.tag == .apply);
    const func = store.get(node.payload);
    try std.testing.expect(func.tag == .sym);
    try std.testing.expect(std.mem.eql(u8, store.interner.resolve(func.payload), "Cons"));
}

/// Comparaison structurelle de deux expressions
pub fn exprStructuralEq(store: *const Store, a: Id, b: Id) bool {
    if (a == b) return true;
    const node_a = store.get(a);
    const node_b = store.get(b);
    if (node_a.tag != node_b.tag) return false;

    return switch (node_a.tag) {
        .sym => node_a.payload == node_b.payload,
        .lit => {
            const lit_a = store.lits.items[node_a.aux];
            const lit_b = store.lits.items[node_b.aux];
            return std.meta.eql(lit_a, lit_b);
        },
        .apply => {
            if (!exprStructuralEq(store, node_a.payload, node_b.payload)) return false;
            const args_a = node_a.span_a.slice(store.pool.items);
            const args_b = node_b.span_a.slice(store.pool.items);
            if (args_a.len != args_b.len) return false;
            for (args_a, 0..) |arg_a, i| {
                if (!exprStructuralEq(store, arg_a, args_b[i])) return false;
            }
            return true;
        },
        .bind => {
            if (node_a.payload != node_b.payload) return false;
            return exprStructuralEq(store, node_a.aux, node_b.aux);
        },
        else => false,
    };
}
