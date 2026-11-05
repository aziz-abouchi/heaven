const std = @import("std");
const platform = @import("platform");
const expr = @import("expr");
const types_mod = @import("types");
const Type = types_mod.Type;
const TypeSubst = types_mod.TypeSubst;
const Store = expr.Store;
const Id = expr.Id;
const Scope = @import("scope.zig").Scope;
const DiagnosticList = @import("diagnostics.zig").DiagnosticList;

pub const Typer = struct {
    store: *const Store,
    subst: TypeSubst,
    next_var: u32 = 0,
    diags: *DiagnosticList,
    type_env: std.StringHashMapUnmanaged(Type) = .{},
    fn_arity: std.StringHashMapUnmanaged(u32) = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, store: *const Store, diags: *DiagnosticList) Typer {
        var self = Typer{
            .store = store,
            .subst = .{},
            .diags = diags,
            .allocator = allocator,
        };
        self.type_env.put(allocator, "+", 0) catch {};
        self.type_env.put(allocator, "-", 0) catch {};
        self.type_env.put(allocator, "print", 0) catch {};
        return self;
    }

    pub fn deinit(self: *Typer) void {
        self.subst.deinit(self.allocator);
        self.type_env.deinit(self.allocator);
        self.fn_arity.deinit(self.allocator);
    }

    pub fn freshVar(self: *Typer) Type {
        const v = self.next_var;
        self.next_var += 1;
        return v;
    }

    /// Compte les params d'une lambda curryfiée : lambda(x, lambda(y, body)) -> 2
    fn countLambdaParams(self: *Typer, id: Id) u32 {
        var count: u32 = 0;
        var cur = id;
        while (cur != expr.NULL and cur < self.store.len()) {
            const n = self.store.get(cur);
            if (n.tag != .lambda) break;
            const body_slice = self.store.spanSliceConst(n.span_a);
            if (body_slice.len == 0) break;
            count += 1;
            const body_id = body_slice[0];
            // Continuer seulement si le body est encore une lambda (curryfiage)
            if (body_id < self.store.len() and self.store.get(body_id).tag == .lambda) {
                cur = body_id;
            } else {
                break;
            }
        }
        return count;
    }

    pub fn infer(self: *Typer, id: Id) Type {
        if (id == expr.NULL) return 0;
        if (id >= self.store.len()) return 0;

        const node = self.store.get(id);
        switch (node.tag) {
            .lit => {
                const l = self.store.lits.items[node.aux];
                return switch (l) {
                    .int => 1, // Stub : on renvoie un ID de type arbitraire
                    .float => 2,
                    .str => 3,
                    .boolean => 4,
                    .unit => 0,
                    .runtime => 5,
                };
            },
            .sym => {
                const name = self.store.interner.resolve(node.payload);
                if (self.type_env.get(name)) |t| return t;
                return self.freshVar();
            },
            .apply => {
                const args = self.store.applyArgs(node);
                for (args) |arg| {
                    _ = self.infer(arg);
                }
                // Vérif arité : si le func est un .sym connu dans fn_arity,
                // comparer args.len à l'arité attendue.
                if (node.payload < self.store.len()) {
                    const fn_node = self.store.get(node.payload);
                    if (fn_node.tag == .sym) {
                        const fname = self.store.interner.resolve(fn_node.payload);
                        if (self.fn_arity.get(fname)) |expected| {
                            const got: u32 = @intCast(args.len);
                            if (got != expected) {
                                const span = node.span_a;
                                const msg = std.fmt.allocPrint(
                                    self.allocator,
                                    "arity mismatch: '{s}' attend {d} argument(s), reçu {d}",
                                    .{ fname, expected, got },
                                ) catch "arity mismatch";
                                self.diags.err(span.start, 0, msg);
                            }
                        }
                    }
                }
                return self.freshVar();
            },
            .bind => {
                const name = self.store.interner.resolve(node.payload);
                const val_type = self.infer(node.aux);
                self.type_env.put(self.allocator, name, val_type) catch {};
                // bind stocke val en span_a[0] (cf. Store.bind l. 919-925)
                const bind_span = self.store.spanSliceConst(node.span_a);
                if (bind_span.len > 0) {
                    const val_id = bind_span[0];
                    if (val_id != expr.NULL and val_id < self.store.len()) {
                        const vnode = self.store.get(val_id);
                        if (vnode.tag == .lambda) {
                            const arity = self.countLambdaParams(val_id);
                            self.fn_arity.put(self.allocator, name, arity) catch {};
                        }
                    }
                }
                return val_type;
            },
            .relation => return 0,
            .hole => return self.freshVar(),
            // Tags ajoutés par ast_bridge pour eq_decl, fn_decl, var_decl, etc.
            .lambda => {
                _ = self.infer(node.aux); // inférer le body
                return self.freshVar();
            },
            .let, .letrec => {
                _ = self.infer(node.aux);
                return self.freshVar();
            },
            .fun => return self.freshVar(),
            // Littéraux alternatifs (post-lowering)
            .int, .float, .string, .true, .false, .var_tag => return self.freshVar(),
            // Fallback safe : pas de panic, juste un type frais.
            // Un tag inconnu ne doit pas tuer le check.
            else => return self.freshVar(),
        }
    }

    pub fn unify(self: *Typer, a: Type, b: Type) bool {
        if (a.eql(b)) return true;
        switch (a) {
            .var_t => |v| {
                self.subst.bind(v, b) catch {};
                return true;
            },
            else => {},
        }
        switch (b) {
            .var_t => |v| {
                self.subst.bind(v, a) catch {};
                return true;
            },
            else => {},
        }
        return false;
    }

    pub fn checkAll(self: *Typer) void {
        const count = self.store.len();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            _ = self.infer(i);
        }
    }

    pub fn typeOf(self: *Typer, id: Id) []const u8 {
        const t = self.infer(id);
        return switch (t) {
            .int_t => "i64",
            .float_t => "f64",
            .bool_t => "Bool",
            .string_t => "String",
            .unit_t => "()",
            .var_t => "?",
            .arrow => "fn",
            .forall => "∀",
        };
    }
};
