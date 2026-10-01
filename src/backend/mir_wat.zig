//! MIR → WAT : émetteur texte (jalon M2a — docs/BACKENDS.md).
//! Contrat : docs/MIR_CONTRACT.md. Lecture seule de MirFunction.
//! call_user hors fn_defs → error.UnsupportedCall (rejet explicite,
//! jamais de repli silencieux sur l'interprète).

const std = @import("std");
const mir = @import("mir");

const MirFunction = mir.MirFunction;
const FnDef = mir.FnDef;
const Instr = mir.Instr;
const BlockId = mir.BlockId;
const Reg = mir.Reg;
const BasicBlock = mir.BasicBlock;
const FnDefs = std.AutoHashMap(u32, FnDef);

/// Émet le module WAT complet : globals (union des load/store),
/// une fonction WASM par fn_def, et $main exporté → i64.
pub fn emitWat(allocator: std.mem.Allocator, root: *const MirFunction) ![]u8 {
    return emitWatLoop(allocator, root, 1);
}

/// Variante avec boucle dans $main. Genere une fonction WASM interne
/// $heaven_main (corps du root) et un $main exporte qui l'itere
/// loop_count fois. Utile pour amortir le bootstrap wasmtime (~5 ms
/// par spawn) sur les mesures de perf et d'energie.
pub fn emitWatLoop(
    allocator: std.mem.Allocator,
    root: *const MirFunction,
    loop_count: u32,
) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    const w = buf.writer(allocator);
    try w.writeAll("(module\n");

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
        try w.print("(global $g{d} (mut i64) (i64.const 0))\n", .{g.*});
    }

    // Snapshot des noms (itération stable sur la HashMap).
    // NB : ordre d'émission non déterministe — les golden tests ne
    // dépendent que de la présence de fragments, pas de l'ordre.
    var fn_names: std.ArrayList(u32) = .empty;
    defer fn_names.deinit(allocator);
    var kit = root.fn_defs.keyIterator();
    while (kit.next()) |k| try fn_names.append(allocator, k.*);

    for (fn_names.items) |sym| {
        const def = root.fn_defs.get(sym).?;
        try w.print("(func $f{d} ", .{sym});
        for (def.param_regs, 0..) |_, i| {
            try w.print("(param $p{d} i64) ", .{i});
        }
        try w.writeAll("(result i64)\n");
        try emitBody(w, &def.fn_mir, &def, &root.fn_defs, sym);
        try w.writeAll(")\n");
    }

    if (loop_count <= 1) {
        // Wrapper simple : $main est le corps du root, inchange.
        try w.writeAll("(func $main (export \"main\") (result i64)\n");
        try emitBody(w, root, null, &root.fn_defs, null);
        try w.writeAll(")\n)\n");
    } else {
        // $heaven_main : le corps du root.
        try w.writeAll("(func $heaven_main (result i64)\n");
        try emitBody(w, root, null, &root.fn_defs, null);
        try w.writeAll(")\n");
        // $main : boucle loop_count fois sur $heaven_main.
        try w.writeAll("(func $main (export \"main\") (result i64)\n");
        try w.writeAll("(local $i i64)\n");
        try w.writeAll("(local $r i64)\n");
        try w.writeAll("(local.set $i (i64.const 0))\n");
        try w.writeAll("(local.set $r (i64.const 0))\n");
        try w.writeAll("(block $done\n");
        try w.writeAll("(loop $iter\n");
        try w.print("(br_if $done (i64.ge_s (local.get $i) (i64.const {d})))\n", .{loop_count});
        try w.writeAll("(local.set $r (call $heaven_main))\n");
        try w.writeAll("(local.set $i (i64.add (local.get $i) (i64.const 1)))\n");
        try w.writeAll("(br $iter)\n");
        try w.writeAll(")\n)\n");
        try w.writeAll("(local.get $r)\n");
        try w.writeAll(")\n)\n");
    }
    return buf.toOwnedSlice(allocator);
}

/// Corps d'une fonction : locals (1 par reg + $cur), prologue
/// params→regs, dispatch trampoline — (loop $dispatch) + chaîne de
/// (if $cur==k). Correct pour tout CFG ; O(nb blocs) par
/// branchement. Le relooping structuré est un chantier M3+.
fn emitBody(w: anytype, f: *const MirFunction, def: ?*const FnDef, fdefs: *const FnDefs, cur_sym: ?u32) !void {
    if (f.blocks.items.len == 0) {
        try w.writeAll("(i64.const 0)\n");
        return;
    }
    var r: u32 = 0;
    while (r < f.next_value) : (r += 1) {
        try w.print("(local $r{d} i64)\n", .{r});
    }
    // 8 temporaires TCO
    var t: u32 = 0;
    while (t < 8) : (t += 1) {
        try w.print("(local $r{d} i64)\n", .{ f.next_value + t });
    }
    try w.writeAll("(local $cur i32)\n");

    if (def) |d| {
        for (d.param_regs, 0..) |preg, i| {
            try w.print("(local.set $r{d} (local.get $p{d}))\n", .{ preg, i });
        }
    }

    // Pre-pass TCO : identifier les blocs self-tail-call.
    var tco = try f.allocator.alloc(bool, f.blocks.items.len);
    defer f.allocator.free(tco);
    @memset(tco, false);
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
                .jump => |jt| {
                    const tg = &f.blocks.items[jt];
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
        }
    }

    try w.writeAll("(local.set $cur (i32.const 0))\n");
    try w.writeAll("(loop $dispatch\n");
    for (f.blocks.items, 0..) |*blk, i| {
        const bid: BlockId = @intCast(i);
        try w.print("(if (i32.eq (local.get $cur) (i32.const {d}))\n", .{bid});
        try w.writeAll("  (then\n");
        if (tco[i]) {
            const c = blk.instrs.items[blk.instrs.items.len - 1].call_user;
            for (blk.instrs.items[0 .. blk.instrs.items.len - 1]) |inst| {
                switch (inst) {
                    .phi => {},
                    else => try emitInstr(w, inst, fdefs),
                }
            }
            // Temps : $r{next_value}..$r{next_value+7}
            const base: Reg = f.next_value;
            for (c.args, 0..) |arg, k| {
                try w.print("  (local.set $r{d} (local.get $r{d}))\n", .{ base + k, arg });
            }
            if (def) |d| {
                for (d.param_regs, 0..) |preg, k| {
                    if (k < c.args.len) {
                        try w.print("  (local.set $r{d} (local.get $r{d}))\n", .{ preg, base + k });
                    }
                }
            }
            try w.writeAll("  (local.set $cur (i32.const 0))\n  br $dispatch\n");
            try w.writeAll("  ))\n");
            continue;
        }
        for (blk.instrs.items) |inst| {
            switch (inst) {
                .phi => {}, // émis par les prédécesseurs (contrat §4)
                .jump, .branch, .ret => return error.TerminatorInBody,
                else => try emitInstr(w, inst, fdefs),
            }
        }
        try emitTerminator(w, f, blk, bid);
        try w.writeAll("  ))\n");
    }
    try w.writeAll("br $dispatch\n)\n");
    try w.writeAll("(i64.const 0)\n");
}

fn emitInstr(w: anytype, inst: Instr, fdefs: *const FnDefs) !void {
    switch (inst) {
        .const_int => |c| try w.print("(local.set $r{d} (i64.const {d}))\n", .{ c.dest, c.value }),
        .add => |a| try w.print("(local.set $r{d} (i64.add (local.get $r{d}) (local.get $r{d})))\n", .{ a.dest, a.lhs, a.rhs }),
        .sub => |a| try w.print("(local.set $r{d} (i64.sub (local.get $r{d}) (local.get $r{d})))\n", .{ a.dest, a.lhs, a.rhs }),
        .mul => |a| try w.print("(local.set $r{d} (i64.mul (local.get $r{d}) (local.get $r{d})))\n", .{ a.dest, a.lhs, a.rhs }),
        .div => |a| try w.print("(local.set $r{d} (i64.div_s (local.get $r{d}) (local.get $r{d})))\n", .{ a.dest, a.lhs, a.rhs }),
        .cmp_lt => |a| try w.print("(local.set $r{d} (i64.extend_i32_s (i64.lt_s (local.get $r{d}) (local.get $r{d}))))\n", .{ a.dest, a.lhs, a.rhs }),
        .cmp_eq => |a| try w.print("(local.set $r{d} (i64.extend_i32_s (i64.eq (local.get $r{d}) (local.get $r{d}))))\n", .{ a.dest, a.lhs, a.rhs }),
        .load => |l| try w.print("(local.set $r{d} (global.get $g{d}))\n", .{ l.dest, l.sym }),
        .store => |s| try w.print("(global.set $g{d} (local.get $r{d}))\n", .{ s.sym, s.src }),
        .call_user => |c| {
            if (!fdefs.contains(c.name)) return error.UnsupportedCall;
            try w.print("(local.set $r{d} (call $f{d}", .{ c.dest, c.name });
            for (c.args) |arg| {
                try w.print(" (local.get $r{d})", .{arg});
            }
            try w.writeAll("))\n");
        },
        .phi, .jump, .branch, .ret => unreachable, // filtrés en amont
    }
}

/// Terminateur d'un bloc. Les phis du bloc cible sont abattus
/// en local.set dans le prédécesseur (contrat §4).
fn emitTerminator(w: anytype, f: *const MirFunction, blk: *const BasicBlock, pred: BlockId) !void {
    switch (blk.terminator) {
        .jump => |t| {
            try emitPhiStores(w, f, t, pred);
            try w.print("(local.set $cur (i32.const {d}))\nbr $dispatch\n", .{t});
        },
        .branch => |b| {
            try w.print("(if (i64.ne (local.get $r{d}) (i64.const 0))\n", .{b.cond});
            try w.writeAll("  (then\n");
            try emitPhiStores(w, f, b.then_block, pred);
            try w.print("  (local.set $cur (i32.const {d}))\n  br $dispatch\n", .{b.then_block});
            try w.writeAll("  )\n  (else\n");
            try emitPhiStores(w, f, b.else_block, pred);
            try w.print("  (local.set $cur (i32.const {d}))\n  br $dispatch\n", .{b.else_block});
            try w.writeAll("  )\n)\n");
        },
        .ret => |rv| try w.print("(return (local.get $r{d}))\n", .{rv}),
        .fallthrough => try w.writeAll("(return (i64.const 0))\n"),
    }
}

fn emitPhiStores(w: anytype, f: *const MirFunction, target: BlockId, pred: BlockId) !void {
    for (f.blocks.items[target].instrs.items) |inst| {
        switch (inst) {
            .phi => |p| {
                for (p.incoming) |in| {
                    if (in.block == pred) {
                        try w.print("(local.set $r{d} (local.get $r{d}))\n", .{ p.dest, in.value });
                    }
                }
            },
            else => {},
        }
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
