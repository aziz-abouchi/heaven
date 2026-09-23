const std = @import("std");
const ast = @import("ast.zig");
const typechecker = @import("typechecker.zig");

pub const ConversionError = error{
    TypeInferenceFailed,
    OutOfMemory,
} || typechecker.TypeError;

pub const Conversion = struct {
    allocator: std.mem.Allocator,
    tc: *typechecker.TypeChecker,

    pub fn init(allocator: std.mem.Allocator, tc: *typechecker.TypeChecker) Conversion {
        return .{
            .allocator = allocator,
            .tc = tc,
        };
    }

    /// Vérifie l'égalité définitionnelle t1 == t2
    pub fn areEqual(self: *Conversion, t1: ast.Term, t2: ast.Term) ConversionError!bool {
        // 1. Proof Irrelevance : si le type de t1 appartient à Prop,
        // deux preuves de la même proposition sont toujours égales.
        if (self.isProof(t1)) return true;

        // 2. Égalité structurelle (Alpha-Beta conversion)
        return self.alphaBetaEqual(t1, t2);
    }

    fn isProof(self: *Conversion, t: ast.Term) bool {
        const type_t = self.tc.infer(t) catch return false;
        const sort_t = self.tc.inferSort(type_t) catch return false;
        return sort_t == .prop;
    }

    fn alphaBetaEqual(self: *Conversion, t1: ast.Term, t2: ast.Term) ConversionError!bool {
        return switch (t1) {
            .sort => |s1| switch (t2) {
                .sort => |s2| self.sortsEqual(s1, s2),
                else => false,
            },
            .variable => |v1| switch (t2) {
                .variable => |v2| v1 == v2,
                else => false,
            },
            .pi => |p1| switch (t2) {
                .pi => |p2| (try self.alphaBetaEqual(p1.domain.*, p2.domain.*)) and
                    (try self.alphaBetaEqual(p1.codomain.*, p2.codomain.*)),
                else => false,
            },
            .lambda => |l1| switch (t2) {
                .lambda => |l2| (try self.alphaBetaEqual(l1.domain.*, l2.domain.*)) and
                    (try self.alphaBetaEqual(l1.body.*, l2.body.*)),
                else => false,
            },
            .app => |a1| switch (t2) {
                .app => |a2| (try self.alphaBetaEqual(a1.func.*, a2.func.*)) and
                    (try self.alphaBetaEqual(a1.arg.*, a2.arg.*)),
                else => false,
            },
        };
    }

    fn sortsEqual(self: *Conversion, s1: ast.Sort, s2: ast.Sort) bool {
        _ = self;
        return switch (s1) {
            .prop => s2 == .prop,
            .type_sort => |l1| switch (s2) {
                .prop => false,
                .type_sort => |l2| (l1.getConcrete() orelse 0) == (l2.getConcrete() orelse 0),
            },
        };
    }

    pub fn reduceIota(self: *Conversion, term: ast.Term) ConversionError!ast.Term {
        return switch (term) {
            .app => |a| {
                const fn_red = try self.reduceIota(a.func.*);
                const arg_red = try self.reduceIota(a.arg.*);

                // Attrape l'application : lift(A, R, B, f, p) (class(x)) -> f(x)
                switch (fn_red) {
                    .lift => |l| switch (arg_red) {
                        .class => |c| {
                            const app_term = try self.allocator.create(ast.Term);
                            const arg_ptr = try self.allocator.create(ast.Term);
                            app_term.* = l.func_f.*;
                            arg_ptr.* = c.element.*;

                            return ast.Term{
                                .app = .{
                                    .func = app_term,
                                    .arg = arg_ptr,
                                },
                            };
                        },
                        else => {},
                    },
                    else => {},
                }

                const func_ptr = try self.allocator.create(ast.Term);
                const arg_ptr = try self.allocator.create(ast.Term);
                func_ptr.* = fn_red;
                arg_ptr.* = arg_red;
                return ast.Term{ .app = .{ .func = func_ptr, .arg = arg_ptr } };
            },
            .class => |c| {
                const elem_red = try self.reduceIota(c.element.*);
                const elem_ptr = try self.allocator.create(ast.Term);
                elem_ptr.* = elem_red;
                return ast.Term{ .class = .{ .quot_type = c.quot_type, .element = elem_ptr } };
            },
            .lift => |l| {
                const func_red = try self.reduceIota(l.func_f.*);
                const func_ptr = try self.allocator.create(ast.Term);
                func_ptr.* = func_red;
                return ast.Term{
                    .lift = .{
                        .quot_type = l.quot_type,
                        .target_b = l.target_b,
                        .func_f = func_ptr,
                        .proof = l.proof, // La preuve n'a pas besoin d'être réduite (Proof Irrelevance)
                    },
                };
            },
            else => term,
        };
    }
};
