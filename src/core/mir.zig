const std = @import("std");
const expr_mod = @import("expr");
const engine_mod = @import("engine_expr");

const mir_types = @import("mir/types.zig");
const mir_compile = @import("mir/compile.zig");

const Sym = expr_mod.Sym;
const Store = expr_mod.Store;
pub const Id = mir_types.Id;
pub const Reg = mir_types.Reg;
pub const BlockId = mir_types.BlockId;
pub const MirError = mir_types.MirError;
pub const PhiEntry = mir_types.PhiEntry;
pub const Instr = mir_types.Instr;
pub const BasicBlock = mir_types.BasicBlock;
pub const FnDef = mir_types.FnDef(MirFunction);
pub const FusedSccInfo = mir_types.FusedSccInfo;
pub const sccFusionEnabledFromEnv = mir_types.sccFusionEnabledFromEnv;
const findMemberIdx = mir_types.findMemberIdx;
const shiftReg = mir_types.shiftReg;
const shiftPhiEntry = mir_types.shiftPhiEntry;
const shiftInstr = mir_types.shiftInstr;
const copyBlocksForFusion = mir_types.copyBlocksForFusion;
const copyBlocksForFusionN = mir_types.copyBlocksForFusionN;
pub const isBuiltinHeapCtor = mir_types.isBuiltinHeapCtor;

pub const MirFunction = struct {
    allocator: std.mem.Allocator,
    blocks: std.ArrayListUnmanaged(BasicBlock),
    next_value: Reg = 0,
    next_block: BlockId = 0,
    loop_exit_block: ?BlockId = null,
    break_values: std.ArrayListUnmanaged(PhiEntry) = .{},
    store: ?*Store = null,
    engine: ?*engine_mod.Engine = null,
    store_ref: ?*Store = null,
    fn_defs: std.AutoHashMap(Sym, FnDef),
    owns_fn_defs: bool = true,
    values: std.ArrayListUnmanaged(i64),
    // 2026-10-30 : pool de strings pour const_str (index = sym)
    str_pool: std.ArrayListUnmanaged([]const u8) = .{},
    // 2026-10-30 : sym interné de "heaven_argv" si @argv utilisé
    argv_sym: ?u32 = null,

    /// Cherche un tail-call dans `f` vers `target`. Meme pattern que
    /// mir_qbe.zig::hasTailCall : derniere instr = call_user, terminator
    /// ret ou jump vers bloc phi-pur + ret.
    fn hasTailCallTo(f: *const MirFunction, target: u32) bool {
        for (f.blocks.items) |*blk| {
            if (blk.instrs.items.len == 0) continue;
            const c = switch (blk.instrs.items[blk.instrs.items.len - 1]) {
                .call_user => |cc| cc,
                else => continue,
            };
            if (c.name != target) continue;
            switch (blk.terminator) {
                .ret => |rv| if (rv == c.dest) return true,
                .jump => |t| {
                    if (t >= f.blocks.items.len) continue;
                    const tg = &f.blocks.items[t];
                    var only_phi = true;
                    for (tg.instrs.items) |ins| {
                        if (ins != .phi) {
                            only_phi = false;
                            break;
                        }
                    }
                    if (only_phi and tg.terminator == .ret) return true;
                },
                else => {},
            }
        }
        return false;
    }

    /// Detecte les paires mutuellement recursives en tail (SCC de taille 2).
    /// Retourne les paires [a, b] avec a < b.
    pub fn findTailPairs(self: *MirFunction, allocator: std.mem.Allocator) ![]const [2]u32 {
        var pairs: std.ArrayListUnmanaged([2]u32) = .{};
        errdefer pairs.deinit(allocator);

        var syms: std.ArrayListUnmanaged(u32) = .{};
        defer syms.deinit(allocator);
        var it = self.fn_defs.keyIterator();
        while (it.next()) |k| try syms.append(allocator, k.*);

        for (syms.items, 0..) |a, i| {
            const def_a = self.fn_defs.get(a) orelse continue;
            for (syms.items[i + 1 ..]) |b| {
                const def_b = self.fn_defs.get(b) orelse continue;
                if (hasTailCallTo(&def_a.fn_mir, b) and hasTailCallTo(&def_b.fn_mir, a)) {
                    try pairs.append(allocator, .{ a, b });
                }
            }
        }
        return pairs.toOwnedSlice(allocator);
    }

    /// Generalisation : retourne les SCCs (composantes fortement
    /// connexes) de taille >= 2 dans le graphe des tail-calls.
    /// Chaque SCC est une liste de symbols, le caller doit liberer
    /// chaque slice et le slice externe.
    ///
    /// Algorithme : fermeture transitive (Floyd-Warshall booleen) sur
    /// la matrice d'adjacence. Pour N fonctions (< 100), le cout
    /// O(N^3) est negligeable.
    
    // TCO ACCESSOR (2026-11-12)
    pub fn fnDefsMut(self: *MirFunction) *@TypeOf(self.fn_defs) {
        return &self.fn_defs;
    }

    pub fn findTailSCCs(self: *MirFunction, allocator: std.mem.Allocator) ![]const []const u32 {
        var syms: std.ArrayListUnmanaged(u32) = .{};
        defer syms.deinit(allocator);
        var it = self.fn_defs.keyIterator();
        while (it.next()) |k| try syms.append(allocator, k.*);
        const n = syms.items.len;
        if (n == 0) return allocator.alloc([]const u32, 0);

        const edge = try allocator.alloc(bool, n * n);
        defer allocator.free(edge);
        @memset(edge, false);
        for (syms.items, 0..) |a, i| {
            const def_a = self.fn_defs.get(a) orelse continue;
            for (syms.items, 0..) |b, j| {
                if (i == j) continue;
                if (hasTailCallTo(&def_a.fn_mir, b)) edge[i * n + j] = true;
            }
        }

        for (0..n) |k| {
            for (0..n) |i| {
                if (!edge[i * n + k]) continue;
                for (0..n) |j| {
                    if (edge[k * n + j]) edge[i * n + j] = true;
                }
            }
        }

        const assigned = try allocator.alloc(bool, n);
        defer allocator.free(assigned);
        @memset(assigned, false);

        var sccs: std.ArrayListUnmanaged([]const u32) = .{};
        errdefer {
            for (sccs.items) |sl| allocator.free(sl);
            sccs.deinit(allocator);
        }

        for (0..n) |i| {
            if (assigned[i]) continue;
            var members: std.ArrayListUnmanaged(u32) = .{};
            defer members.deinit(allocator);
            try members.append(allocator, syms.items[i]);
            for (i + 1..n) |j| {
                if (assigned[j]) continue;
                if (edge[i * n + j] and edge[j * n + i]) {
                    try members.append(allocator, syms.items[j]);
                    assigned[j] = true;
                }
            }
            assigned[i] = true;
            if (members.items.len >= 2) {
                const copy = try allocator.alloc(u32, members.items.len);
                @memcpy(copy, members.items);
                try sccs.append(allocator, copy);
            }
        }

        return sccs.toOwnedSlice(allocator);
    }

    /// Info sur une paire fusionnee par fuseTailPairs.
    pub const FusedPairInfo = struct {
        scc_sym: u32,
        a_sym: u32,
        b_sym: u32,
    };

    /// B3 : remplace le corps de la fonction `sym` par un wrapper qui
    /// appelle `scc_sym(param_regs..., tag_value)`. Les param_regs
    /// ABI de `sym` restent inchanges.
    fn wrapWithSccCall(self: *MirFunction, sym: u32, scc_sym: u32, tag_value: i64, K: u32) !void {
        const def = self.fn_defs.getPtr(sym) orelse return;

        var wrapper = MirFunction.init(self.allocator);
        errdefer wrapper.deinit();

        var max_r: u32 = 0;
        for (def.param_regs) |r| if (r > max_r) {
            max_r = r;
        };
        wrapper.next_value = max_r + 1;

        _ = try wrapper.newBlock();
        const tag_r = wrapper.newReg();
        const dest_r = wrapper.newReg();
        try wrapper.blocks.items[0].instrs.append(self.allocator, .{ .const_int = .{ .dest = tag_r, .value = tag_value } });
        const args = try self.allocator.alloc(Reg, K + 1);
        for (def.param_regs, 0..) |r, j| args[j] = r;
        args[K] = tag_r;
        try wrapper.blocks.items[0].instrs.append(self.allocator, .{ .call_user = .{
            .dest = dest_r,
            .name = scc_sym,
            .args = args,
        } });
        wrapper.blocks.items[0].terminator = .{ .ret = dest_r };

        // Liberer l'ancien corps (blocs + slices des instrs), puis
        // remplacer. param_regs et param_names restent ceux d'origine.
        def.fn_mir.deinit();
        def.fn_mir = wrapper;
    }

    /// B2 : fusion SCC reelle. Pour chaque paire detectee (a, b),
    /// cree une fonction fusionnee $scc_N qui contient les blocs de
    /// a et de b avec un tag dispatch en entree. Les call_user intra-
    /// SCC sont reecrits en call_user $scc_N avec tag (QBE TCO prend
    /// le relais cote backend : call_user vers cur_sym -> jmp @b0).
    ///
    /// Layout de la fonction fusionnee :
    ///   @b0                    : dispatch (branch tag == 0)
    ///   @b[1 .. a_blocks]      : region a (reg_off = 0, block_off = 1)
    ///   @b[a_blocks+1 .. ]     : region b (reg_off = a_next, block_off = 1+a_blocks)
    ///
    /// Regs :
    ///   [0 .. a_next)                    : regs de a (identiques)
    ///   [a_next .. a_next+b_next)        : regs de b (decales)
    ///   a_next + b_next                  : tag_reg (dernier param ABI)
    ///   a_next + b_next + 1              : zero_reg
    ///   a_next + b_next + 2              : cond_reg
    pub fn fuseTailPairs(self: *MirFunction, allocator: std.mem.Allocator) ![]const FusedPairInfo {
        const pairs = try self.findTailPairs(allocator);
        defer allocator.free(pairs);
        if (pairs.len == 0) return allocator.alloc(FusedPairInfo, 0);

        var max_sym: u32 = 0;
        var it = self.fn_defs.keyIterator();
        while (it.next()) |k| if (k.* > max_sym) {
            max_sym = k.*;
        };

        var infos = try allocator.alloc(FusedPairInfo, pairs.len);
        errdefer allocator.free(infos);

        for (pairs, 0..) |pair, i| {
            const a_sym = pair[0];
            const b_sym = pair[1];
            const scc_sym = max_sym + 1 + @as(u32, @intCast(i));

            const def_a = self.fn_defs.get(a_sym) orelse continue;
            const def_b = self.fn_defs.get(b_sym) orelse continue;
            if (def_a.param_regs.len != def_b.param_regs.len) continue;
            const K = def_a.param_regs.len;
            const a_next = def_a.fn_mir.next_value;
            const b_next = def_b.fn_mir.next_value;
            const a_blocks: u32 = @intCast(def_a.fn_mir.blocks.items.len);

            var fused = MirFunction.init(allocator);
            errdefer fused.deinit();

            const total_regs = a_next + b_next + 3;
            var r: u32 = 0;
            while (r < total_regs) : (r += 1) _ = fused.newReg();
            const tag_reg: Reg = a_next + b_next;
            const zero_reg: Reg = a_next + b_next + 1;
            const cond_reg: Reg = a_next + b_next + 2;

            var fused_param_regs = try allocator.alloc(Reg, K + 1);
            errdefer allocator.free(fused_param_regs);
            var fused_param_names = try allocator.alloc(Sym, K + 1);
            errdefer allocator.free(fused_param_names);
            for (0..K) |j| {
                fused_param_regs[j] = def_a.param_regs[j];
                fused_param_names[j] = def_a.param_names[j];
            }
            fused_param_regs[K] = tag_reg;
            fused_param_names[K] = 0;

            _ = try fused.newBlock();
            const b0 = &fused.blocks.items[0];
            try b0.instrs.append(allocator, .{ .const_int = .{ .dest = zero_reg, .value = 0 } });
            for (0..K) |j| {
                const src = def_a.param_regs[j];
                const dst = def_b.param_regs[j] + a_next;
                try b0.instrs.append(allocator, .{ .add = .{ .dest = dst, .lhs = src, .rhs = zero_reg } });
            }
            try b0.instrs.append(allocator, .{ .cmp_eq = .{ .dest = cond_reg, .lhs = tag_reg, .rhs = zero_reg } });
            b0.terminator = .{ .branch = .{ .cond = cond_reg, .then_block = 1, .else_block = 1 + a_blocks } };

            try copyBlocksForFusion(&fused, &def_a.fn_mir, allocator, 0, 1, a_sym, b_sym, scc_sym);
            try copyBlocksForFusion(&fused, &def_b.fn_mir, allocator, a_next, 1 + a_blocks, a_sym, b_sym, scc_sym);

            try self.fn_defs.put(scc_sym, .{
                .fn_mir = fused,
                .param_regs = fused_param_regs,
                .param_names = fused_param_names,
            });

            // B3 : remplacer les corps de a et b par des wrappers qui
            // appellent $scc_N avec le bon tag. Les FnDef d'origine
            // gardent leurs param_regs/names (ABI inchangee).
            const K_u32: u32 = @intCast(K);
            try self.wrapWithSccCall(a_sym, scc_sym, 0, K_u32);
            try self.wrapWithSccCall(b_sym, scc_sym, 1, K_u32);

            infos[i] = .{ .scc_sym = scc_sym, .a_sym = a_sym, .b_sym = b_sym };
        }

        return infos;
    }

    /// Generalisation N-ary : fusion de chaque SCC (tail-call graph)
    /// en une fonction avec tag dispatch a N branches.
    /// Le caller doit liberer chaque info.members et le slice externe.
    ///
    /// Layout regs : 0=tag, 1=zero, 2=cond, 3=const,
    /// [4 .. 4+sum(next_value)) = regs des membres (decales).
    /// Layout blocks : 0..N-2 = checks, puis regions contigues.
    pub fn fuseTailSCCs(self: *MirFunction, allocator: std.mem.Allocator) ![]const FusedSccInfo {
        const sccs = try self.findTailSCCs(allocator);
        defer {
            for (sccs) |scc| allocator.free(scc);
            allocator.free(sccs);
        }
        if (sccs.len == 0) return allocator.alloc(FusedSccInfo, 0);

        var max_sym: u32 = 0;
        var it = self.fn_defs.keyIterator();
        while (it.next()) |k| if (k.* > max_sym) {
            max_sym = k.*;
        };

        var infos: std.ArrayListUnmanaged(FusedSccInfo) = .{};
        errdefer {
            for (infos.items) |info| allocator.free(info.members);
            infos.deinit(allocator);
        }

        for (sccs, 0..) |scc, idx| {
            const N = scc.len;
            if (N < 2) continue;
            const scc_sym = max_sym + 1 + @as(u32, @intCast(idx));

            const def0 = self.fn_defs.get(scc[0]) orelse continue;
            const K = def0.param_regs.len;
            var k_ok = true;
            for (scc) |m| {
                const d = self.fn_defs.get(m) orelse {
                    k_ok = false;
                    break;
                };
                if (d.param_regs.len != K) {
                    k_ok = false;
                    break;
                }
            }
            if (!k_ok) continue;

            const region_start = try allocator.alloc(u32, N);
            defer allocator.free(region_start);
            const reg_start = try allocator.alloc(u32, N);
            defer allocator.free(reg_start);

            var cur_blk: u32 = @intCast(N - 1);
            var cur_reg: u32 = 0;
            for (scc, 0..) |m, i| {
                region_start[i] = cur_blk;
                reg_start[i] = cur_reg;
                const d = self.fn_defs.get(m) orelse continue;
                cur_blk += @intCast(d.fn_mir.blocks.items.len);
                cur_reg += d.fn_mir.next_value;
            }

            const tag_reg: Reg = 0;
            const zero_reg: Reg = 1;
            const cond_reg: Reg = 2;
            const const_reg: Reg = 3;
            const REG_BASE: u32 = 4;

            var fused = MirFunction.init(allocator);
            errdefer fused.deinit();
            var r: u32 = 0;
            while (r < REG_BASE + cur_reg) : (r += 1) _ = fused.newReg();

            var fused_param_regs = try allocator.alloc(Reg, K + 1);
            errdefer allocator.free(fused_param_regs);
            var fused_param_names = try allocator.alloc(Sym, K + 1);
            errdefer allocator.free(fused_param_names);
            for (0..K) |j| {
                fused_param_regs[j] = def0.param_regs[j] + REG_BASE;
                fused_param_names[j] = def0.param_names[j];
            }
            fused_param_regs[K] = tag_reg;
            fused_param_names[K] = 0;

            // @b0 : init + check 0.
            _ = try fused.newBlock();
            const b0 = &fused.blocks.items[0];
            try b0.instrs.append(allocator, .{ .const_int = .{ .dest = zero_reg, .value = 0 } });
            for (scc, 0..) |m, mi| {
                if (mi == 0) continue;
                const d = self.fn_defs.get(m) orelse continue;
                const reg_off_mi: u32 = REG_BASE + reg_start[mi];
                for (0..K) |j| {
                    const src = fused_param_regs[j];
                    const dst = d.param_regs[j] + reg_off_mi;
                    try b0.instrs.append(allocator, .{ .add = .{ .dest = dst, .lhs = src, .rhs = zero_reg } });
                }
            }
            try b0.instrs.append(allocator, .{ .const_int = .{ .dest = const_reg, .value = 0 } });
            try b0.instrs.append(allocator, .{ .cmp_eq = .{ .dest = cond_reg, .lhs = tag_reg, .rhs = const_reg } });
            const else0: u32 = if (N > 2) 1 else region_start[N - 1];
            b0.terminator = .{ .branch = .{ .cond = cond_reg, .then_block = region_start[0], .else_block = else0 } };

            // @b1..@b[N-2] : checks intermediaires.
            var ci: u32 = 1;
            while (ci < N - 1) : (ci += 1) {
                _ = try fused.newBlock();
                const b = &fused.blocks.items[ci];
                try b.instrs.append(allocator, .{ .const_int = .{ .dest = const_reg, .value = @intCast(ci) } });
                try b.instrs.append(allocator, .{ .cmp_eq = .{ .dest = cond_reg, .lhs = tag_reg, .rhs = const_reg } });
                const else_b: u32 = if (ci + 1 < N - 1) ci + 1 else region_start[N - 1];
                b.terminator = .{ .branch = .{ .cond = cond_reg, .then_block = region_start[ci], .else_block = else_b } };
            }

            // Regions.
            for (scc, 0..) |m, mi| {
                const d = self.fn_defs.get(m) orelse continue;
                const reg_off_mi: u32 = REG_BASE + reg_start[mi];
                try copyBlocksForFusionN(&fused, &d.fn_mir, allocator, reg_off_mi, region_start[mi], scc, scc_sym);
            }

            try self.fn_defs.put(scc_sym, .{
                .fn_mir = fused,
                .param_regs = fused_param_regs,
                .param_names = fused_param_names,
            });

            const K_u32: u32 = @intCast(K);
            for (scc, 0..) |m, mi| {
                try self.wrapWithSccCall(m, scc_sym, @intCast(mi), K_u32);
            }

            const members_copy = try allocator.alloc(u32, N);
            @memcpy(members_copy, scc);
            try infos.append(allocator, .{ .scc_sym = scc_sym, .members = members_copy });
        }

        return infos.toOwnedSlice(allocator);
    }

    pub fn init(allocator: std.mem.Allocator) MirFunction {
        return .{
            .allocator = allocator,
            .blocks = .{},
            .store = null,
            .fn_defs = std.AutoHashMap(Sym, FnDef).init(allocator),
            .values = .{},
        };
    }

    pub fn deinit(self: *MirFunction) void {
        for (self.blocks.items) |*blk| {
            // Liberer les allocations internes des instructions qui en
            // possedent. Reproduit par la recursion def.fn_mir.deinit()
            // pour les fn_defs imbriquees.
            for (blk.instrs.items) |inst| {
                switch (inst) {
                    .phi => |ph| self.allocator.free(ph.incoming),
                    .call_user => |c| self.allocator.free(c.args),
                    .extern_call => |c| self.allocator.free(c.args),
                    else => {},
                }
            }
            blk.instrs.deinit(self.allocator);
        }
        self.blocks.deinit(self.allocator);
                self.break_values.deinit(self.allocator);
        self.str_pool.deinit(self.allocator);

        // Libérer les définitions de fonctions (uniquement si propriétaire ;
        // les clones partagent fn_defs et ne doivent pas le libérer)
        if (self.owns_fn_defs) {
            var it = self.fn_defs.valueIterator();
            while (it.next()) |def| {
                def.fn_mir.deinit();
                self.allocator.free(def.param_names);
                self.allocator.free(def.param_regs);
            }
            self.fn_defs.deinit();
        }

        self.values.deinit(self.allocator);
    }

    pub fn newReg(self: *MirFunction) Reg {
        const r = self.next_value;
        self.next_value += 1;
        return r;
    }

    pub fn newBlock(self: *MirFunction) !BlockId {
        const id = self.next_block;
        self.next_block += 1;
        try self.blocks.append(self.allocator, .{
            .instrs = .{},
            .terminator = .fallthrough,
        });
        return id;
    }


    pub fn initWithStore(allocator: std.mem.Allocator, store: *Store) MirFunction {
        return .{
            .allocator = allocator,
            .blocks = .{},
            .store = store,
            .fn_defs = std.AutoHashMap(Sym, FnDef).init(allocator),
            .values = .{},
        };
    }

    /// Nom du parametre synthetique i d'une fonction multi-clauses.
    pub fn multiParamSym(store: *Store, i: usize) !Sym {
        var buf: [16]u8 = undefined;
        const nm = try std.fmt.bufPrint(&buf, "__a{d}", .{i});
        return try store.interner.intern(nm);
    }

    /// Un pattern de clause est une *variable* s'il s'agit d'un symbole qui
    /// n'est ni un constructeur connu, ni true/false, ni capitalise.
    fn isVarPattern(self: *MirFunction, store: *Store, pat_id: Id) bool {
        const pat = store.get(pat_id);
        if (pat.tag == .hole) return true; // wildcard `_`
        if (pat.tag != .sym) return false;
        const name = store.interner.resolve(pat.payload);
        if (name.len == 0) return false;
        if (std.ascii.isUpper(name[0])) return false;
        if (std.mem.eql(u8, name, "true") or std.mem.eql(u8, name, "false")) return false;
        if (self.engine) |eng| {
            if (eng.fns.get(name)) |f| {
                if (f.ctor_arity != null) return false;
            }
        }
        return true;
    }

    /// Un pattern scalaire compilable par egalite entiere :
    /// entier, booleen (true/True -> 1, false/False -> 0), ou constructeur ADT 0-aire.
    fn scalarPatternLit(self: *MirFunction, store: *Store, pat_id: Id) !?Id {
        const lp = store.lowerRec(pat_id) catch return null;
        const n = store.get(lp);
        if (n.tag == .sym) {
            const name = store.interner.resolve(n.payload);
            if (std.mem.eql(u8, name, "true") or std.mem.eql(u8, name, "True")) return try store.int(1);
            if (std.mem.eql(u8, name, "false") or std.mem.eql(u8, name, "False")) return try store.int(0);
            if (self.engine) |eng| {
                if (eng.fns.get(name)) |fd| {
                    if (fd.ctor_arity) |arity| {
                        if (arity == 0) {
                            if (fd.ctor_tag) |tag| return try store.int(@intCast(tag));
                        }
                    }
                }
            }
            return null;
        }
        if (n.tag != .lit) return null;
        return switch (store.lits.items[n.aux]) {
            .int => lp,
            .boolean => |b| try store.int(if (b) 1 else 0),
            // Chaine : la comparaison se fait par contenu (strcmp), pas par
            // adresse ; voir patternTest.
            .str => lp,
            else => null,
        };
    }

    /// Test d'un motif scalaire contre `arg` : egalite pour les entiers et
    /// booleens, `(@strcmp arg "lit") = 0` pour les chaines (contenu).
    fn patternTest(store: *Store, arg: Id, lp: Id) !Id {
        const n = store.get(lp);
        if (n.tag == .lit and store.lits.items[n.aux] == .str) {
            const cmp = try store.apply(try store.sym("@strcmp"), &.{ arg, lp });
            return try store.binop("=", cmp, try store.int(0));
        }
        return try store.binop("=", arg, lp);
    }

    /// Soundness : on ne compile que ce qu'on sait traduire fidelement.
    /// Supporte : variables, wildcards `_`, entiers, booleens (`true`/`false`),
    /// et gardes (`| cond`) avec derniere clause generale non gardee.
    const NaryCtorPat = struct {
        tag: u8,
        args: [8]Id,
        len: usize,
    };

    /// Deroule une application potentiellement curryfiee `((Ctor a0) a1) ...`
    /// vers la tete symbole et la liste plate d'arguments `[a0, a1, ...]`.
    pub fn unwindCurriedApply(store: *Store, root_id: Id, out_args: *[8]Id) ?struct { head_sym: Sym, len: usize } {
        var cur = root_id;
        var rev: [8]Id = undefined;
        var count: usize = 0;
        while (true) {
            const n = store.get(cur);
            if (n.tag != .apply) break;
            const raw = n.span_a.slice(store.pool.items);
            if (n.payload == 0) {
                if (raw.len < 2) return null;
                var i: usize = raw.len;
                while (i > 1) {
                    i -= 1;
                    if (count >= 8) return null;
                    rev[count] = raw[i];
                    count += 1;
                }
                cur = raw[0];
                continue;
            }
            const head_matches = raw.len > 0 and (raw[0] == n.payload or
                (store.get(raw[0]).tag == .sym and store.get(n.payload).tag == .sym and
                 store.get(raw[0]).payload == store.get(n.payload).payload));
            const slice = if (head_matches) raw[1..] else raw;
            var i: usize = slice.len;
            while (i > 0) {
                i -= 1;
                if (count >= 8) return null;
                rev[count] = slice[i];
                count += 1;
            }
            cur = n.payload;
        }
        if (count == 0) return null;
        const head = store.get(cur);
        if (head.tag != .sym) return null;
        for (0..count) |k| {
            out_args[k] = rev[count - 1 - k];
        }
        return .{ .head_sym = head.payload, .len = count };
    }

    fn naryCtorPattern(self: *MirFunction, store: *Store, pat_id: Id) ?NaryCtorPat {
        return self.naryCtorPatternAt(store, pat_id, true);
    }

    /// `allow_nested` : un ctor de premier niveau accepte des sous-motifs
    /// ctor, eux-memes plats (variables / litteraux seulement). Profondeur
    /// max 2 : desugarClauses ne sait pas tester/lier plus profond, et un
    /// niveau ignore donnerait une valeur inventee.
    fn naryCtorPatternAt(self: *MirFunction, store: *Store, pat_id: Id, allow_nested: bool) ?NaryCtorPat {
        var args_buf: [8]Id = undefined;
        const unwound = unwindCurriedApply(store, pat_id, &args_buf) orelse return null;
        const cname = store.interner.resolve(unwound.head_sym);
        if (isBuiltinHeapCtor(cname)) return null;
        const eng = self.engine orelse return null;
        const fd = eng.fns.get(cname) orelse return null;
        const arity = fd.ctor_arity orelse return null;
        if (arity == 0 or unwound.len != arity) return null;
        const tag = fd.ctor_tag orelse return null;
        for (0..unwound.len) |i| {
            const sub = args_buf[i];
            if (self.isVarPattern(store, sub)) continue;
            if ((self.scalarPatternLit(store, sub) catch null) != null) continue;
            if (allow_nested and self.naryCtorPatternAt(store, sub, false) != null) continue;
            return null;
        }
        return .{ .tag = tag, .args = args_buf, .len = unwound.len };
    }

    pub fn multiClauseEligible(self: *MirFunction, def: *const engine_mod.FunctionDef) bool {
        const store = self.store orelse return false;
        const n = def.num_clauses;
        const arity = def.clauses[0].num_patterns;
        if (arity == 0) return false;
        for (0..n) |ci| {
            const c = def.clauses[ci];
            if (c.num_patterns != arity) return false;
            for (0..c.num_patterns) |i| {
                const pid = c.patterns[i];
                if (self.isVarPattern(store, pid)) continue;
                const slit = self.scalarPatternLit(store, pid) catch return false;
                if (slit != null) continue;
                if (self.naryCtorPattern(store, pid) != null) continue;
                return false;
            }
        }
        // Plus d'exigence de clause finale « attrape-tout » : desugarClauses
        // termine la chaine par un @abort explicite (echec bruyant si aucun
        // motif ne correspond), comme l'erreur de l'interpreteur.
        return true;
    }

    /// Desugare les clauses en une expression Core :
    ///   let vars in (if (tests_et_garde) body1 (if ...))
    pub fn desugarClauses(self: *MirFunction, store: *Store, def: *const engine_mod.FunctionDef) !Id {
        const n = def.num_clauses;
        // Reste de la chaine par defaut : echec explicite (abort en QBE, trap en
        // WAT) si aucun motif ne correspond, comme l'erreur de l'interpreteur.
        // Une clause finale qui attrape tout (sans test) remplace ce reste ; une
        // clause finale avec tests (liste exhaustive sans `_`) compile donc aussi.
        var result: Id = try store.apply(try store.sym("@abort"), &.{});
        var have_result = true;
        var ci: usize = n;
        while (ci > 0) {
            ci -= 1;
            const c = def.clauses[ci];
            var inner_body = try store.lowerRec(c.body);

            var pi_field: usize = c.num_patterns;
            while (pi_field > 0) {
                pi_field -= 1;
                const nc = self.naryCtorPattern(store, c.patterns[pi_field]) orelse continue;
                const psym = try multiParamSym(store, pi_field);
                var fi: usize = nc.len;
                while (fi > 0) {
                    fi -= 1;
                    const sub = nc.args[fi];
                    const arg = try store.sym(store.interner.resolve(psym));
                    const off_id = try store.int(@intCast((fi + 1) * 8));
                    const load_expr = try store.apply(try store.sym("__mir_load_at"), &.{ arg, off_id });
                    if (self.naryCtorPattern(store, sub)) |sub_nc| {
                        var sfi: usize = sub_nc.len;
                        while (sfi > 0) {
                            sfi -= 1;
                            const ssub = sub_nc.args[sfi];
                            if (!self.isVarPattern(store, ssub)) continue;
                            if (store.get(ssub).tag != .sym) continue;
                            const sfname = store.interner.resolve(store.get(ssub).payload);
                            if (std.mem.eql(u8, sfname, "_")) continue;
                            const sub_arg = try store.sym(store.interner.resolve(psym));
                            const sub_off_id = try store.int(@intCast((fi + 1) * 8));
                            const sub_ptr = try store.apply(try store.sym("__mir_load_at"), &.{ sub_arg, sub_off_id });
                            const soff_id = try store.int(@intCast((sfi + 1) * 8));
                            const sload_expr = try store.apply(try store.sym("__mir_load_at"), &.{ sub_ptr, soff_id });
                            const sb = try store.bind(sfname, sload_expr);
                            const sbn = store.get(sb);
                            store.pool.items[sbn.span_a.start + 1] = inner_body;
                            inner_body = sb;
                        }
                        continue;
                    }
                    if (!self.isVarPattern(store, sub)) continue;
                    if (store.get(sub).tag != .sym) continue;
                    const fname = store.interner.resolve(store.get(sub).payload);
                    if (std.mem.eql(u8, fname, "_")) continue;
                    const b = try store.bind(fname, load_expr);
                    const bn = store.get(b);
                    store.pool.items[bn.span_a.start + 1] = inner_body;
                    inner_body = b;
                }
            }

            // Une seule condition 0/1 par clause (tests imbriques qui rendent 0
            // ou 1) et UN SEUL `(if cond corps reste)` : `result` (le reste de
            // la chaine) n'apparait qu'une fois. Un `if` par test dupliquait
            // `result` et rendait la compilation exponentielle en nombre de
            // clauses (2^k : 14 clauses -> 1M lignes de WAT).
            // Ordre d'evaluation (inchange) : scalaires -> pointeur -> tag -> garde.
            const one = try store.int(1);
            const zero = try store.int(0);
            // Etapes de test, dans l'ordre d'evaluation. Chaque chargement
            // memoire suit la verification pointeur + tag de son proprietaire
            // (un ctor nullaire est un immediat < 4096 : le charger = crash).
            //   1. scalaires de premier niveau ; 2. par ctor : pointeur, tag,
            //   puis champs (ctor imbrique : pointeur, tag, champs scalaires ;
            //   champ scalaire : test) ; 3. garde.
            var stages: std.ArrayListUnmanaged(Id) = .{};
            defer stages.deinit(self.allocator);

            for (0..c.num_patterns) |i| {
                const lp = (try self.scalarPatternLit(store, c.patterns[i])) orelse continue;
                const arg = try store.sym(store.interner.resolve(try multiParamSym(store, i)));
                try stages.append(self.allocator, try patternTest(store, arg, lp));
            }

            for (0..c.num_patterns) |i| {
                const nc = self.naryCtorPattern(store, c.patterns[i]) orelse continue;
                const psym = try multiParamSym(store, i);
                const owner = try store.sym(store.interner.resolve(psym));
                try stages.append(self.allocator, try store.binop(">=", owner, try store.int(4096)));
                const tag0 = try store.apply(try store.sym("__mir_load_at"), &.{ owner, try store.int(0) });
                try stages.append(self.allocator, try store.binop("=", tag0, try store.int(@intCast(nc.tag))));
                for (0..nc.len) |fi| {
                    const sub = nc.args[fi];
                    const f_ptr = try store.apply(try store.sym("__mir_load_at"), &.{ owner, try store.int(@intCast((fi + 1) * 8)) });
                    if (self.naryCtorPattern(store, sub)) |sub_nc| {
                        try stages.append(self.allocator, try store.binop(">=", f_ptr, try store.int(4096)));
                        const stag = try store.apply(try store.sym("__mir_load_at"), &.{ f_ptr, try store.int(0) });
                        try stages.append(self.allocator, try store.binop("=", stag, try store.int(@intCast(sub_nc.tag))));
                        for (0..sub_nc.len) |sfi| {
                            const slp = (try self.scalarPatternLit(store, sub_nc.args[sfi])) orelse continue;
                            const sval = try store.apply(try store.sym("__mir_load_at"), &.{ f_ptr, try store.int(@intCast((sfi + 1) * 8)) });
                            try stages.append(self.allocator, try patternTest(store, sval, slp));
                        }
                    } else if (try self.scalarPatternLit(store, sub)) |slp| {
                        try stages.append(self.allocator, try patternTest(store, f_ptr, slp));
                    }
                }
            }

            var test_cond: ?Id = null;
            if (c.guard) |g| test_cond = try store.lowerRec(g);
            var si: usize = stages.items.len;
            while (si > 0) {
                si -= 1;
                test_cond = try store.apply(try store.sym("if"), &.{ stages.items[si], test_cond orelse one, zero });
            }

            if (test_cond) |tc| {
                inner_body = try store.apply(try store.sym("if"), &.{ tc, inner_body, result });
            }

            var pi: usize = c.num_patterns;
            while (pi > 0) {
                pi -= 1;
                const pid = c.patterns[pi];
                if (!self.isVarPattern(store, pid)) continue;
                if (store.get(pid).tag != .sym) continue;
                const pname = store.interner.resolve(store.get(pid).payload);
                if (std.mem.eql(u8, pname, "_")) continue;
                const psym = try multiParamSym(store, pi);
                const arg = try store.sym(store.interner.resolve(psym));
                const b = try store.bind(pname, arg);
                const bn = store.get(b);
                store.pool.items[bn.span_a.start + 1] = inner_body;
                inner_body = b;
            }

            result = inner_body;
            have_result = true;
        }
        return result;
    }

    /// Retire de fn_defs, jusqu'au point fixe, toute fonction qui appelle
    /// une fonction absente de fn_defs.
    pub fn pruneOrphanCallers(self: *MirFunction) !void {
        var doomed: std.ArrayListUnmanaged(Sym) = .{};
        defer doomed.deinit(self.allocator);
        while (true) {
            doomed.clearRetainingCapacity();
            var it = self.fn_defs.iterator();
            while (it.next()) |entry| {
                var orphan = false;
                for (entry.value_ptr.fn_mir.blocks.items) |*blk| {
                    for (blk.instrs.items) |inst| {
                        switch (inst) {
                            .call_user => |c| {
                                if (!self.fn_defs.contains(c.name)) orphan = true;
                            },
                            else => {},
                        }
                    }
                    if (orphan) break;
                }
                if (orphan) try doomed.append(self.allocator, entry.key_ptr.*);
            }
            if (doomed.items.len == 0) return;
            for (doomed.items) |name_sym| {
                if (self.fn_defs.fetchRemove(name_sym)) |kv| {
                    var v = kv.value;
                    v.fn_mir.deinit();
                    self.allocator.free(v.param_names);
                    self.allocator.free(v.param_regs);
                }
            }
        }
    }

    /// Precompile les fonctions utilisateur (engine.fns) en fn_defs MIR.
    /// Permet a compileExpr de resoudre les `call_user` vers des
    /// fonctions definies par equation (`fn name(args) = body`).
    ///
    /// Limites actuelles :
    /// - Une seule clause (pas de pattern matching).
    /// - Tous les patterns doivent etre des symboles simples (pas de
    ///   patterns complexes type `fn f(0) = ...`).
    /// - Pas de recursion sur les clauses (la recursion du corps est
    ///   OK, elle passe par call_user).
    pub const precompileUserFns = mir_compile.precompileUserFns;
    pub const compileExpr = mir_compile.compileExpr;
    pub const compileLambda = mir_compile.compileLambda;
    pub const compileIf = mir_compile.compileIf;
    pub const compileWhile = mir_compile.compileWhile;
    pub const compileBreak = mir_compile.compileBreak;
    pub const compilePow = mir_compile.compilePow;

    pub fn execute(self: *MirFunction, global_vars: *std.AutoHashMap(u32, i64)) MirError!i64 {
        return self.executeLegacy(global_vars);
    }

    /// Ancienne implémentation execute désactivée pendant la réécriture Reg-based
    fn executeLegacy(self: *MirFunction, global_vars: *std.AutoHashMap(u32, i64)) MirError!i64 {
        if (self.blocks.items.len == 0) return 0;
        var current_block: BlockId = 0;
        // NE PAS deinit() values ici : execute() peut etre appele
        // plusieurs fois dans un meme test (oracle + codegen) et deinit()
        // le detruirait prematurement. clearRetainingCapacity vide la
        // liste mais conserve l'allocation, ce qui evite le double free
        // au deinit() ulterieur. Valeurs restent possedees par MirFunction.
        self.values.clearRetainingCapacity();
        var prev_block: BlockId = 0;

        var iterations: u32 = 0;
        while (true) : (iterations += 1) {
            if (iterations > 1000) return error.TooManyIterations;
            const block = self.blocks.items[current_block];
            for (block.instrs.items) |inst| {
                switch (inst) {
                    .const_int => |c| {
                        if (c.dest >= self.values.items.len) try self.values.resize(self.allocator, c.dest + 1);
                        self.values.items[c.dest] = c.value;
                    },
                    .add => |a| {
                        if (a.dest >= self.values.items.len) try self.values.resize(self.allocator, a.dest + 1);
                        self.values.items[a.dest] = self.values.items[a.lhs] + self.values.items[a.rhs];
                    },
                    .sub => |a| {
                        if (a.dest >= self.values.items.len) try self.values.resize(self.allocator, a.dest + 1);
                        self.values.items[a.dest] = self.values.items[a.lhs] - self.values.items[a.rhs];
                    },
                    .mul => |a| {
                        if (a.dest >= self.values.items.len) try self.values.resize(self.allocator, a.dest + 1);
                        self.values.items[a.dest] = self.values.items[a.lhs] * self.values.items[a.rhs];
                    },
                    .div => |a| {
                        if (a.dest >= self.values.items.len) try self.values.resize(self.allocator, a.dest + 1);
                        if (self.values.items[a.rhs] == 0) return error.DivisionByzero;
                        self.values.items[a.dest] = @divTrunc(self.values.items[a.lhs], self.values.items[a.rhs]);
                    },
                    .rem => |a| {
                        if (a.dest >= self.values.items.len) try self.values.resize(self.allocator, a.dest + 1);
                        if (self.values.items[a.rhs] == 0) return error.DivisionByzero;
                        self.values.items[a.dest] = @divTrunc(self.values.items[a.lhs], self.values.items[a.rhs]);
                    },
                    // 2026-10-30 : alloc/str non-foldable en constant. On rejette.
                    .alloc, .load_at, .store_at, .const_str => return error.UnsupportedOp,
                    .cmp_lt => |a| {
                        if (a.dest >= self.values.items.len) try self.values.resize(self.allocator, a.dest + 1);
                        self.values.items[a.dest] = if (self.values.items[a.lhs] < self.values.items[a.rhs]) 1 else 0;
                    },
                    .cmp_eq => |a| {
                        if (a.dest >= self.values.items.len) try self.values.resize(self.allocator, a.dest + 1);
                        self.values.items[a.dest] = if (self.values.items[a.lhs] == self.values.items[a.rhs]) 1 else 0;
                    },
                    .extern_call => {},
                    .load => |ld| {
                        const val = global_vars.get(ld.sym) orelse return error.UndefinedVariable;
                        if (ld.dest >= self.values.items.len) try self.values.resize(self.allocator, ld.dest + 1);
                        self.values.items[ld.dest] = val;
                    },
                    .store => |st| {
                        const val = self.values.items[st.src];
                        try global_vars.put(st.sym, val);
                    },
                    .phi => |p| {
                        var found = false;
                        for (p.incoming) |in| {
                            if (in.block == prev_block) {
                                if (in.value >= self.values.items.len) return error.ValueNotDefined;
                                const val = self.values.items[in.value];
                                if (p.dest >= self.values.items.len) try self.values.resize(self.allocator, p.dest + 1);
                                self.values.items[p.dest] = val;
                                found = true;
                                break;
                            }
                        }
                        if (!found) return error.InvalidInstruction;
                    },
                    .jump, .branch, .ret => unreachable,
                    .call_user => |cu| {
                        // Vérifier si c'est une fonction MIR définie
                        if (self.fn_defs.get(cu.name)) |fn_def| {
                            // Récupérer les valeurs des arguments
                            var arg_values = try std.ArrayList(i64).initCapacity(self.allocator, cu.args.len);
                            defer arg_values.deinit(self.allocator);
                            for (cu.args) |arg_reg| {
                                try arg_values.append(self.allocator, self.values.items[arg_reg]);
                            }
                            // Créer une copie de la fonction pour l'exécution
                            var temp_mir = try self.cloneFunction(&fn_def);
                            defer temp_mir.deinit();
                            // Initialiser les paramètres avec les valeurs des arguments
                            // On suppose que l'ordre des paramètres correspond à l'ordre des arguments
                            for (0..fn_def.param_regs.len) |i| {
                                const param_reg = fn_def.param_regs[i];
                                const arg_val = arg_values.items[i];
                                // On doit mettre cette valeur dans le tableau values de temp_mir
                                // Pour cela, on peut utiliser temp_mir.values, mais il n'est pas exposé.
                                // On va plutôt créer une fonction d'initialisation dans MirFunction.
                                // On va ajouter une méthode setValue(reg, val) qui met à jour le tableau values.
                                // Pour l'instant, on va directement manipuler le tableau values de temp_mir.
                                // Mais values est un ArrayListUnmanaged, on doit l'initialiser.
                                // On va initialiser temp_mir.values avec la taille nécessaire.
                                // On doit s'assurer que le tableau a assez de place.
                                const max_reg = std.mem.max(Id, fn_def.param_regs) + 1;
                                try temp_mir.values.resize(self.allocator, max_reg);
                                temp_mir.values.items[param_reg] = arg_val;
                            }
                            // Exécuter la fonction copiée
                            var empty_globals = std.AutoHashMap(u32, i64).init(self.allocator);
                            defer empty_globals.deinit();
                            const result = try temp_mir.executeLegacy(&empty_globals);
                            // Stocker le résultat
                            if (cu.dest >= self.values.items.len) try self.values.resize(self.allocator, cu.dest + 1);
                            self.values.items[cu.dest] = result;
                        } else {
                            // Appel à une fonction native (code existant)
                            const store = self.store_ref orelse return error.InvalidInstruction;
                            const engine = self.engine orelse return error.InvalidInstruction;

                            const name = store.interner.resolve(cu.name);
                            var args_list = std.ArrayListUnmanaged(Id){};
                            defer args_list.deinit(self.allocator);
                            for (cu.args) |arg_reg| {
                                const val = self.values.items[arg_reg];
                                const id = try store.int(val);
                                try args_list.append(self.allocator, id);
                            }
                            const result_id = engine.evalFunction(engine.env, name, args_list.items) catch return error.InvalidInstruction;
                            const result_node = store.get(result_id);
                            if (result_node.tag == .lit) {
                                const lit = store.lits.items[result_node.aux];
                                switch (lit) {
                                    .int => |v| {
                                        if (cu.dest >= self.values.items.len) try self.values.resize(self.allocator, cu.dest + 1);
                                        self.values.items[cu.dest] = v;
                                    },
                                    else => return error.InvalidInstruction,
                                }
                            } else {
                                return error.InvalidInstruction;
                            }
                        }
                    },
                }
            }
            switch (block.terminator) {
                .jump => |target| {
                    prev_block = current_block;
                    current_block = target;
                },
                .branch => |b| {
                    const cond = self.values.items[b.cond];
                    prev_block = current_block;
                    current_block = if (cond != 0) b.then_block else b.else_block;
                },
                .ret => |r| {
                    if (r >= self.values.items.len) return error.ValueNotDefined;
                    return self.values.items[r];
                },
                .fallthrough => return 0,
            }
        }
    }

    fn cloneFunction(self: *MirFunction, fn_def: *const FnDef) !MirFunction {
        var new_mir = MirFunction.init(self.allocator);
        // Copier les blocs
        try new_mir.blocks.ensureTotalCapacity(self.allocator, fn_def.fn_mir.blocks.items.len);
        for (fn_def.fn_mir.blocks.items) |block| {
            var new_block = BasicBlock{
                .instrs = .{},
                .terminator = block.terminator,
            };
            try new_block.instrs.ensureTotalCapacity(self.allocator, block.instrs.items.len);
            for (block.instrs.items) |inst| {
                var new_inst = inst;
                switch (inst) {
                    .call_user => |c| {
                        const new_args = try self.allocator.alloc(Reg, c.args.len);
                        @memcpy(new_args, c.args);
                        new_inst.call_user.args = new_args;
                    },
                    .extern_call => |c| {
                        const new_args = try self.allocator.alloc(Reg, c.args.len);
                        @memcpy(new_args, c.args);
                        new_inst.extern_call.args = new_args;
                    },
                    .phi => |ph| {
                        const new_inc = try self.allocator.alloc(PhiEntry, ph.incoming.len);
                        @memcpy(new_inc, ph.incoming);
                        new_inst.phi.incoming = new_inc;
                    },
                    else => {},
                }
                try new_block.instrs.append(self.allocator, new_inst);
            }
            try new_mir.blocks.append(self.allocator, new_block);
        }
        // Copier les autres champs nécessaires (store, engine, etc.)
        new_mir.store = self.store;
        new_mir.engine = self.engine;
        new_mir.store_ref = self.store_ref;
        // FIX (2026-11-13): partager fn_defs pour que executeLegacy
        // résolve les call_user récursifs (even/odd, fac, fib).
        // Le clone ne libère pas (owns_fn_defs = false) : le root
        // reste seul propriétaire de la map.
        new_mir.fn_defs = self.fn_defs;
        new_mir.owns_fn_defs = false;
        new_mir.values = .{};
        return new_mir;
    }

    pub fn dump(self: *const MirFunction, writer: anytype) !void {
        for (self.blocks.items, 0..) |block, i| {
            try writer.print("block_{d}:\n", .{i});
            for (block.instrs.items) |inst| {
                switch (inst) {
                    .const_int => |c| try writer.print("  v{d} = const {d}\n", .{ c.dest, c.value }),
                    .add => |a| try writer.print("  v{d} = v{d} + v{d}\n", .{ a.dest, a.lhs, a.rhs }),
                    .sub => |a| try writer.print("  v{d} = v{d} - v{d}\n", .{ a.dest, a.lhs, a.rhs }),
                    .mul => |a| try writer.print("  v{d} = v{d} * v{d}\n", .{ a.dest, a.lhs, a.rhs }),
                    .div => |a| try writer.print("  v{d} = v{d} / v{d}\n", .{ a.dest, a.lhs, a.rhs }),
                    .cmp_lt => |a| try writer.print("  v{d} = v{d} < v{d}\n", .{ a.dest, a.lhs, a.rhs }),
                    .cmp_eq => |a| try writer.print("  v{d} = v{d} == v{d}\n", .{ a.dest, a.lhs, a.rhs }),
                    .load => |ld| try writer.print("  v{d} = load[sym {d}]\n", .{ ld.dest, ld.sym }),
                    .store => |st| try writer.print("  store[sym {d}] = v{d}\n", .{ st.sym, st.src }),
                    .phi => |p| {
                        try writer.print("  v{d} = phi(", .{p.dest});
                        for (p.incoming, 0..) |in, idx| {
                            if (idx > 0) try writer.print(", ", .{});
                            try writer.print("v{d} from block_{d}", .{ in.value, in.block });
                        }
                        try writer.print(")\n", .{});
                    },
                    .call_user => |cu| {
                        try writer.print("  v{d} = call {s}(", .{ cu.dest, "?" }); // on pourrait afficher le nom, mais il faut le résoudre
                        for (cu.args, 0..) |arg, idx| {
                            if (idx > 0) try writer.print(", ", .{});
                            try writer.print("v{d}", .{arg});
                        }
                        try writer.print(")\n", .{});
                    },
                    else => try writer.print("  [unhandled instr]\n", .{}),
                }
            }
            switch (block.terminator) {
                .jump => |target| try writer.print("  jump block_{d}\n", .{target}),
                .branch => |b| try writer.print("  branch v{d} ? block_{d} : block_{d}\n", .{ b.cond, b.then_block, b.else_block }),
                .ret => |r| try writer.print("  ret v{d}\n", .{r}),
                .fallthrough => try writer.print("  fallthrough\n", .{}),
            }
        }
    }
};

// ═══════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════

test "mir — simple arithmetic" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const expr_id = try store.binop("+", try store.int(3), try store.int(4));
    var mir = MirFunction.init(allocator);
    defer mir.deinit();

    const entry = try mir.newBlock();
    var test_blk_2164: BlockId = entry;
    _ = try mir.compileExpr(&store, expr_id, &test_blk_2164, std.AutoHashMap(u32, Reg).init(allocator));
    mir.blocks.items[entry].terminator = .{ .ret = 0 };

    var globals = std.AutoHashMap(u32, i64).init(allocator);
    defer globals.deinit();
    const result = try mir.execute(&globals);
    try std.testing.expectEqual(7, result);
}

test "mir — if/else" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    // if(1, 10, 20)
    const expr_id = try store.binop("if", try store.int(1), try store.binop(",", try store.int(10), try store.int(20)));
    var mir = MirFunction.init(allocator);
    defer mir.deinit();

    const entry = try mir.newBlock();
    var locals = std.AutoHashMap(u32, Reg).init(allocator);
    defer locals.deinit();
    var test_blk_2186: BlockId = entry;
    _ = try mir.compileExpr(&store, expr_id, &test_blk_2186, locals);

    var globals = std.AutoHashMap(u32, i64).init(allocator);
    defer globals.deinit();
    const result = try mir.execute(&globals);
    try std.testing.expectEqual(10, result);
}

test "mir — while loop" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    // while(x < 5, let x = x + 1) with x=0
    const x_sym = try store.interner.intern("x");
    _ = x_sym;
    const x_id = try store.sym("x");
    const cond = try store.binop("<", x_id, try store.int(5));
    const inc = try store.binop("+", x_id, try store.int(1));
    const body = try store.bind("x", inc, try store.int(0)); // dummy body expr
    const while_expr = try store.binop("while", cond, body);

    var mir = MirFunction.init(allocator);
    defer mir.deinit();

    const entry = try mir.newBlock();
    var locals = std.AutoHashMap(u32, Reg).init(allocator);
    defer locals.deinit();
    // let x = 0
    const x_init = try store.bind("x", try store.int(0), while_expr);
    var test_blk_2216: BlockId = entry;
    _ = try mir.compileExpr(&store, x_init, &test_blk_2216, locals);

    var globals = std.AutoHashMap(u32, i64).init(allocator);
    defer globals.deinit();
    const result = try mir.execute(&globals);
    try std.testing.expectEqual(0, result); // while retourne toujours 0
}

test "mir — break in while" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    // while(1, break(42))
    const cond = try store.int(1);
    const break_val = try store.int(42);
    const break_expr = try store.binop("break", break_val);
    const while_expr = try store.binop("while", cond, break_expr);

    var mir = MirFunction.init(allocator);
    defer mir.deinit();

    const entry = try mir.newBlock();
    var locals = std.AutoHashMap(u32, Reg).init(allocator);
    defer locals.deinit();
    var test_blk_2241: BlockId = entry;
    _ = try mir.compileExpr(&store, while_expr, &test_blk_2241, locals);

    var globals = std.AutoHashMap(u32, i64).init(allocator);
    defer globals.deinit();
    const result = try mir.execute(&globals);
    try std.testing.expectEqual(42, result);
}

test "mir — if with break in while" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    // while(x < 5, if(x = 3, break(x), let x = x + 1))
    const x_sym = try store.interner.intern("x");
    _ = x_sym;
    const x_id = try store.sym("x");
    const cond = try store.binop("<", x_id, try store.int(5));
    const eq_cond = try store.binop("=", x_id, try store.int(3));
    const break_x = try store.binop("break", x_id);
    const inc = try store.binop("+", x_id, try store.int(1));
    const inc_bind = try store.bind("x", inc, try store.int(0));
    const if_expr = try store.binop("if", eq_cond, try store.binop(",", break_x, inc_bind));
    const while_expr = try store.binop("while", cond, if_expr);

    var mir = MirFunction.init(allocator);
    defer mir.deinit();

    const entry = try mir.newBlock();
    var locals = std.AutoHashMap(u32, Reg).init(allocator);
    defer locals.deinit();

    // let x = 0 in while(...)
    const full_expr = try store.bind("x", try store.int(0), while_expr);
    var test_blk_2275: BlockId = entry;
    _ = try mir.compileExpr(&store, full_expr, &test_blk_2275, locals);

    var globals = std.AutoHashMap(u32, i64).init(allocator);
    defer globals.deinit();
    const result = try mir.execute(&globals);
    try std.testing.expectEqual(3, result); // break(x) quand x=3
}

test "mir — user function definition and call" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    // Définir (def add [a b] (+ a b))
    // En syntaxe interne : (let add (lambda a (lambda b (+ a b))) (add 5 3))
    const a_sym = try store.interner.intern("a");
    const b_sym = try store.interner.intern("b");
    const a_id = try store.symId(a_sym);
    const b_id = try store.symId(b_sym);
    const plus = try store.binop("+", a_id, b_id);
    const lambda_b = try store.lambda(&.{"b"}, plus);
    const lambda_a = try store.lambda(&.{"a"}, lambda_b);
    const add_sym = try store.interner.intern("add");
    _ = add_sym;
    const call = try store.call("add", &.{ try store.int(5), try store.int(3) });
    const let_expr = try store.bind("add", lambda_a, call);

    var mir = MirFunction.init(allocator);
    defer mir.deinit();

    const entry = try mir.newBlock();
    var locals = std.AutoHashMap(u32, Reg).init(allocator);
    defer locals.deinit();
    var test_blk_2308: BlockId = entry;
    _ = try mir.compileExpr(&store, let_expr, &test_blk_2308, locals);
    // On doit s'assurer que le dernier bloc a un ret
    // On peut ajouter un ret du dernier résultat
    // Pour simplifier, on va modifier compileExpr pour qu'il ajoute un ret automatiquement.

    var globals = std.AutoHashMap(u32, i64).init(allocator);
    defer globals.deinit();
    const result = try mir.execute(&globals);
    try std.testing.expectEqual(8, result);
}

test "unlowering — reconstruction d'une opération binaire" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    // Construction d'un nœud abaissement: (+ 10 20)
    const lhs = try store.int(10);
    const rhs = try store.int(20);
    const expr_id = try store.binop("+", lhs, rhs);

    // Unlowering
    const unlowered = try expr_mod.unlower(&store, expr_id);
    switch (unlowered) {
        .binary_op => |bin| {
            const op_name = store.interner.resolve(bin.op);
            try std.testing.expectEqualStrings("+", op_name);

            const lhs_kind = try expr_mod.unlower(&store, bin.lhs);
            const rhs_kind = try expr_mod.unlower(&store, bin.rhs);
            try std.testing.expectEqual(i64(10), lhs_kind.literal);
            try std.testing.expectEqual(i64(20), rhs_kind.literal);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "unlowering — lambda simple : (lambda x (x))" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    // (lambda x (x))
    const x_sym = try store.interner.intern("x");
    const body = try store.sym(x_sym);
    const lam = try store.lambda(&.{"x"}, body);

    const u = try expr_mod.unlower(&store, lam);
    switch (u) {
        .function => |f| {
            try std.testing.expectEqual(x_sym, f.param);
            try std.testing.expectEqual(body, f.body);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "unlowering — variable nue : (sym x)" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const x_sym = try store.interner.intern("x");
    const x_id = try store.sym(x_sym);

    const u = try expr_mod.unlower(&store, x_id);
    switch (u) {
        .variable => |name| try std.testing.expectEqual(x_sym, name),
        else => return error.TestUnexpectedResult,
    }
}

test "unlowering — call générique : (f 1 2)" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const f = try store.sym("f");
    const a1 = try store.int(1);
    const a2 = try store.int(2);
    const call_id = try store.apply(f, &.{ a1, a2 });

    const u = try expr_mod.unlower(&store, call_id);
    switch (u) {
        .call => |c| {
            try std.testing.expectEqual(f, c.func);
            try std.testing.expectEqual(@as(usize, 2), c.args.len);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "unlowering — relation passthrough" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const a = try store.int(1);
    const b = try store.int(2);
    const rel = try store.relation("Eq", &.{a}, &.{b});

    const u = try expr_mod.unlower(&store, rel);
    switch (u) {
        .raw_primitive => |t| try std.testing.expectEqual(.relation, t),
        else => return error.TestUnexpectedResult,
    }
}

test "unlowering — conditional : (if c 1 2)" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const c = try store.sym("c");
    const t = try store.int(1);
    const e = try store.int(2);
    const if_op = try store.sym("if");
    const apply_id = try store.apply(if_op, &.{ c, t, e });

    const u = try expr_mod.unlower(&store, apply_id);
    switch (u) {
        .conditional => |k| {
            try std.testing.expectEqual(c, k.cond);
            try std.testing.expectEqual(t, k.then_branch);
            try std.testing.expectEqual(e, k.else_branch);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "unlowering — tuple : (tuple 1 2 3)" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const tup = try store.sym("tuple");
    const a1 = try store.int(1);
    const a2 = try store.int(2);
    const a3 = try store.int(3);
    const id = try store.apply(tup, &.{ a1, a2, a3 });

    const u = try expr_mod.unlower(&store, id);
    switch (u) {
        .tuple_lit => |elems| {
            try std.testing.expectEqual(@as(usize, 3), elems.len);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "unlowering — block : (block 1 2)" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const blk = try store.sym("block");
    const a1 = try store.int(1);
    const a2 = try store.int(2);
    const id = try store.apply(blk, &.{ a1, a2 });

    const u = try expr_mod.unlower(&store, id);
    switch (u) {
        .block_expr => |elems| try std.testing.expectEqual(@as(usize, 2), elems.len),
        else => return error.TestUnexpectedResult,
    }
}

test "unlowering — seq : (seq 1 2)" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const sq = try store.sym("seq");
    const a1 = try store.int(1);
    const a2 = try store.int(2);
    const id = try store.apply(sq, &.{ a1, a2 });

    const u = try expr_mod.unlower(&store, id);
    switch (u) {
        .seq_expr => |elems| try std.testing.expectEqual(@as(usize, 2), elems.len),
        else => return error.TestUnexpectedResult,
    }
}

test "mir — lowering et unlowering d'un lambda avec binding" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    // (bind x 5 (+ x 2))
    const x_sym = try store.interner.intern("x");
    const val_id = try store.int(5);
    const body_id = try store.binop("+", try store.sym(x_sym), try store.int(2));
    const bind_id = try store.bind(x_sym, val_id, body_id);

    var mir = MirFunction.init(allocator);
    defer mir.deinit();

    const entry = try mir.newBlock();
    var locals = std.AutoHashMap(u32, Reg).init(allocator);
    defer locals.deinit();

    var test_blk_2510: BlockId = entry;
    const res_reg = try mir.compileExpr(&store, bind_id, &test_blk_2510, locals);
    mir.blocks.items[entry].terminator = .{ .ret = res_reg };

    var globals = std.AutoHashMap(u32, i64).init(allocator);
    defer globals.deinit();

    const result = try mir.execute(&globals);
    try std.testing.expectEqual(@as(i64, 7), result);
}
