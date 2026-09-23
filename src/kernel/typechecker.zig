const std = @import("std");
const ast = @import("ast.zig");

pub const TypeError = error{
    NotAType,
    TypeMismatch,
    UnboundVariable,
    OutOfMemory,
};

pub const Context = std.ArrayList(ast.Term);

pub const TypeChecker = struct {
    allocator: std.mem.Allocator,
    context: Context,

    pub fn init(allocator: std.mem.Allocator) TypeChecker {
        return .{
            .allocator = allocator,
            .context = .{},
        };
    }

    pub fn deinit(self: *TypeChecker) void {
        self.context.deinit(self.allocator);
    }

    pub fn inferSort(self: *TypeChecker, term: ast.Term) TypeError!ast.Sort {
        const inferred = try self.infer(term);
        return switch (inferred) {
            .sort => |s| s,
            else => TypeError.NotAType,
        };
    }

    pub fn inferPi(self: *TypeChecker, domain: ast.Term, codomain_body: ast.Term) TypeError!ast.Sort {
        const sort_a = try self.inferSort(domain);

        try self.context.append(self.allocator, domain);
        defer _ = self.context.pop();

        const sort_b = try self.inferSort(codomain_body);

        return switch (sort_b) {
            // Imprédicativité : (A : Type_i) -> (B : Prop) est dans Prop
            .prop => ast.Sort.prop,
            .type_sort => |lvl_b| switch (sort_a) {
                .prop => ast.Sort{ .type_sort = lvl_b },
                .type_sort => |lvl_a| ast.Sort{
                    .type_sort = lvl_a.maxWith(lvl_b, self.allocator) catch return TypeError.OutOfMemory,
                },
            },
        };
    }

    pub fn checkSortLeq(self: *TypeChecker, sub: ast.Sort, super: ast.Sort) bool {
        _ = self;
        return switch (sub) {
            .prop => true, // Prop <= Type_i
            .type_sort => |l1| switch (super) {
                .prop => false,
                .type_sort => |l2| {
                    const c1 = l1.getConcrete() orelse 0;
                    const c2 = l2.getConcrete() orelse 0;
                    return c1 <= c2;
                },
            },
        };
    }

    pub fn infer(self: *TypeChecker, term: ast.Term) TypeError!ast.Term {
        return switch (term) {
            .sort => |s| switch (s) {
                .prop => ast.Term{ .sort = .{ .type_sort = .{ .concrete = 0 } } }, // Prop : Type_0
                .type_sort => |l| switch (l) {
                    .concrete => |c| ast.Term{ .sort = .{ .type_sort = .{ .concrete = c + 1 } } }, // Type_i : Type_{i+1}
                    .max => ast.Term{ .sort = .{ .type_sort = .{ .concrete = 1 } } },
                },
            },
            .variable => |idx| {
                if (idx >= self.context.items.len) return TypeError.UnboundVariable;
                return self.context.items[self.context.items.len - 1 - idx];
            },
            .pi => |p| {
                const sort_res = try self.inferPi(p.domain.*, p.codomain.*);
                return ast.Term{ .sort = sort_res };
            },
            .lambda => |l| {
                _ = try self.inferSort(l.domain.*);

                try self.context.append(self.allocator, l.domain.*);
                defer _ = self.context.pop();

                const body_type = try self.infer(l.body.*);

                const dom_ptr = try self.allocator.create(ast.Term);
                const body_type_ptr = try self.allocator.create(ast.Term);
                dom_ptr.* = l.domain.*;
                body_type_ptr.* = body_type;

                return ast.Term{
                    .pi = .{
                        .name = l.name,
                        .domain = dom_ptr,
                        .codomain = body_type_ptr,
                    },
                };
            },
            .app => |a| {
                const fn_type = try self.infer(a.func.*);
                switch (fn_type) {
                    .pi => |p| {
                        _ = try self.infer(a.arg.*);
                        return p.codomain.*;
                    },
                    else => return TypeError.TypeMismatch,
                }
            },
            .quot => |q| {
                // 1. A doit être dans Type_i
                const sort_a = try self.inferSort(q.type_a.*);
                // 2. R doit être de type A -> A -> Prop
                _ = try self.infer(q.relation_r.*);
                return ast.Term{ .sort = sort_a };
            },
            .class => |c| {
                const quot_type = try self.infer(c.quot_type.*);
                switch (quot_type) {
                    .quot => return c.quot_type.*,
                    else => return TypeError.TypeMismatch,
                }
            },
            .lift => |l| {
                // lift renvoie la fonction Quot(A, R) -> B
                const domain_ptr = try self.allocator.create(ast.Term);
                const codomain_ptr = try self.allocator.create(ast.Term);
                domain_ptr.* = l.quot_type.*;
                codomain_ptr.* = l.target_b.*;

                return ast.Term{
                    .pi = .{
                        .name = "q",
                        .domain = domain_ptr,
                        .codomain = codomain_ptr,
                    },
                };
            },
        };
    }
};
