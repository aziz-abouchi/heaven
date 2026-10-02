const std = @import("std");
const expr_mod = @import("expr");
const engine_mod = @import("engine_expr");

const Sym = expr_mod.Sym;
const Store = expr_mod.Store;
pub const Id = expr_mod.Id;

// Représente un registre virtuel MIR (indépendant des Reg de l'AST)
pub const Reg = u32;

// ValueId remplacé par Reg (Expr IR)
// pub const ValueId = u32;
pub const BlockId = u32;

pub const MirError = error{
    UnsupportedExpr,
    UnsupportedLiteral,
    UnsupportedOp,
    OutOfMemory,
    DivisionByzero,
    InvalidInstruction,
    ValueNotDefined,
    UndefinedVariable,
    TooManyIterations,
    BreakOutsideLoop,
};

const PhiEntry = struct { value: Reg, block: BlockId };

pub const Instr = union(enum) {
    const_int: struct { dest: Reg, value: i64 },
    add: struct { dest: Reg, lhs: Reg, rhs: Reg },
    sub: struct { dest: Reg, lhs: Reg, rhs: Reg },
    mul: struct { dest: Reg, lhs: Reg, rhs: Reg },
    div: struct { dest: Reg, lhs: Reg, rhs: Reg },
    cmp_lt: struct { dest: Reg, lhs: Reg, rhs: Reg },
    cmp_eq: struct { dest: Reg, lhs: Reg, rhs: Reg },
    jump: struct { target: BlockId },
    branch: struct { cond: Reg, then_block: BlockId, else_block: BlockId },
    ret: struct { value: Reg },
    phi: struct { dest: Reg, incoming: []const PhiEntry },
    load: struct { dest: Reg, sym: u32 },
    store: struct { sym: u32, src: Reg },
    call_user: struct { dest: Reg, name: u32, args: []const Reg },
};

pub const BasicBlock = struct {
    instrs: std.ArrayListUnmanaged(Instr),
    terminator: union(enum) {
        jump: BlockId,
        branch: struct { cond: Reg, then_block: BlockId, else_block: BlockId },
        ret: Reg,
        fallthrough,
    },
};

pub const FnDef = struct {
    fn_mir: MirFunction,
    param_names: []const Sym,
    param_regs: []const Reg,
};

/// Copie les blocs de `src` dans `fused` avec decalage reg_off / block_off.
/// Reecrit les call_user vers a_sym ou b_sym en call_user vers scc_sym
/// avec un tag constant (0 pour a, 1 pour b).
fn copyBlocksForFusion(
    fused: *MirFunction,
    src: *const MirFunction,
    allocator: std.mem.Allocator,
    reg_off: u32,
    block_off: u32,
    a_sym: u32,
    b_sym: u32,
    scc_sym: u32,
) !void {
    for (src.blocks.items) |src_blk| {
        var new_blk = BasicBlock{ .instrs = .{}, .terminator = .fallthrough };
        for (src_blk.instrs.items) |inst| {
            switch (inst) {
                .call_user => |c| {
                    if (c.name == a_sym or c.name == b_sym) {
                        const tag_value: i64 = if (c.name == a_sym) 0 else 1;
                        const tag_c = fused.newReg();
                        try new_blk.instrs.append(allocator, .{ .const_int = .{ .dest = tag_c, .value = tag_value } });
                        const new_args = try allocator.alloc(Reg, c.args.len + 1);
                        for (c.args, 0..) |arg, idx| new_args[idx] = arg + reg_off;
                        new_args[c.args.len] = tag_c;
                        try new_blk.instrs.append(allocator, .{ .call_user = .{
                            .dest = c.dest + reg_off,
                            .name = scc_sym,
                            .args = new_args,
                        } });
                    } else {
                        try new_blk.instrs.append(allocator, try shiftInstr(allocator, inst, reg_off, block_off));
                    }
                },
                else => try new_blk.instrs.append(allocator, try shiftInstr(allocator, inst, reg_off, block_off)),
            }
        }
        new_blk.terminator = switch (src_blk.terminator) {
            .ret => |rv| .{ .ret = rv + reg_off },
            .jump => |t| .{ .jump = t + block_off },
            .branch => |b| .{ .branch = .{ .cond = b.cond + reg_off, .then_block = b.then_block + block_off, .else_block = b.else_block + block_off } },
            .fallthrough => .fallthrough,
        };
        try fused.blocks.append(allocator, new_blk);
    }
}

/// Helpers de decalage pour la fusion SCC. Utilises pour copier les
/// blocs et regs d'une fonction source dans une fonction fusionnee en
/// evitant les collisions de numerotation.
fn shiftReg(r: Reg, off: u32) Reg {
    return r + off;
}

fn shiftPhiEntry(in: PhiEntry, reg_off: u32, block_off: u32) PhiEntry {
    return .{ .value = in.value + reg_off, .block = in.block + block_off };
}

fn shiftInstr(allocator: std.mem.Allocator, inst: Instr, reg_off: u32, block_off: u32) !Instr {
    return switch (inst) {
        .const_int => |c| .{ .const_int = .{ .dest = c.dest + reg_off, .value = c.value } },
        .add => |a| .{ .add = .{ .dest = a.dest + reg_off, .lhs = a.lhs + reg_off, .rhs = a.rhs + reg_off } },
        .sub => |a| .{ .sub = .{ .dest = a.dest + reg_off, .lhs = a.lhs + reg_off, .rhs = a.rhs + reg_off } },
        .mul => |a| .{ .mul = .{ .dest = a.dest + reg_off, .lhs = a.lhs + reg_off, .rhs = a.rhs + reg_off } },
        .div => |a| .{ .div = .{ .dest = a.dest + reg_off, .lhs = a.lhs + reg_off, .rhs = a.rhs + reg_off } },
        .cmp_lt => |a| .{ .cmp_lt = .{ .dest = a.dest + reg_off, .lhs = a.lhs + reg_off, .rhs = a.rhs + reg_off } },
        .cmp_eq => |a| .{ .cmp_eq = .{ .dest = a.dest + reg_off, .lhs = a.lhs + reg_off, .rhs = a.rhs + reg_off } },
        .load => |l| .{ .load = .{ .dest = l.dest + reg_off, .sym = l.sym } },
        .store => |st| .{ .store = .{ .sym = st.sym, .src = st.src + reg_off } },
        .call_user => |c| blk: {
            const args = try allocator.alloc(Reg, c.args.len);
            for (c.args, 0..) |arg, i| args[i] = arg + reg_off;
            break :blk .{ .call_user = .{ .dest = c.dest + reg_off, .name = c.name, .args = args } };
        },
        .phi => |p| blk: {
            const incoming = try allocator.alloc(PhiEntry, p.incoming.len);
            for (p.incoming, 0..) |in, i| incoming[i] = shiftPhiEntry(in, reg_off, block_off);
            break :blk .{ .phi = .{ .dest = p.dest + reg_off, .incoming = incoming } };
        },
        .jump, .branch, .ret => return error.TerminatorInInstrs,
    };
}

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
    values: std.ArrayListUnmanaged(i64),

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
                        if (ins != .phi) { only_phi = false; break; }
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
        for (def.param_regs) |r| if (r > max_r) { max_r = r; };
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
        while (it.next()) |k| if (k.* > max_sym) { max_sym = k.*; };

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
                    else => {},
                }
            }
            blk.instrs.deinit(self.allocator);
        }
        self.blocks.deinit(self.allocator);
        self.break_values.deinit(self.allocator);

        // Libérer les définitions de fonctions
        var it = self.fn_defs.valueIterator();
        while (it.next()) |def| {
            def.fn_mir.deinit();
            self.allocator.free(def.param_names);
            self.allocator.free(def.param_regs);
        }
        self.fn_defs.deinit();

        self.values.deinit(self.allocator);
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
    pub fn precompileUserFns(self: *MirFunction) !void {
        const engine = self.engine orelse return;
        const store = self.store orelse return;

        // Passe 1 : repertorier les noms de fonctions utilisateur
        // eligibles.
        var eligible: std.ArrayListUnmanaged([]const u8) = .{};
        defer eligible.deinit(self.allocator);

        var it_names = engine.fns.iterator();
        while (it_names.next()) |entry| {
            const name_str = entry.key_ptr.*;
            const fn_def_user = entry.value_ptr.*;

            if (fn_def_user.ctor_arity != null) continue;
            if (fn_def_user.num_clauses != 1) continue;

            const clause = fn_def_user.clauses[0];
            if (std.mem.eql(u8, name_str, "choose") or std.mem.eql(u8, name_str, "fib")) {
                std.debug.print("[mir-filt] '{s}': num_patterns={d}\n", .{ name_str, clause.num_patterns });
            }
            var all_syms = true;
            for (0..clause.num_patterns) |i| {
                const pat = store.get(clause.patterns[i]);
                if (pat.tag != .sym) {
                    all_syms = false;
                    break;
                }
            }
            if (std.mem.eql(u8, name_str, "choose") or std.mem.eql(u8, name_str, "fib")) {
                std.debug.print("[mir-filt] '{s}': all_syms={}\n", .{ name_str, all_syms });
            }
            if (!all_syms) continue;

            try eligible.append(self.allocator, name_str);
        }

        // Passe 1 (suite) : pre-enregistrer les placeholders (fn_mir
        // vide, mais nom dans fn_defs). Indispensable pour que les
        // appels recursifs (fib appelle fib) soient resolus par
        // checkCallUsers a l'emission.
        for (eligible.items) |name_str| {
            const name_sym = store.interner.lookup(name_str) orelse continue;
            if (self.fn_defs.contains(name_sym)) continue;

            const fn_def_user = engine.fns.get(name_str) orelse continue;
            const clause = fn_def_user.clauses[0];

            var fn_mir = MirFunction.init(self.allocator);
            fn_mir.store = store;
            fn_mir.engine = engine;
            errdefer fn_mir.deinit();

            _ = try fn_mir.newBlock();
            const param_regs = try self.allocator.alloc(Reg, clause.num_patterns);
            errdefer self.allocator.free(param_regs);
            const param_names = try self.allocator.alloc(Sym, clause.num_patterns);
            errdefer self.allocator.free(param_names);

            var locals = std.AutoHashMap(u32, Reg).init(self.allocator);
            defer locals.deinit();

            for (0..clause.num_patterns) |i| {
                const pat_node = store.get(clause.patterns[i]);
                const param_sym = pat_node.payload;
                const reg = fn_mir.newReg();
                param_regs[i] = reg;
                param_names[i] = param_sym;
                try locals.put(param_sym, reg);
            }

            try self.fn_defs.put(name_sym, .{
                .fn_mir = fn_mir,
                .param_names = param_names,
                .param_regs = param_regs,
            });
        }

        // Passe 2 : compiler les corps. Tous les noms sont deja dans
        // fn_defs, donc les appels recursifs sont resolus.
        for (eligible.items) |name_str| {
            const name_sym = store.interner.lookup(name_str) orelse continue;
            const def = self.fn_defs.getPtr(name_sym) orelse continue;

            // Skip si deja compile (plus dun bloc = corps compile).
            if (def.fn_mir.blocks.items.len > 1) continue;

            const fn_def_user = engine.fns.get(name_str) orelse continue;
            const clause = fn_def_user.clauses[0];

            var locals = std.AutoHashMap(u32, Reg).init(self.allocator);
            defer locals.deinit();
            for (def.param_regs, 0..) |reg, i| {
                try locals.put(def.param_names[i], reg);
            }

            // Le corps de la clause est en forme frontend (.binop,
            // .call, etc.). MIR attend du Core (.apply, .lit, .sym).
            // lowerRec fait la conversion (meme pipeline que parseLastExpr
            // dans qbe_cmd.zig / wasm_cmd.zig).
            const lowered_body = store.lowerRec(clause.body) catch {
                if (self.fn_defs.fetchRemove(name_sym)) |kv| {
                    var v = kv.value;
                    v.fn_mir.deinit();
                    self.allocator.free(v.param_names);
                    self.allocator.free(v.param_regs);
                }
                continue;
            };
            const result = def.fn_mir.compileExpr(store, lowered_body, 0, locals) catch {
                // Recuperer la valeur pour liberer proprement avant
                // de la retirer de fn_defs.
                if (self.fn_defs.fetchRemove(name_sym)) |kv| {
                    var v = kv.value;
                    v.fn_mir.deinit();
                    self.allocator.free(v.param_names);
                    self.allocator.free(v.param_regs);
                }
                continue;
            };
            if (def.fn_mir.blocks.items[0].terminator == .fallthrough) {
                def.fn_mir.blocks.items[0].terminator = .{ .ret = result };
            }
        }
    }

    /// Alloue un nœud placeholder dans le Store Expr IR pour une valeur MIR
    pub fn newReg(self: *MirFunction) Reg {
        const reg = self.next_value;
        self.next_value += 1;
        return reg;
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

    fn compileLambda(self: *MirFunction, store: *Store, lambda_id: Reg) !FnDef {
        // Déplier les lambdas pour récupérer la liste des paramètres et le corps final
        var params = std.ArrayListUnmanaged(u32){};
        defer params.deinit(self.allocator);
        var current_id = lambda_id;
        var current_node = store.get(current_id);
        while (current_node.tag == .lambda) {
            try params.append(self.allocator, current_node.payload);
            const body_ids = current_node.span_a.slice(store.pool.items);
            if (body_ids.len == 0) return error.UnsupportedExpr;
            current_id = body_ids[0];
            current_node = store.get(current_id);
        }
        // current_id est le corps final
        // Créer un nouveau MirFunction pour la définition
        var fn_mir = MirFunction.init(self.allocator);
        // Allouer des registres pour les paramètres
        var param_regs = std.ArrayListUnmanaged(Id){};
        defer param_regs.deinit(self.allocator);
        var param_map = std.AutoHashMap(Sym, Reg).init(self.allocator);
        defer param_map.deinit();
        for (params.items) |p| {
            const reg = fn_mir.newReg();
            try param_regs.append(self.allocator, reg);
            try param_map.put(p, reg);
        }
        // Compiler le corps dans la nouvelle fonction
        const entry = try fn_mir.newBlock();
        const result_reg = try fn_mir.compileExpr(store, current_id, entry, param_map);
        fn_mir.blocks.items[entry].terminator = .{ .ret = result_reg };
        // Créer la définition
        return FnDef{
            .fn_mir = fn_mir,
            .param_names = try params.toOwnedSlice(self.allocator),
            .param_regs = try param_regs.toOwnedSlice(self.allocator),
        };
    }

    pub fn compileExpr(self: *MirFunction, store: *Store, id: Id, target_block: BlockId, locals: std.AutoHashMap(u32, Reg)) MirError!Reg {
        const node = store.get(id);
        // std.debug.print("[mir-tag] compileExpr tag={any}\n", .{node.tag});
        switch (node.tag) {
            .bind => {
                const sym = node.payload;
                // La valeur est dans node.span_a[0] (ou node.aux ? Vérifier)
                // D'après la construction de bind, le span_a contient [val, body] ? Non, bind est construit avec un seul argument ? Dans Store.bind, on met val et corps par défaut unit.
                // En fait, bind a node.span_a qui contient [val, body] (car on utilise reserveSpan(2)).
                // Donc span_a[0] = valeur, span_a[1] = corps.
                const val_id = node.span_a.slice(store.pool.items)[0];
                const body_id = if (node.span_a.len > 1) node.span_a.slice(store.pool.items)[1] else 0;
                // Compiler la valeur
                const val_reg = try self.compileExpr(store, val_id, target_block, locals);
                // Si la valeur est un lambda, enregistrer la fonction
                const val_node = store.get(val_id);
                if (val_node.tag == .lambda) {
                    const fn_def = try self.compileLambda(store, val_id);
                    try self.fn_defs.put(sym, fn_def);
                }
                // Ajouter la variable locale
                var new_locals = try locals.clone();
                defer new_locals.deinit();
                try new_locals.put(sym, val_reg);
                // Compiler le corps
                if (body_id != 0) {
                    return try self.compileExpr(store, body_id, target_block, new_locals);
                }
                return val_reg;
            },
            .sym => {
                const sym = node.payload;
                if (locals.get(sym)) |reg| {
                    return reg;
                }
                const dest = self.newReg();
                try self.blocks.items[target_block].instrs.append(self.allocator, .{ .load = .{ .dest = dest, .sym = sym } });
                return dest;
            },
            .lit => {
                const l = store.lits.items[node.aux];
                switch (l) {
                    .int => |v| {
                        const dest = self.newReg();
                        try self.blocks.items[target_block].instrs.append(self.allocator, .{ .const_int = .{ .dest = dest, .value = v } });
                        return dest;
                    },
                    else => return error.UnsupportedLiteral,
                }
            },
            .apply => {
                const func_node = store.get(node.payload);
                if (func_node.tag != .sym) {
                    return error.UnsupportedExpr;
                }
                const op_name = store.interner.resolve(func_node.payload);
                // Convention Store : span_a[0] = func_id (docs/spec/
                // _store_invariants.md). Certains tests construisent
                // span_a = [arg0, arg1, ...] (sans le func). On
                // normalise : si le premier arg est le func lui-meme,
                // on le saute.
                const raw_args = node.span_a.slice(store.pool.items);
                const args = if (raw_args.len > 0 and raw_args[0] == node.payload)
                    raw_args[1..]
                else
                    raw_args;

                if (std.mem.eql(u8, op_name, "while") and args.len == 2) {
                    return try self.compileWhile(store, args[0], args[1], target_block, locals);
                }
                if (std.mem.eql(u8, op_name, "if") and args.len == 3) {
                    return try self.compileIf(store, args[0], args[1], args[2], target_block, locals);
                }
                if (std.mem.eql(u8, op_name, "break") and args.len == 1) {
                    return try self.compileBreak(store, args[0], target_block, locals);
                }

                // Appel de fonction utilisateur
                if (self.engine) |engine| {
                    if (engine.fns.get(op_name) != null) {
                        var arg_regs = std.ArrayListUnmanaged(Id){};
                        defer arg_regs.deinit(self.allocator);
                        for (args) |arg| {
                            const arg_reg = try self.compileExpr(store, arg, target_block, locals);
                            try arg_regs.append(self.allocator, arg_reg);
                        }
                        const dest = self.newReg();
                        const name_sym = func_node.payload;
                        const arg_slice = try self.allocator.dupe(Id, arg_regs.items);
                        errdefer self.allocator.free(arg_slice);
                        try self.blocks.items[target_block].instrs.append(self.allocator, .{
                            .call_user = .{ .dest = dest, .name = name_sym, .args = arg_slice },
                        });
                        return dest;
                    }
                }

                if (args.len == 2) {
                    const lhs = try self.compileExpr(store, args[0], target_block, locals);
                    const rhs = try self.compileExpr(store, args[1], target_block, locals);
                    const dest = self.newReg();
                    const op: Instr = if (std.mem.eql(u8, op_name, "+"))
                        .{ .add = .{ .dest = dest, .lhs = lhs, .rhs = rhs } }
                    else if (std.mem.eql(u8, op_name, "-"))
                        .{ .sub = .{ .dest = dest, .lhs = lhs, .rhs = rhs } }
                    else if (std.mem.eql(u8, op_name, "*"))
                        .{ .mul = .{ .dest = dest, .lhs = lhs, .rhs = rhs } }
                    else if (std.mem.eql(u8, op_name, "/"))
                        .{ .div = .{ .dest = dest, .lhs = lhs, .rhs = rhs } }
                    else if (std.mem.eql(u8, op_name, "<"))
                        .{ .cmp_lt = .{ .dest = dest, .lhs = lhs, .rhs = rhs } }
                    else if (std.mem.eql(u8, op_name, "="))
                        .{ .cmp_eq = .{ .dest = dest, .lhs = lhs, .rhs = rhs } }
                    else
                        return error.UnsupportedOp;
                    try self.blocks.items[target_block].instrs.append(self.allocator, op);
                    return dest;
                }
                return error.UnsupportedExpr;
            },
            else => {
                return error.UnsupportedExpr;
            },
        }
    }

    fn compileIf(self: *MirFunction, store: *Store, cond_id: Reg, then_id: Reg, else_id: Reg, entry_block: BlockId, locals: std.AutoHashMap(u32, Reg)) MirError!Id {
        const cond_val = try self.compileExpr(store, cond_id, entry_block, locals);
        const then_block = try self.newBlock();
        const else_block = try self.newBlock();
        const merge_block = try self.newBlock();

        self.blocks.items[entry_block].terminator = .{ .branch = .{ .cond = cond_val, .then_block = then_block, .else_block = else_block } };

        const then_val = try self.compileExpr(store, then_id, then_block, locals);
        // Si le bloc then ne s'est pas déjà terminé (par un break/ret), on jump au merge
        if (std.meta.activeTag(self.blocks.items[then_block].terminator) == .fallthrough) {
            self.blocks.items[then_block].terminator = .{ .jump = merge_block };
        }

        const else_val = try self.compileExpr(store, else_id, else_block, locals);
        if (self.blocks.items[else_block].terminator == .fallthrough) {
            self.blocks.items[else_block].terminator = .{ .jump = merge_block };
        }

        const phi_dest = self.newReg();
        // Ne collecter que les blocs qui jumpent vers merge_block
        var incoming = std.ArrayListUnmanaged(PhiEntry){};
        defer incoming.deinit(self.allocator);

        if (std.meta.activeTag(self.blocks.items[then_block].terminator) == .jump and self.blocks.items[then_block].terminator.jump == merge_block) {
            try incoming.append(self.allocator, .{ .value = then_val, .block = then_block });
        }
        if (self.blocks.items[else_block].terminator == .jump and self.blocks.items[else_block].terminator.jump == merge_block) {
            try incoming.append(self.allocator, .{ .value = else_val, .block = else_block });
        }

        // S'il y a au moins un incoming, on crée un phi
        if (incoming.items.len > 0) {
            const incoming_copy = try self.allocator.dupe(PhiEntry, incoming.items);
            errdefer self.allocator.free(incoming_copy);
            try self.blocks.items[merge_block].instrs.append(self.allocator, .{ .phi = .{ .dest = phi_dest, .incoming = incoming_copy } });
            self.blocks.items[merge_block].terminator = .{ .ret = phi_dest };
        } else {
            // Pas de phi nécessaire, retourner 0
            try self.blocks.items[merge_block].instrs.append(self.allocator, .{ .const_int = .{ .dest = phi_dest, .value = 0 } });
            self.blocks.items[merge_block].terminator = .{ .ret = phi_dest };
        }

        return phi_dest;
    }

    fn compileWhile(self: *MirFunction, store: *Store, cond_id: Reg, body_id: Reg, entry_block: BlockId, locals: std.AutoHashMap(u32, Reg)) MirError!Id {
        const cond_block = try self.newBlock();
        const body_block = try self.newBlock();
        const exit_block = try self.newBlock();

        // Sauvegarder l'état de la boucle parente
        const old_exit = self.loop_exit_block;
        const old_break_values_len = self.break_values.items.len;

        self.loop_exit_block = exit_block;

        self.blocks.items[entry_block].terminator = .{ .jump = cond_block };

        const cond_val = try self.compileExpr(store, cond_id, cond_block, locals);

        // Valeur de sortie normale (condition fausse). Doit figurer
        // comme incoming du phi de sortie si des breaks existent : le
        // CFG a un arc cond_block -> exit_block (else du branch), et
        // QBE exige que TOUS les predecesseurs reels d'un bloc
        // apparaissent dans ses phis ("predecessors not matched").
        const normal_exit_reg = self.newReg();
        try self.blocks.items[cond_block].instrs.append(self.allocator, .{ .const_int = .{ .dest = normal_exit_reg, .value = 0 } });

        self.blocks.items[cond_block].terminator = .{ .branch = .{ .cond = cond_val, .then_block = body_block, .else_block = exit_block } };

        _ = try self.compileExpr(store, body_id, body_block, locals);
        // Si le corps ne s'est pas terminé par un break, on reboucle
        if (self.blocks.items[body_block].terminator == .fallthrough) {
            self.blocks.items[body_block].terminator = .{ .jump = cond_block };
        }

        // Collecter les valeurs de break pour le phi à la sortie
        const break_entries = self.break_values.items[old_break_values_len..];
        const phi_dest = self.newReg();

        if (break_entries.len > 0) {
            // Phi de sortie : tous les breaks + la sortie normale
            // (condition fausse -> 0).
            var incoming = std.ArrayList(PhiEntry).empty;
            defer incoming.deinit(self.allocator);
            try incoming.appendSlice(self.allocator, break_entries);
            try incoming.append(self.allocator, .{ .value = normal_exit_reg, .block = cond_block });

            const incoming_copy = try self.allocator.dupe(PhiEntry, incoming.items);
            errdefer self.allocator.free(incoming_copy);
            try self.blocks.items[exit_block].instrs.append(self.allocator, .{ .phi = .{ .dest = phi_dest, .incoming = incoming_copy } });
        } else {
            // Pas de break, retourner 0
            try self.blocks.items[exit_block].instrs.append(self.allocator, .{ .const_int = .{ .dest = phi_dest, .value = 0 } });
        }

        self.blocks.items[exit_block].terminator = .{ .ret = phi_dest };

        // Restaurer l'état de la boucle parente
        self.break_values.shrinkRetainingCapacity(old_break_values_len);
        self.loop_exit_block = old_exit;

        return phi_dest;
    }

    fn compileBreak(self: *MirFunction, store: *Store, value_expr_id: Reg, target_block: BlockId, locals: std.AutoHashMap(u32, Reg)) MirError!Id {
        const exit_block = self.loop_exit_block orelse return error.BreakOutsideLoop;
        const val_reg = try self.compileExpr(store, value_expr_id, target_block, locals);

        // Enregistrer la valeur de break pour le phi à la sortie
        try self.break_values.append(self.allocator, .{ .value = val_reg, .block = target_block });

        // Sauter au bloc de sortie de la boucle
        self.blocks.items[target_block].terminator = .{ .jump = exit_block };
        return val_reg;
    }

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
                    .cmp_lt => |a| {
                        if (a.dest >= self.values.items.len) try self.values.resize(self.allocator, a.dest + 1);
                        self.values.items[a.dest] = if (self.values.items[a.lhs] < self.values.items[a.rhs]) 1 else 0;
                    },
                    .cmp_eq => |a| {
                        if (a.dest >= self.values.items.len) try self.values.resize(self.allocator, a.dest + 1);
                        self.values.items[a.dest] = if (self.values.items[a.lhs] == self.values.items[a.rhs]) 1 else 0;
                    },
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
                try new_block.instrs.append(self.allocator, inst);
            }
            try new_mir.blocks.append(self.allocator, new_block);
        }
        // Copier les autres champs nécessaires (store, engine, etc.)
        new_mir.store = self.store;
        new_mir.engine = self.engine;
        new_mir.store_ref = self.store_ref;
        // On pourrait copier d'autres choses si besoin
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
    _ = try mir.compileExpr(&store, expr_id, entry, std.AutoHashMap(u32, Reg).init(allocator));
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
    _ = try mir.compileExpr(&store, expr_id, entry, locals);

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
    _ = try mir.compileExpr(&store, x_init, entry, locals);

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
    _ = try mir.compileExpr(&store, while_expr, entry, locals);

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
    _ = try mir.compileExpr(&store, full_expr, entry, locals);

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
    _ = try mir.compileExpr(&store, let_expr, entry, locals);
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

    const res_reg = try mir.compileExpr(&store, bind_id, entry, locals);
    mir.blocks.items[entry].terminator = .{ .ret = res_reg };

    var globals = std.AutoHashMap(u32, i64).init(allocator);
    defer globals.deinit();

    const result = try mir.execute(&globals);
    try std.testing.expectEqual(@as(i64, 7), result);
}
