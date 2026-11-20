const std = @import("std");
const expr_mod = @import("expr");

const Sym = expr_mod.Sym;
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
    TerminatorInInstrs,
};

pub const PhiEntry = struct { value: Reg, block: BlockId };

pub const Instr = union(enum) {
    const_int: struct { dest: Reg, value: i64 },
    // 2026-10-30 : strings litterales (Sym = index dans str_pool)
    const_str: struct { dest: Reg, sym: u32 },
    add: struct { dest: Reg, lhs: Reg, rhs: Reg },
    sub: struct { dest: Reg, lhs: Reg, rhs: Reg },
    mul: struct { dest: Reg, lhs: Reg, rhs: Reg },
    div: struct { dest: Reg, lhs: Reg, rhs: Reg },
    rem: struct { dest: Reg, lhs: Reg, rhs: Reg },
    cmp_lt: struct { dest: Reg, lhs: Reg, rhs: Reg },
    cmp_eq: struct { dest: Reg, lhs: Reg, rhs: Reg },
    jump: struct { target: BlockId },
    branch: struct { cond: Reg, then_block: BlockId, else_block: BlockId },
    ret: struct { value: Reg },
    phi: struct { dest: Reg, incoming: []const PhiEntry },
    load: struct { dest: Reg, sym: u32 },
    store: struct { sym: u32, src: Reg },
    // 2026-10-30 : opcodes heap pour fst/snd/pair/cons.
    alloc: struct { dest: Reg, size: u32 },
    load_at: struct { dest: Reg, base: Reg, offset: u32 },
    store_at: struct { base: Reg, offset: u32, src: Reg },
    call_user: struct { dest: Reg, name: u32, args: []const Reg },
    extern_call: struct { dest: Reg, name: u32, args: []const Reg },
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

pub fn FnDef(comptime MirFnType: type) type {
    return struct {
        fn_mir: MirFnType,
        param_names: []const Sym,
        param_regs: []const Reg,
    };
}

/// Info sur un SCC fusionne par fuseTailSCCs.
pub const FusedSccInfo = struct {
    scc_sym: u32,
    members: []const u32,
};

/// Cherche l'index d'un symbol dans un SCC. Null si absent.
pub fn findMemberIdx(members: []const u32, sym: u32) ?u32 {
    for (members, 0..) |m, i| if (m == sym) return @intCast(i);
    return null;
}

/// Helpers de decalage pour la fusion SCC. Utilises pour copier les
/// blocs et regs d'une fonction source dans une fonction fusionnee en
/// evitant les collisions de numerotation.
pub fn shiftReg(r: Reg, off: u32) Reg {
    return r + off;
}

pub fn shiftPhiEntry(in: PhiEntry, reg_off: u32, block_off: u32) PhiEntry {
    return .{ .value = in.value + reg_off, .block = in.block + block_off };
}

pub fn shiftInstr(allocator: std.mem.Allocator, inst: Instr, reg_off: u32, block_off: u32) !Instr {
    return switch (inst) {
        .const_int => |c| .{ .const_int = .{ .dest = c.dest + reg_off, .value = c.value } },
        .const_str => |c| .{ .const_str = .{ .dest = c.dest + reg_off, .sym = c.sym } },
        .add => |a| .{ .add = .{ .dest = a.dest + reg_off, .lhs = a.lhs + reg_off, .rhs = a.rhs + reg_off } },
        .sub => |a| .{ .sub = .{ .dest = a.dest + reg_off, .lhs = a.lhs + reg_off, .rhs = a.rhs + reg_off } },
        .mul => |a| .{ .mul = .{ .dest = a.dest + reg_off, .lhs = a.lhs + reg_off, .rhs = a.rhs + reg_off } },
        .div => |a| .{ .div = .{ .dest = a.dest + reg_off, .lhs = a.lhs + reg_off, .rhs = a.rhs + reg_off } },
        .rem => |a| .{ .rem = .{ .dest = a.dest + reg_off, .lhs = a.lhs + reg_off, .rhs = a.rhs + reg_off } },
        .cmp_lt => |a| .{ .cmp_lt = .{ .dest = a.dest + reg_off, .lhs = a.lhs + reg_off, .rhs = a.rhs + reg_off } },
        .cmp_eq => |a| .{ .cmp_eq = .{ .dest = a.dest + reg_off, .lhs = a.lhs + reg_off, .rhs = a.rhs + reg_off } },
        .load => |l| .{ .load = .{ .dest = l.dest + reg_off, .sym = l.sym } },
        .store => |st| .{ .store = .{ .sym = st.sym, .src = st.src + reg_off } },
        .alloc => |a| .{ .alloc = .{ .dest = a.dest + reg_off, .size = a.size } },
        .load_at => |l| .{ .load_at = .{ .dest = l.dest + reg_off, .base = l.base + reg_off, .offset = l.offset } },
        .store_at => |st| .{ .store_at = .{ .base = st.base + reg_off, .offset = st.offset, .src = st.src + reg_off } },
        .call_user => |c| blk: {
            const args = try allocator.alloc(Reg, c.args.len);
            for (c.args, 0..) |arg, i| args[i] = arg + reg_off;
            break :blk .{ .call_user = .{ .dest = c.dest + reg_off, .name = c.name, .args = args } };
        },
        .extern_call => |c| blk: {
            const args = try allocator.alloc(Reg, c.args.len);
            for (c.args, 0..) |arg, i| args[i] = arg + reg_off;
            break :blk .{ .extern_call = .{ .dest = c.dest + reg_off, .name = c.name, .args = args } };
        },
        .phi => |p| blk: {
            const incoming = try allocator.alloc(PhiEntry, p.incoming.len);
            for (p.incoming, 0..) |in, i| incoming[i] = shiftPhiEntry(in, reg_off, block_off);
            break :blk .{ .phi = .{ .dest = p.dest + reg_off, .incoming = incoming } };
        },
        .jump, .branch, .ret => return error.TerminatorInInstrs,
    };
}

/// Copie les blocs de `src` dans `fused` avec decalage reg_off / block_off.
/// Reecrit les call_user vers a_sym ou b_sym en call_user vers scc_sym
/// avec un tag constant (0 pour a, 1 pour b).
pub fn copyBlocksForFusion(
    fused: anytype,
    src: anytype,
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

/// Variante N-ary de copyBlocksForFusion. Reecrit tout call_user
/// vers un membre du SCC en call_user vers scc_sym avec tag = index
/// du membre dans le SCC.
pub fn copyBlocksForFusionN(
    fused: anytype,
    src: anytype,
    allocator: std.mem.Allocator,
    reg_off: u32,
    block_off: u32,
    members: []const u32,
    scc_sym: u32,
) !void {
    for (src.blocks.items) |src_blk| {
        var new_blk = BasicBlock{ .instrs = .{}, .terminator = .fallthrough };
        for (src_blk.instrs.items) |inst| {
            switch (inst) {
                .call_user => |c| {
                    if (findMemberIdx(members, c.name)) |mi| {
                        const tag_value: i64 = @intCast(mi);
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

/// Pure predicate for SCC fusion gating. Inverse convention of
/// HEAVEN_NO_* flags: opt-in because the wrapper ABI is broken
/// (cf _claims_vs_reality.md claim #5 Update 3). Default off.
pub fn sccFusionEnabledFromEnv(env_val: ?[]const u8) bool {
    const v = env_val orelse return false;
    return v.len > 0 and !std.mem.eql(u8, v, "0");
}

/// `pair` et `cons` sont des builtins heap SANS tag : champs aux offsets 0 et 8
/// (cf. compileExpr, lus par fst/snd/head/tail). Le chemin des constructeurs ADT
/// n-aires ecrit au contraire un tag a l'offset 0 et les champs a partir de 8.
/// Mele a ces builtins, `head (cons 42 ...)` lisait le tag (1) au lieu de 42
/// (reponse fausse silencieuse, regression c880598). Ces deux noms restent donc
/// sur leur disposition builtin : ni construction ADT, ni filtrage ADT.
pub fn isBuiltinHeapCtor(name: []const u8) bool {
    return std.mem.eql(u8, name, "pair") or std.mem.eql(u8, name, "cons");
}
