const std = @import("std");
const matrix_lib = @import("matrix_lib");
const universal_lib = @import("../../inference/forge/universal.zig");
const heaven_expr_lib = @import("heaven_expr");
const ontology_lib = @import("ontology");
const swarm_lib = @import("../swarm/runtime.zig");
const green_lib = @import("../green.zig");
const proof_lib = @import("proof");
const skill_lib = @import("skill");
const heaven_lib = @import("../heaven.zig");
const autofab_lib = @import("../autofab.zig");
const prolog_lib = @import("../prolog.zig");
const run_mod = @import("run.zig");

pub const Shell = struct {
    allocator: std.mem.Allocator,
    matrix: *matrix_lib.Matrix,
    engine: *heaven_lib.Engine,
    ingestor: *universal_lib.UniversalIngestor,
    memo: std.StringHashMap(i64),
    prolog: prolog_lib.PrologEngine,
    heaven: *heaven_expr_lib.Heaven,
    kanren: @import("kanren").KanrenEngine,
    meta: *ontology_lib.MetaEngine,
    swarm: *swarm_lib.SwarmRuntime,
    green: *green_lib.GreenScheduler,
    proofs: *proof_lib.ProofEnv,
    skills: skill_lib.SkillRegistry,
    active_theorem: ?[]const u8 = null,

    pub fn init(alloc: std.mem.Allocator, m: *matrix_lib.Matrix, e: *heaven_lib.Engine, i: *universal_lib.UniversalIngestor, port: u16) Shell {
        const he = alloc.create(heaven_expr_lib.Heaven) catch @panic("alloc heaven_expr");
        //defer alloc.destroy(he);
        he.* = heaven_expr_lib.Heaven.init(alloc);
        return .{
            .allocator = alloc,
            .matrix = m,
            .engine = e,
            .ingestor = i,
            .memo = std.StringHashMap(i64).init(alloc),
            .prolog = prolog_lib.PrologEngine.init(alloc),
            .heaven = he,
            .kanren = @import("kanren").KanrenEngine.init(alloc),
            .meta = blk: {
                const me = alloc.create(ontology_lib.MetaEngine) catch @panic("alloc meta");
                //defer alloc.destroy(me);
                me.* = ontology_lib.MetaEngine.init(alloc);
                break :blk me;
            },
            .swarm = blk: {
                const s = alloc.create(swarm_lib.SwarmRuntime) catch @panic("alloc swarm");
                //defer alloc.destroy(s);
                s.* = swarm_lib.SwarmRuntime.init(alloc, port);
                break :blk s;
            },
            .green = blk: {
                const g = alloc.create(green_lib.GreenScheduler) catch @panic("alloc green");
                //defer alloc.destroy(g);
                g.* = green_lib.GreenScheduler.init(alloc);
                break :blk g;
            },
            .proofs = blk: {
                const p = alloc.create(proof_lib.ProofEnv) catch @panic("alloc proofs");
                //defer alloc.destroy(p);
                p.* = proof_lib.ProofEnv.init(alloc);
                break :blk p;
            },
            .skills = skill_lib.SkillRegistry.init(alloc),
        };
    }

    pub fn deinit(self: *Shell) void {
        // Appeler deinit sur les objets qui allouent de la mémoire
        self.heaven.deinit();
        self.meta.deinit();
        self.proofs.deinit();
        self.swarm.deinit();
        self.green.deinit();
        // Puis détruire les structs créés avec alloc.create dans init.zig
        self.allocator.destroy(self.heaven);
        self.allocator.destroy(self.meta);
        self.allocator.destroy(self.proofs);
        self.allocator.destroy(self.swarm);
        self.allocator.destroy(self.green);
    }

    pub fn run(self: *Shell) !void {
        return run_mod.run(self);
    }
};
