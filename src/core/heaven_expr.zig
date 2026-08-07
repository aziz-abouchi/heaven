const std = @import("std");
const expr = @import("expr");
const engine = @import("engine_expr");
const types = @import("types");
const canon = @import("canon");
const pattern = @import("pattern");
const proof = @import("proof");

const Store = expr.Store;
const Id = expr.Id;
const LowerError = expr.LowerError;

pub const HeavenError = error{
    ExtensionNotLowered,
    TypeMismatch,
    EvaluationFailed,
    OutOfMemory,
    InvalidInput,
};

pub const Heaven = struct {
    store: Store,
    env: engine.Env,
    registry: engine.FunctionRegistry,
    type_env: types.TypeEnv,
    proof_core: proof.ProofEnv = .{},
    bridge: Bridge = .{},
    engine: EngineState = .{},

    pub fn init(allocator: std.mem.Allocator) Heaven {
        return .{
            .store = Store.init(allocator),
            .env = engine.Env.init(allocator),
            .registry = engine.FunctionRegistry.init(allocator),
            .type_env = types.TypeEnv.init(allocator),
        };
    }

    pub fn deinit(self: *Heaven) void {
        self.store.deinit();
        self.env.deinit();
        self.registry.deinit();
        self.type_env.deinit();
    }

    pub fn ensureInit(self: *Heaven) void {
        _ = self;
    }

    // Wrapper pour mcp_server.zig qui prend une chaîne et retourne une chaîne
    pub fn eval(self: *Heaven, src: []const u8) HeavenError![]u8 {
        _ = self;
        // Stub temporaire pour faire compiler
        return std.heap.page_allocator.dupe(u8, src) catch return HeavenError.OutOfMemory;
    }

    // Wrapper pour mcp_server.zig (derive)
    pub fn derive(self: *Heaven, expr_str: []const u8, var_name: []const u8) HeavenError![]u8 {
        _ = self;
        _ = var_name;
        // Stub temporaire : retourne l'expression inchangée.
        // La vraie dérivation sera implémentée plus tard avec le pattern matching.
        return std.heap.page_allocator.dupe(u8, expr_str) catch return HeavenError.OutOfMemory;
    }

    // Wrapper pour mcp_server.zig (expand)
    pub fn expand(self: *Heaven, expr_str: []const u8) HeavenError![]u8 {
        _ = self;
        // Stub temporaire
        return std.heap.page_allocator.dupe(u8, expr_str) catch return HeavenError.OutOfMemory;
    }

    // Wrapper pour mcp_server.zig (solve)
    pub fn solve(self: *Heaven, expr_str: []const u8, var_name: []const u8) HeavenError![]u8 {
        _ = self;
        _ = var_name;
        // Stub temporaire
        return std.heap.page_allocator.dupe(u8, expr_str) catch return HeavenError.OutOfMemory;
    }

    // Wrapper pour mcp_server.zig (format)
    pub fn format(self: *Heaven, id: Id) HeavenError![]u8 {
        return self.idToString(id);
    }

    // Stubs pour le shell
    pub const Bridge = struct {
        pub fn importExpr(_: *Bridge, _: []const u8) HeavenError!Id {
            return 0;
        }
    };
    pub const EngineState = struct {
        fuel: u32 = 1000000,
        fns: std.StringHashMapUnmanaged(Id) = .{},
    };

    /// Vérifie qu'un Id est entièrement lowered avant passage au noyau.
    fn ensureLowered(self: *Heaven, id: Id) HeavenError!Id {
        return self.store.lowerRec(id) catch |err| switch (err) {
            error.ExtensionNotLowered => return HeavenError.ExtensionNotLowered,
            error.OutOfMemory => return HeavenError.OutOfMemory,
        };
    }

    /// Simplification : évalue l'expression et retourne une représentation textuelle.
    pub fn simplify(self: *Heaven, src: []const u8) HeavenError![]u8 {
        _ = self;
        // Stub temporaire pour faire compiler mcp_server.zig
        // Le vrai flux (parse -> lower -> evaluate -> print) sera reconnecté ici.
        return std.heap.page_allocator.dupe(u8, src) catch return HeavenError.OutOfMemory;
    }

    /// Canonicalisation AC.
    pub fn canonicalize(self: *Heaven, id: Id) HeavenError![]u8 {
        const lowered = try self.ensureLowered(id);
        const result = canon.canonicalizeAC(&self.store, lowered) catch |err| switch (err) {
            error.OutOfMemory => return HeavenError.OutOfMemory,
        };
        return try self.idToString(result);
    }

    /// Pattern matching.
    pub fn matchPattern(self: *Heaven, pattern_id: Id, target: Id) HeavenError!bool {
        const p = try self.ensureLowered(pattern_id);
        const t = try self.ensureLowered(target);
        var bindings = pattern.Bindings.init(self.store.allocator);
        defer bindings.deinit();
        return pattern.match(&self.store, p, t, &bindings) catch |err| switch (err) {
            error.OutOfMemory => return HeavenError.OutOfMemory,
            error.MatchFailed => return false,
        };
    }

    /// Preuve Peano.
    pub fn provePeano(self: *Heaven, id: Id, axiom: proof.PeanoAxiom) HeavenError![]u8 {
        const lowered = try self.ensureLowered(id);
        const result = proof.rewritePeano(&self.store, lowered, axiom) catch |err| switch (err) {
            error.OutOfMemory => return HeavenError.OutOfMemory,
            else => return HeavenError.EvaluationFailed,
        };
        return try self.idToString(result);
    }

    // --- Helpers de sérialisation ---

    fn idToString(self: *Heaven, id: Id) HeavenError![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(self.store.allocator);
        try self.serializeId(id, &buf);
        return buf.toOwnedSlice(self.store.allocator) catch return HeavenError.OutOfMemory;
    }

    fn typeToString(self: *Heaven, ty: *types.Type) HeavenError![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(self.store.allocator);
        try self.serializeType(ty, &buf);
        return buf.toOwnedSlice(self.store.allocator) catch return HeavenError.OutOfMemory;
    }

    fn serializeId(self: *Heaven, id: Id, buf: *std.ArrayList(u8)) HeavenError!void {
        const node = self.store.get(id);
        switch (node.tag) {
            .lit => {
                const lit = self.store.lits.items[node.aux];
                switch (lit) {
                    .int => |v| buf.writer(self.store.allocator).print("{d}", .{v}) catch return HeavenError.OutOfMemory,
                    .float => |v| buf.writer(self.store.allocator).print("{d}", .{v}) catch return HeavenError.OutOfMemory,
                    .boolean => |v| buf.appendSlice(self.store.allocator, if (v) "true" else "false") catch return HeavenError.OutOfMemory,
                    .str => |v| {
                        buf.append(self.store.allocator, '"') catch return HeavenError.OutOfMemory;
                        buf.appendSlice(self.store.allocator, self.store.interner.resolve(v)) catch return HeavenError.OutOfMemory;
                        buf.append(self.store.allocator, '"') catch return HeavenError.OutOfMemory;
                    },
                    .unit => buf.appendSlice(self.store.allocator, "()") catch return HeavenError.OutOfMemory,
                    .runtime => buf.appendSlice(self.store.allocator, "<runtime>") catch return HeavenError.OutOfMemory,
                }
            },
            .sym => {
                buf.appendSlice(self.store.allocator, self.store.interner.resolve(node.payload)) catch return HeavenError.OutOfMemory;
            },
            .apply => {
                buf.append(self.store.allocator, '(') catch return HeavenError.OutOfMemory;
                const pool = self.store.pool.items;
                const args = node.span_a.slice(pool);
                for (args, 0..) |arg, i| {
                    if (i > 0) buf.append(self.store.allocator, ' ') catch return HeavenError.OutOfMemory;
                    try self.serializeId(arg, buf);
                }
                buf.append(self.store.allocator, ')') catch return HeavenError.OutOfMemory;
            },
            .bind => {
                buf.appendSlice(self.store.allocator, "(bind ") catch return HeavenError.OutOfMemory;
                buf.appendSlice(self.store.allocator, self.store.interner.resolve(node.payload)) catch return HeavenError.OutOfMemory;
                buf.append(self.store.allocator, ' ') catch return HeavenError.OutOfMemory;
                const pool = self.store.pool.items;
                const args = node.span_a.slice(pool);
                for (args) |arg| {
                    buf.append(self.store.allocator, ' ') catch return HeavenError.OutOfMemory;
                    try self.serializeId(arg, buf);
                }
                buf.append(self.store.allocator, ')') catch return HeavenError.OutOfMemory;
            },
            .lambda => {
                buf.appendSlice(self.store.allocator, "(lambda ") catch return HeavenError.OutOfMemory;
                buf.appendSlice(self.store.allocator, self.store.interner.resolve(node.payload)) catch return HeavenError.OutOfMemory;
                buf.append(self.store.allocator, ' ') catch return HeavenError.OutOfMemory;
                const pool = self.store.pool.items;
                const args = node.span_a.slice(pool);
                for (args) |arg| {
                    buf.append(self.store.allocator, ' ') catch return HeavenError.OutOfMemory;
                    try self.serializeId(arg, buf);
                }
                buf.append(self.store.allocator, ')') catch return HeavenError.OutOfMemory;
            },
            .relation => {
                buf.append(self.store.allocator, '(') catch return HeavenError.OutOfMemory;
                const pool = self.store.pool.items;
                const args = node.span_a.slice(pool);
                for (args, 0..) |arg, i| {
                    if (i > 0) buf.append(self.store.allocator, ' ') catch return HeavenError.OutOfMemory;
                    try self.serializeId(arg, buf);
                }
                buf.append(self.store.allocator, ')') catch return HeavenError.OutOfMemory;
            },
            else => buf.appendSlice(self.store.allocator, "<?>") catch return HeavenError.OutOfMemory,
        }
    }

    fn serializeType(self: *Heaven, ty: *types.Type, buf: *std.ArrayList(u8)) HeavenError!void {
        switch (ty.*) {
            .var_type => |v| buf.writer(self.store.allocator).print("t{d}", .{v}) catch return HeavenError.OutOfMemory,
            .int => buf.appendSlice(self.store.allocator, "Int") catch return HeavenError.OutOfMemory,
            .float => buf.appendSlice(self.store.allocator, "Float") catch return HeavenError.OutOfMemory,
            .boolType => buf.appendSlice(self.store.allocator, "Bool") catch return HeavenError.OutOfMemory,
            .string => buf.appendSlice(self.store.allocator, "String") catch return HeavenError.OutOfMemory,
            .unit => buf.appendSlice(self.store.allocator, "Unit") catch return HeavenError.OutOfMemory,
            .func_node => |f| {
                buf.append(self.store.allocator, '(') catch return HeavenError.OutOfMemory;
                try self.serializeType(f.arg, buf);
                buf.appendSlice(self.store.allocator, " -> ") catch return HeavenError.OutOfMemory;
                try self.serializeType(f.ret, buf);
                buf.append(self.store.allocator, ')') catch return HeavenError.OutOfMemory;
            },
            .tuple_type => |ts| {
                buf.append(self.store.allocator, '(') catch return HeavenError.OutOfMemory;
                for (ts, 0..) |t, i| {
                    if (i > 0) buf.appendSlice(self.store.allocator, ", ") catch return HeavenError.OutOfMemory;
                    try self.serializeType(t, buf);
                }
                buf.append(self.store.allocator, ')') catch return HeavenError.OutOfMemory;
            },
            .relation_type => |r| {
                try self.serializeType(r.lhs, buf);
                buf.appendSlice(self.store.allocator, " = ") catch return HeavenError.OutOfMemory;
                try self.serializeType(r.rhs, buf);
            },
        }
    }

    // --- Stubs pour le frontend (commands.zig, mcp_server.zig, etc.) ---
    /// Inférence de type HM.
    pub fn typeOf(self: *Heaven, src: []const u8) HeavenError![]u8 {
        _ = self;
        // Stub temporaire pour faire compiler commands.zig
        return std.heap.page_allocator.dupe(u8, src) catch return HeavenError.OutOfMemory;
    }
    pub fn evalSkill(self: *Heaven, src: []const u8) HeavenError![]u8 {
        _ = self;
        return std.heap.page_allocator.dupe(u8, src) catch return HeavenError.OutOfMemory;
    }
    pub fn evalProve(self: *Heaven, src: []const u8) HeavenError![]u8 {
        _ = self;
        return std.heap.page_allocator.dupe(u8, src) catch return HeavenError.OutOfMemory;
    }
    pub fn dumpAst(self: *Heaven, src: []const u8) HeavenError![]u8 {
        _ = self;
        return std.heap.page_allocator.dupe(u8, src) catch return HeavenError.OutOfMemory;
    }
    pub fn toLaTeXInline(self: *Heaven, id: Id) HeavenError![]u8 {
        _ = self;
        _ = id;
        return std.heap.page_allocator.dupe(u8, "") catch return HeavenError.OutOfMemory;
    }
    pub fn explain(self: *Heaven, src: []const u8) HeavenError![]u8 {
        _ = self;
        return std.heap.page_allocator.dupe(u8, src) catch return HeavenError.OutOfMemory;
    }
    pub fn describeKB(self: *Heaven) HeavenError![]u8 {
        _ = self;
        return std.heap.page_allocator.dupe(u8, "KB: stub") catch return HeavenError.OutOfMemory;
    }
    pub fn toC(self: *Heaven, ids: []const Id) HeavenError![]u8 {
        _ = self;
        _ = ids;
        return std.heap.page_allocator.dupe(u8, "// stub") catch return HeavenError.OutOfMemory;
    }
    pub fn integrate(self: *Heaven, expression: []const u8, var_name: []const u8) HeavenError![]u8 {
        _ = self;
        _ = var_name;
        return std.heap.page_allocator.dupe(u8, expression) catch return HeavenError.OutOfMemory;
    }
    pub fn plot(self: *Heaven, expression: []const u8, var_name: []const u8) HeavenError![]u8 {
        _ = self;
        _ = var_name;
        return std.heap.page_allocator.dupe(u8, expression) catch return HeavenError.OutOfMemory;
    }
    pub fn evalTheorem(self: *Heaven, src: []const u8) HeavenError![]u8 {
        _ = self;
        return std.heap.page_allocator.dupe(u8, src) catch return HeavenError.OutOfMemory;
    }
    pub fn substExpr(self: *Heaven, expression: []const u8, var_name: []const u8, val: []const u8) HeavenError![]u8 {
        _ = self;
        _ = var_name;
        _ = val;
        return std.heap.page_allocator.dupe(u8, expression) catch return HeavenError.OutOfMemory;
    }
    pub fn listRules(self: *Heaven) HeavenError![]u8 {
        _ = self;
        return std.heap.page_allocator.dupe(u8, "[]") catch return HeavenError.OutOfMemory;
    }
    pub fn evalSExpr(self: *Heaven, src: []const u8) HeavenError![]u8 {
        _ = self;
        return std.heap.page_allocator.dupe(u8, src) catch return HeavenError.OutOfMemory;
    }
};
