//! MIR → QBE IL : émetteur (jalon M3 — docs/BACKENDS.md).
//! Contrat : docs/MIR_CONTRACT.md. Lecture seule de MirFunction.
//! call_user hors fn_defs → error.UnsupportedCall (jamais de repli
//! silencieux sur l'interprète). Le wrapper $main printf le résultat
//! (exit code = 8 bits, insuffisant pour un i64).

const std = @import("std");
const mir = @import("mir");

const MirFunction = mir.MirFunction;
const FnDef = mir.FnDef;
const Instr = mir.Instr;
const BlockId = mir.BlockId;
const Reg = mir.Reg;
const BasicBlock = mir.BasicBlock;

/// Émet l'IL complet : globals, une fonction par fn_def (locales),
/// $heaven_main (le MIR root), $main exporté qui printf le résultat.
pub fn emitQbe(allocator: std.mem.Allocator, root: *const MirFunction) ![]u8 {
    // Fail-fast : verifier tous les call_user AVANT d'ecrire un seul
    // octet. Conforme au contrat docs/MIR_CONTRACT.md §6 : un appel
    // vers une fonction hors fn_defs doit etre rejete explicitement,
    // jamais silencieusement transforme en .ssa que QBE refusera
    // avec un message obscur.
    try checkCallUsers(root);

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    const w = buf.writer(allocator);

    var global_set = std.AutoHashMap(u32, void).init(allocator);
    defer global_set.deinit();
    try collectGlobals(&global_set, root);
    var fit = root.fn_defs.keyIterator();
    while (fit.next()) |k| {
        const fd = root.fn_defs.get(k.*).?;
        try collectGlobals(&global_set, &fd.fn_mir);
    }
    var git = global_set.keyIterator();
    while (git.next()) |g| {
        try w.print("data $g{d} = {{ l 0 }}\n", .{g.*});
    }

    var fn_names: std.ArrayList(u32) = .empty;
    defer fn_names.deinit(allocator);
    var kit = root.fn_defs.keyIterator();
    while (kit.next()) |k| try fn_names.append(allocator, k.*);

    for (fn_names.items) |sym| {
        const def = root.fn_defs.get(sym).?;
        try w.print("function l $f{d}(", .{sym});
        for (def.param_regs, 0..) |_, i| {
            try w.print("{s}l %a{d}", .{ if (i > 0) ", " else "", i });
        }
        try w.writeAll(") {\n@entry\n");
        for (def.param_regs, 0..) |preg, i| {
            try w.print("    %r{d} =l copy %a{d}\n", .{ preg, i });
        }
        try emitBody(w, &def.fn_mir);
        try w.writeAll("}\n");
    }

    try w.writeAll("function l $heaven_main() {\n");
    try emitBody(w, root);
    try w.writeAll("}\n");

    try w.writeAll("export function $main() {\n");
    try w.writeAll("@start\n");
    try w.writeAll("    %r =l call $heaven_main()\n");
    try w.writeAll("    %r2 =l call $printf(l $fmt, l %r)\n");
    try w.writeAll("    ret\n");
    try w.writeAll("}\n");
    try w.writeAll("data $fmt = { b \"%ld\\n\", b 0 }\n");
    return buf.toOwnedSlice(allocator);
}

/// Verifie que tous les call_user referencent une fonction presente
/// dans root.fn_defs. Couvre root et chaque fn_def (contrat §6 :
/// les corps de fn_def sont des lambdas compilees sans call_user,
/// mais on verifie par prudence).
fn checkCallUsers(root: *const MirFunction) !void {
    const defs = &root.fn_defs;
    try checkBlocks(root, defs);
    var it = defs.valueIterator();
    while (it.next()) |def| {
        try checkBlocks(&def.fn_mir, defs);
    }
}

fn checkBlocks(f: *const MirFunction, defs: *const std.AutoHashMap(u32, FnDef)) !void {
    for (f.blocks.items) |*blk| {
        for (blk.instrs.items) |inst| {
            switch (inst) {
                .call_user => |c| {
                    if (!defs.contains(c.name)) return error.UnsupportedCall;
                },
                else => {},
            }
        }
    }
}

fn emitBody(w: anytype, f: *const MirFunction) !void {
    if (f.blocks.items.len == 0) {
        try w.writeAll("    ret 0\n");
        return;
    }
    var tmp: Reg = f.next_value; // temps au-delà des regs réels
    for (f.blocks.items, 0..) |*blk, i| {
        try w.print("@b{d}\n", .{i});
        // Phis d'abord (ils vivent en tête du bloc, contrat §4)
        for (blk.instrs.items) |inst| {
            switch (inst) {
                .phi => |p| {
                    try w.print("    %r{d} =l phi ", .{p.dest});
                    for (p.incoming, 0..) |in, j| {
                        try w.print("{s}@b{d} %r{d}", .{ if (j > 0) ", " else "", in.block, in.value });
                    }
                    try w.writeAll("\n");
                },
                else => {},
            }
        }
        for (blk.instrs.items) |inst| {
            switch (inst) {
                .phi => {},
                else => try emitInstr(w, inst, &tmp),
            }
        }
        try emitTerm(w, blk);
    }
}

fn emitInstr(w: anytype, inst: Instr, tmp: *Reg) !void {
    switch (inst) {
        .const_int => |c| try w.print("    %r{d} =l copy {d}\n", .{ c.dest, c.value }),
        .add => |a| try w.print("    %r{d} =l add %r{d}, %r{d}\n", .{ a.dest, a.lhs, a.rhs }),
        .sub => |a| try w.print("    %r{d} =l sub %r{d}, %r{d}\n", .{ a.dest, a.lhs, a.rhs }),
        .mul => |a| try w.print("    %r{d} =l mul %r{d}, %r{d}\n", .{ a.dest, a.lhs, a.rhs }),
        .div => |a| try w.print("    %r{d} =l div %r{d}, %r{d}\n", .{ a.dest, a.lhs, a.rhs }),
        .cmp_lt => |a| {
            try w.print("    %t{d} =w csltw %r{d}, %r{d}\n", .{ tmp.*, a.lhs, a.rhs });
            try w.print("    %r{d} =l extsw %t{d}\n", .{ a.dest, tmp.* });
            tmp.* += 1;
        },
        .cmp_eq => |a| {
            try w.print("    %t{d} =w ceqw %r{d}, %r{d}\n", .{ tmp.*, a.lhs, a.rhs });
            try w.print("    %r{d} =l extsw %t{d}\n", .{ a.dest, tmp.* });
            tmp.* += 1;
        },
        .load => |l| try w.print("    %r{d} =l loadl $g{d}\n", .{ l.dest, l.sym }),
        .store => |s| try w.print("    storel %r{d}, $g{d}\n", .{ s.src, s.sym }),
        .call_user => |c| {
            // NB : vérification fn_defs dans emitQbe (vue globale) ;
            // ici émission seule. Cf. checkCallUsers.
            try w.print("    %r{d} =l call $f{d}(", .{ c.dest, c.name });
            for (c.args, 0..) |arg, i| {
                try w.print("{s}l %r{d}", .{ if (i > 0) ", " else "", arg });
            }
            try w.writeAll(")\n");
        },
        .phi, .jump, .branch, .ret => unreachable,
    }
}

fn emitTerm(w: anytype, blk: *const BasicBlock) !void {
    switch (blk.terminator) {
        .jump => |t| try w.print("    jmp @b{d}\n", .{t}),
        .branch => |b| try w.print("    jnz %r{d}, @b{d}, @b{d}\n", .{ b.cond, b.then_block, b.else_block }),
        .ret => |rv| try w.print("    ret %r{d}\n", .{rv}),
        .fallthrough => try w.writeAll("    ret 0\n"),
    }
}

fn collectGlobals(set: *std.AutoHashMap(u32, void), f: *const MirFunction) !void {
    for (f.blocks.items) |*blk| {
        for (blk.instrs.items) |inst| {
            switch (inst) {
                .load => |l| try set.put(l.sym, {}),
                .store => |s| try set.put(s.sym, {}),
                else => {},
            }
        }
    }
}
