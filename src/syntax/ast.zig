//! Heaven Syntax AST / HIR léger.
//!
//! Cette couche est indépendante de Tree-sitter.
//! Tree-sitter produit le CST ; syntax/lower.zig produit ce HIR.
//! Le HIR est ensuite consommé par core/lowering.zig / elaboration.

const std = @import("std");

pub const Allocator = std.mem.Allocator;

pub const Span = struct {
    start: u32 = 0,
    end: u32 = 0,
};

pub const Ast = struct {
    allocator: Allocator,
    source: []const u8,
    items: []Item = &.{},

    pub fn init(
        allocator: Allocator,
        source: []const u8,
        items: []Item,
    ) Ast {
        return .{
            .allocator = allocator,
            .source = source,
            .items = items,
        };
    }

    pub fn deinit(self: *Ast) void {
        for (self.items) |*item| item.deinit(self.allocator);
        if (self.items.len != 0) self.allocator.free(self.items);
        self.items = &.{};
    }
};

pub const Item = union(enum) {
    equation: Equation,
    data_decl: DataDecl,
    axiom_decl: AxiomDecl,
    theorem_decl: TheoremDecl,
    proof_decl: ProofDecl,
    fn_decl: FunctionDecl,

    pub fn deinit(self: *Item, allocator: Allocator) void {
        switch (self.*) {
            .equation => |*x| x.deinit(allocator),
            .data_decl => |*x| x.deinit(allocator),
            .axiom_decl => |*x| x.deinit(allocator),
            .theorem_decl => |*x| x.deinit(allocator),
            .proof_decl => |*x| x.deinit(allocator),
            .fn_decl => |*x| x.deinit(allocator),
        }
    }
};

pub const Equation = struct {
    name: []const u8,
    patterns: []Pattern,
    body: Expr,
    span: Span = .{},

    pub fn deinit(self: *Equation, allocator: Allocator) void {
        if (self.patterns.len != 0) allocator.free(self.patterns);
        self.body.deinit(allocator);
    }
};

pub const FunctionDecl = struct {
    name: []const u8,
    params: []const []const u8,
    body: Expr,
    span: Span = .{},

    pub fn deinit(self: *FunctionDecl, allocator: Allocator) void {
        self.body.deinit(allocator);
        if (self.params.len != 0) allocator.free(self.params);
    }
};

pub const DataDecl = struct {
    name: []const u8,
    constructors: []DataConstructor,
    span: Span = .{},

    pub fn deinit(self: *DataDecl, allocator: Allocator) void {
        for (self.constructors) |*ctor| ctor.deinit(allocator);
        if (self.constructors.len != 0) allocator.free(self.constructors);
    }
};

pub const DataConstructor = struct {
    name: []const u8,
    args: []TypeExpr,

    pub fn deinit(self: *DataConstructor, allocator: Allocator) void {
        for (self.args) |*arg| arg.deinit(allocator);
        if (self.args.len != 0) allocator.free(self.args);
    }
};

pub const AxiomDecl = struct {
    name: []const u8,
    proposition: TypeExpr,
    span: Span = .{},

    pub fn deinit(self: *AxiomDecl, allocator: Allocator) void {
        self.proposition.deinit(allocator);
    }
};

pub const TheoremDecl = struct {
    name: []const u8,
    proposition: TypeExpr,
    proof: ?ProofBlock = null,
    span: Span = .{},

    pub fn deinit(self: *TheoremDecl, allocator: Allocator) void {
        self.proposition.deinit(allocator);
        if (self.proof) |*p| p.deinit(allocator);
    }
};

pub const ProofDecl = struct {
    name: []const u8,
    strategy: ?ProofStrategy = null,
    steps: []ProofStep = &.{},
    span: Span = .{},

    pub fn deinit(self: *ProofDecl, allocator: Allocator) void {
        if (self.strategy) |*s| s.deinit(allocator);
        for (self.steps) |*step| step.deinit(allocator);
        if (self.steps.len != 0) allocator.free(self.steps);
    }
};

pub const ProofBlock = struct {
    strategy: ?ProofStrategy = null,
    steps: []ProofStep = &.{},

    pub fn deinit(self: *ProofBlock, allocator: Allocator) void {
        if (self.strategy) |*s| s.deinit(allocator);
        for (self.steps) |*step| step.deinit(allocator);
        if (self.steps.len != 0) allocator.free(self.steps);
    }
};

pub const ProofStrategy = union(enum) {
    induction: []const u8,
    cases: []const u8,
    contradiction,
    trivial,
    construction,
    information_theory,
    named: []const u8,

    pub fn deinit(self: *ProofStrategy, allocator: Allocator) void {
        _ = allocator;
        _ = self;
    }
};

pub const ProofStep = union(enum) {
    case_step: struct {
        pattern: Pattern,
        steps: []ProofStep,
    },
    apply: Expr,
    rewrite: Expr,
    assume: struct {
        name: []const u8,
        proposition: Expr,
    },
    have: struct {
        name: []const u8,
        proposition: Expr,
        proof: Expr,
    },
    construct: Expr,
    trivial,
    qed,

    pub fn deinit(self: *ProofStep, allocator: Allocator) void {
        switch (self.*) {
            .case_step => |*x| {
                x.pattern.deinit(allocator);
                for (x.steps) |*s| s.deinit(allocator);
                if (x.steps.len != 0) allocator.free(x.steps);
            },
            .apply => |*x| x.deinit(allocator),
            .rewrite => |*x| x.deinit(allocator),
            .assume => |*x| x.proposition.deinit(allocator),
            .have => |*x| {
                x.proposition.deinit(allocator);
                x.proof.deinit(allocator);
            },
            .construct => |*x| x.deinit(allocator),
            .trivial, .qed => {},
        }
    }
};

pub const Pattern = union(enum) {
    variable: []const u8,
    constructor: struct {
        name: []const u8,
        args: []Pattern,
    },
    int: i64,
    float: f64,
    string: []const u8,
    boolean: bool,
    wildcard,
    tuple: []Pattern,
    list: []Pattern,

    pub fn deinit(self: *Pattern, allocator: Allocator) void {
        switch (self.*) {
            .constructor => |*x| {
                for (x.args) |*arg| arg.deinit(allocator);
                if (x.args.len != 0) allocator.free(x.args);
            },
            .tuple, .list => |items| {
                for (items) |*item| item.deinit(allocator);
                if (items.len != 0) allocator.free(items);
            },
            else => {},
        }
    }
};

pub const Expr = union(enum) {
    identifier: []const u8,
    int: i64,
    float: f64,
    string: []const u8,
    boolean: bool,

    call: struct {
        callee: *Expr,
        args: []Expr,
    },

    binary: struct {
        op: []const u8,
        lhs: *Expr,
        rhs: *Expr,
    },

    unary: struct {
        op: []const u8,
        operand: *Expr,
    },

    application: []Expr,
    parenthesized: *Expr,

    pub fn deinit(self: *Expr, allocator: Allocator) void {
        switch (self.*) {
            .call => |*x| {
                x.callee.deinit(allocator);
                allocator.destroy(x.callee);
                for (x.args) |*arg| arg.deinit(allocator);
                if (x.args.len != 0) allocator.free(x.args);
            },
            .binary => |*x| {
                x.lhs.deinit(allocator);
                x.rhs.deinit(allocator);
                allocator.destroy(x.lhs);
                allocator.destroy(x.rhs);
            },
            .unary => |*x| {
                x.operand.deinit(allocator);
                allocator.destroy(x.operand);
            },
            .application => |items| {
                for (items) |*item| item.deinit(allocator);
                if (items.len != 0) allocator.free(items);
            },
            .parenthesized => |x| {
                x.deinit(allocator);
                allocator.destroy(x);
            },
            else => {},
        }
    }
};

pub const TypeExpr = union(enum) {
    named: []const u8,

    generic: struct {
        name: []const u8,
        args: []TypeExpr,
    },

    applied: struct {
        name: []const u8,
        args: []TypeExpr,
    },

    arrow: struct {
        from: *TypeExpr,
        to: *TypeExpr,
    },

    forall: struct {
        binders: []Binder,
        body: *TypeExpr,
    },

    pub fn deinit(self: *TypeExpr, allocator: Allocator) void {
        switch (self.*) {
            .generic => |*x| {
                for (x.args) |*arg| arg.deinit(allocator);
                if (x.args.len != 0) allocator.free(x.args);
            },
            .applied => |*x| {
                for (x.args) |*arg| arg.deinit(allocator);
                if (x.args.len != 0) allocator.free(x.args);
            },
            .arrow => |*x| {
                x.from.deinit(allocator);
                x.to.deinit(allocator);
                allocator.destroy(x.from);
                allocator.destroy(x.to);
            },
            .forall => |*x| {
                for (x.binders) |*b| b.deinit(allocator);
                if (x.binders.len != 0) allocator.free(x.binders);
                x.body.deinit(allocator);
                allocator.destroy(x.body);
            },
            .named => {},
        }
    }
};

pub const Binder = struct {
    name: []const u8,
    ty: TypeExpr,

    pub fn deinit(self: *Binder, allocator: Allocator) void {
        self.ty.deinit(allocator);
    }
};
