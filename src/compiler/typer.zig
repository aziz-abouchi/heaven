const std = @import("std");
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
    }

    pub fn freshVar(self: *Typer) Type {
        const v = self.next_var;
        self.next_var += 1;
        return v;
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
                const pool = self.store.pool.items;
                const args = node.span_a.slice(pool);
                for (args) |arg| {
                    _ = self.infer(arg);
                }
                return self.freshVar();
            },
            .bind => {
                const name = self.store.interner.resolve(node.payload);
                const val_type = self.infer(node.aux);
                self.type_env.put(self.allocator, name, val_type) catch {};
                return val_type;
            },
            .relation => return 0,
            .hole => return self.freshVar(),
            else => unreachable,
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
