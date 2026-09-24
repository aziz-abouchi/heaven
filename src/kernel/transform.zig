const std = @import("std");
const ast = @import("ast.zig");
const Term = ast.Term;

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

    pub fn transformTerm(self: *Transformer, term: Term) std.mem.Allocator.Error!*Term {
        return switch (term) {
            .quot => |q| {
                const new_type_a = try self.transformTerm(q.type_a.*);
                const new_rel_r = try self.transformTerm(q.relation_r.*);

                const res = try self.allocator.create(Term);
                res.* = .{
                    .quot = .{
                        .type_a = new_type_a,
                        .relation_r = new_rel_r,
                    },
                };
                return res;
            },

            .lift => |l| {
                const new_quot = try self.transformTerm(l.quot_type.*);
                const new_target = try self.transformTerm(l.target_b.*);
                const new_func = try self.transformTerm(l.func_f.*);
                const new_proof = try self.transformTerm(l.proof.*);

                const res = try self.allocator.create(Term);
                res.* = .{
                    .lift = .{
                        .quot_type = new_quot,
                        .target_b = new_target,
                        .func_f = new_func,
                        .proof = new_proof,
                    },
                };
                return res;
            },

            .sort, .variable => {
                const res = try self.allocator.create(Term);
                res.* = term;
                return res;
            },

            .pi => |p| {
                const dom_ptr = try self.transformTerm(p.domain.*);
                const codom_ptr = try self.transformTerm(p.codomain.*);

                const res_ptr = try self.allocator.create(Term);
                res_ptr.* = .{
                    .pi = .{
                        .name = p.name,
                        .domain = dom_ptr,
                        .codomain = codom_ptr,
                    },
                };
                return res_ptr;
            },

            .lambda => |l| {
                const dom_ptr = try self.transformTerm(l.domain.*);
                const body_ptr = try self.transformTerm(l.body.*);

                const res_ptr = try self.allocator.create(Term);
                res_ptr.* = .{
                    .lambda = .{
                        .name = l.name,
                        .domain = dom_ptr,
                        .body = body_ptr,
                    },
                };
                return res_ptr;
            },

            .app => |a| {
                const func_ptr = try self.transformTerm(a.func.*);
                const arg_ptr = try self.transformTerm(a.arg.*);

                const res_ptr = try self.allocator.create(Term);
                res_ptr.* = .{
                    .app = .{
                        .func = func_ptr,
                        .arg = arg_ptr,
                    },
                };
                return res_ptr;
            },

            .class => |c| {
                const quot_ptr = try self.transformTerm(c.quot_type.*);
                const elem_ptr = try self.transformTerm(c.element.*);

                const res_ptr = try self.allocator.create(Term);
                res_ptr.* = .{
                    .class = .{
                        .quot_type = quot_ptr,
                        .element = elem_ptr,
                    },
                };
                return res_ptr;
            },
        };
    }

    pub fn destroyTerm(self: *Transformer, term_ptr: *const Term) void {
        switch (term_ptr.*) {
            .quot => |q| {
                self.destroyTerm(q.type_a);
                self.destroyTerm(q.relation_r);
            },
            .lift => |l| {
                self.destroyTerm(l.quot_type);
                self.destroyTerm(l.target_b);
                self.destroyTerm(l.func_f);
                self.destroyTerm(l.proof);
            },
            .sort, .variable => {},
            .pi => |p| {
                self.destroyTerm(p.domain);
                self.destroyTerm(p.codomain);
            },
            .lambda => |l| {
                self.destroyTerm(l.domain);
                self.destroyTerm(l.body);
            },
            .app => |a| {
                self.destroyTerm(a.func);
                self.destroyTerm(a.arg);
            },
            .class => |c| {
                self.destroyTerm(c.quot_type);
                self.destroyTerm(c.element);
            },
        }
        self.allocator.destroy(@constCast(term_ptr));
    }
};
