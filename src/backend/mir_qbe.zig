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
    return emitQbeLoop(allocator, root, 1);
}

/// Variante avec boucle dans le wrapper $main. Genere un binaire qui
/// execute le corps `loop_count` fois avant de printf. Utile pour
/// amortir le cout de fork+exec quand on mesure l'energie ou la
/// temperature (qui bougent a l'echelle de la seconde, pas de la ms).
pub fn emitQbeLoop(
    allocator: std.mem.Allocator,
    root: *const MirFunction,
    loop_count: u32,
) ![]u8 {
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
        try w.writeAll(") {\n");



        try emitBody(w, &def.fn_mir, def.param_regs, sym);
        try w.writeAll("}\n");
    }

    try w.writeAll("function l $heaven_main() {\n");
    try emitBody(w, root, null, null);
    try w.writeAll("}\n");

    try w.writeAll("export function $main() {\n");
    try w.writeAll("@start\n");
    if (loop_count <= 1) {
        try w.writeAll("    %r =l call $heaven_main()\n");
        try w.writeAll("    %r2 =l call $printf(l $fmt, l %r)\n");
    } else {
        // Boucle loop_count fois sur $heaven_main, imprime le dernier
        // resultat. Amortit fork+exec pour la mesure d'energie.
        try w.writeAll("    %loop_i =l copy 0\n");
        try w.writeAll("    %loop_r =l copy 0\n");
        try w.writeAll("@loop\n");
        try w.print("    %loop_cond =w csltl %loop_i, {d}\n", .{loop_count});
        try w.writeAll("    jnz %loop_cond, @loop_body, @loop_done\n");
        try w.writeAll("@loop_body\n");
        try w.writeAll("    %loop_r =l call $heaven_main()\n");
        try w.writeAll("    %loop_i =l add %loop_i, 1\n");
        try w.writeAll("    jmp @loop\n");
        try w.writeAll("@loop_done\n");
        try w.writeAll("    %r2 =l call $printf(l $fmt, l %loop_r)\n");
    }
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

fn emitBody(w: anytype, f: *const MirFunction, param_regs: ?[]const Reg, cur_sym: ?u32) !void {
    if (f.blocks.items.len == 0) {
        try w.writeAll("    ret 0\n");
        return;
    }
    var tco = try f.allocator.alloc(bool, f.blocks.items.len);
    defer f.allocator.free(tco);
    @memset(tco, false);
    var any_tco = false;
    if (cur_sym) |sym| {
        for (f.blocks.items, 0..) |*blk, i| {
            if (blk.instrs.items.len == 0) continue;
            const c = switch (blk.instrs.items[blk.instrs.items.len - 1]) {
                .call_user => |cc| cc,
                else => continue,
            };
            if (c.name != sym) continue;
            switch (blk.terminator) {
                .ret => |rv| { if (rv != c.dest) continue; },
                .jump => |t| {
                    const tg = &f.blocks.items[t];
                    var only_phi = true;
                    for (tg.instrs.items) |ins| {
                        if (ins != .phi) { only_phi = false; break; }
                    }
                    if (!only_phi) continue;
                    if (tg.terminator != .ret) continue;
                },
                else => continue,
            }
            tco[i] = true;
            any_tco = true;
        }
    }
    if (param_regs) |pr| {
        try w.writeAll("@entry\n");
        if (any_tco) {
            try w.writeAll("    jmp @b0\n");
        } else {
            for (pr, 0..) |preg, i| {
                try w.print("    %r{d} =l copy %a{d}\n", .{ preg, i });
            }
        }
    }
    var tmp: Reg = f.next_value;
    for (f.blocks.items, 0..) |*blk, i| {
        try w.print("@b{d}\n", .{i});
        if (i == 0 and any_tco) {
            if (param_regs) |pr| {
                for (pr, 0..) |preg, k| {
                    try w.print("    %r{d} =l phi @entry %a{d}", .{ preg, k });
                    for (tco, 0..) |b, j| {
                        if (b) try w.print(", @b{d} %t{d}_{d}", .{ j, j, k });
                    }
                    try w.writeAll("\n");
                }
            }
        }
        for (blk.instrs.items) |inst| {
            switch (inst) {
                .phi => |p| {
                    try w.print("    %r{d} =l phi", .{p.dest});
                    var first = true;
                    for (p.incoming) |in| {
                        if (tco[in.block]) continue;
                        if (!first) try w.writeAll(",");
                        try w.print(" @b{d} %r{d}", .{ in.block, in.value });
                        first = false;
                    }
                    if (first) try w.writeAll(" @entry 0");
                    try w.writeAll("\n");
                },
                else => {},
            }
        }
        if (tco[i]) {
            const c = blk.instrs.items[blk.instrs.items.len - 1].call_user;
            for (blk.instrs.items[0 .. blk.instrs.items.len - 1]) |inst| {
                switch (inst) {
                    .phi => {},
                    else => try emitInstr(w, inst, &tmp),
                }
            }
            for (c.args, 0..) |arg, k| {
                try w.print("    %t{d}_{d} =l copy %r{d}\n", .{ i, k, arg });
            }
            try w.writeAll("    jmp @b0\n");
            continue;
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
