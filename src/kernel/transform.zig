const std = @import("std");
const ast = @import("ast.zig");

pub const Provenance = union(enum) {
    Axiom: []const u8,
    Rule: []const u8,
    Sensor: []const u8,
    Agent: []const u8,
    User: []const u8,
};

pub const EngineType = enum {
    EGraph,
    CAS,
    Prolog,
    Kernel,
};

pub const TraceStep = struct {
    source: Provenance,
    engine: EngineType,
    operation: []const u8,
    timestamp: u64,
};

pub const Transformer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Transformer {
        return .{ .allocator = allocator };
    }

    pub fn transformTerm(self: *Transformer, term: ast.Term) !ast.Term {
        return switch (term) {
            .sort, .variable => term,

            .pi => |p| {
                const dom_ptr = try self.allocator.create(ast.Term);
                const codom_ptr = try self.allocator.create(ast.Term);
                dom_ptr.* = try self.transformTerm(p.domain.*);
                codom_ptr.* = try self.transformTerm(p.codomain.*);
                return ast.Term{
                    .pi = .{
                        .name = p.name,
                        .domain = dom_ptr,
                        .codomain = codom_ptr,
                    },
                };
            },

            .lambda => |l| {
                const dom_ptr = try self.allocator.create(ast.Term);
                const body_ptr = try self.allocator.create(ast.Term);
                dom_ptr.* = try self.transformTerm(l.domain.*);
                body_ptr.* = try self.transformTerm(l.body.*);
                return ast.Term{
                    .lambda = .{
                        .name = l.name,
                        .domain = dom_ptr,
                        .body = body_ptr,
                    },
                };
            },

            .app => |a| {
                const func_ptr = try self.allocator.create(ast.Term);
                const arg_ptr = try self.allocator.create(ast.Term);
                func_ptr.* = try self.transformTerm(a.func.*);
                arg_ptr.* = try self.transformTerm(a.arg.*);
                return ast.Term{
                    .app = .{
                        .func = func_ptr,
                        .arg = arg_ptr,
                    },
                };
            },

            .quot => |q| {
                const type_a_ptr = try self.allocator.create(ast.Term);
                const rel_r_ptr = try self.allocator.create(ast.Term);
                type_a_ptr.* = try self.transformTerm(q.type_a.*);
                rel_r_ptr.* = try self.transformTerm(q.relation_r.*);
                return ast.Term{
                    .quot = .{
                        .type_a = type_a_ptr,
                        .relation_r = rel_r_ptr,
                    },
                };
            },

            .class => |c| {
                const quot_ptr = try self.allocator.create(ast.Term);
                const elem_ptr = try self.allocator.create(ast.Term);
                quot_ptr.* = try self.transformTerm(c.quot_type.*);
                elem_ptr.* = try self.transformTerm(c.element.*);
                return ast.Term{
                    .class = .{
                        .quot_type = quot_ptr,
                        .element = elem_ptr,
                    },
                };
            },

            .lift => |l| {
                const quot_ptr = try self.allocator.create(ast.Term);
                const target_ptr = try self.allocator.create(ast.Term);
                const func_ptr = try self.allocator.create(ast.Term);
                const proof_ptr = try self.allocator.create(ast.Term);

                quot_ptr.* = try self.transformTerm(l.quot_type.*);
                target_ptr.* = try self.transformTerm(l.target_b.*);
                func_ptr.* = try self.transformTerm(l.func_f.*);
                proof_ptr.* = try self.transformTerm(l.proof.*);

                return ast.Term{
                    .lift = .{
                        .quot_type = quot_ptr,
                        .target_b = target_ptr,
                        .func_f = func_ptr,
                        .proof = proof_ptr,
                    },
                };
            },
        };
    }

    pub fn destroyTerm(self: *Transformer, term_ptr: *const ast.Term) void {
        switch (term_ptr.*) {
            .sort, .variable => {},
            .pi => |p| {
                self.destroyTerm(p.domain);
                self.destroyTerm(p.codomain);
                self.allocator.destroy(@constCast(p.domain));
                self.allocator.destroy(@constCast(p.codomain));
            },
            .lambda => |l| {
                self.destroyTerm(l.domain);
                self.destroyTerm(l.body);
                self.allocator.destroy(@constCast(l.domain));
                self.allocator.destroy(@constCast(l.body));
            },
            .app => |a| {
                self.destroyTerm(a.func);
                self.destroyTerm(a.arg);
                self.allocator.destroy(@constCast(a.func));
                self.allocator.destroy(@constCast(a.arg));
            },
            .quot => |q| {
                self.destroyTerm(q.type_a);
                self.destroyTerm(q.relation_r);
                self.allocator.destroy(@constCast(q.type_a));
                self.allocator.destroy(@constCast(q.relation_r));
            },
            .class => |c| {
                self.destroyTerm(c.quot_type);
                self.destroyTerm(c.element);
                self.allocator.destroy(@constCast(c.quot_type));
                self.allocator.destroy(@constCast(c.element));
            },
            .lift => |l| {
                self.destroyTerm(l.quot_type);
                self.destroyTerm(l.target_b);
                self.destroyTerm(l.func_f);
                self.destroyTerm(l.proof);
                self.allocator.destroy(@constCast(l.quot_type));
                self.allocator.destroy(@constCast(l.target_b));
                self.allocator.destroy(@constCast(l.func_f));
                self.allocator.destroy(@constCast(l.proof));
            },
        }
    }
};
