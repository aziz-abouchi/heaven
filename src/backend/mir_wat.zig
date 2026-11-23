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

/// Adresse minimale de depart du tas WAT (>= seuil pointeur du MIR, voir
/// emitWatLoop). Les donnees (chaines) sont placees a partir de cette adresse
/// et le tas demarre apres elles, aligne sur 8.
pub const heap_base: u32 = 4096;

/// Adresses des chaines litterales (index = root.str_pool) et debut du tas.
const StrLayout = struct { addrs: []u32, heap_start: u32 };

fn layoutStrings(allocator: std.mem.Allocator, root: *const MirFunction) !StrLayout {
    const addrs = try allocator.alloc(u32, root.str_pool.items.len);
    var at: u32 = heap_base;
    for (root.str_pool.items, 0..) |bytes, i| {
        addrs[i] = at;
        at += @as(u32, @intCast(bytes.len)) + 1; // NUL final
    }
    return .{ .addrs = addrs, .heap_start = (at + 7) & ~@as(u32, 7) };
}

/// Contexte d'emission partage par emitBody/emitInstr.
const Ctx = struct { str_addrs: []const u32, store: @FieldType(MirFunction, "store") };

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
    // Invariant MIR : un pointeur de tas est >= 4096 ; les constructeurs sans
    // argument sont des entiers immediats < 4096 (cf. `>= 4096` dans la
    // compilation des clauses ADT, mir.zig). Le tas WAT demarre donc a 4096,
    // pas a 8 : sinon un noeud ICons serait pris pour un constructeur nul.
    const lay = try layoutStrings(allocator, root);
    defer allocator.free(lay.addrs);
    const ctx = Ctx{ .str_addrs = lay.addrs, .store = root.store };
    const pages: u32 = @max(1, (lay.heap_start + 65535) / 65536);
    try w.print("(module\n(memory (export \"memory\") {d})\n(global $heap_ptr (mut i32) (i32.const {d}))\n", .{ pages, lay.heap_start });
    // Chaines litterales : segments de donnees (NUL final implicite : memoire a 0).
    for (root.str_pool.items, 0..) |bytes, i| {
        try w.print("(data (i32.const {d}) \"", .{lay.addrs[i]});
        for (bytes) |b| try w.print("\\{x:0>2}", .{b});
        try w.writeAll("\\00\")\n");
    }
    // strcmp libc : difference des premiers octets distincts (0 si egales).
    try w.writeAll(
        \\(func $__strcmp (param $a i64) (param $b i64) (result i64)
        \\  (local $pa i32) (local $pb i32) (local $ca i32) (local $cb i32)
        \\  (local.set $pa (i32.wrap_i64 (local.get $a)))
        \\  (local.set $pb (i32.wrap_i64 (local.get $b)))
        \\  (block $done (loop $l
        \\    (local.set $ca (i32.load8_u (local.get $pa)))
        \\    (local.set $cb (i32.load8_u (local.get $pb)))
        \\    (br_if $done (i32.ne (local.get $ca) (local.get $cb)))
        \\    (br_if $done (i32.eqz (local.get $ca)))
        \\    (local.set $pa (i32.add (local.get $pa) (i32.const 1)))
        \\    (local.set $pb (i32.add (local.get $pb) (i32.const 1)))
        \\    (br $l)))
        \\  (i64.extend_i32_s (i32.sub (local.get $ca) (local.get $cb))))
        \\
    );
    try w.writeAll(
        \\(func $__strlen (param $s i64) (result i64)
        \\  (local $p i32) (local $n i32)
        \\  (local.set $p (i32.wrap_i64 (local.get $s)))
        \\  (block $done (loop $l
        \\    (br_if $done (i32.eqz (i32.load8_u (i32.add (local.get $p) (local.get $n)))))
        \\    (local.set $n (i32.add (local.get $n) (i32.const 1)))
        \\    (br $l)))
        \\  (i64.extend_i32_u (local.get $n)))
        \\
        \\(func $__strcat (param $a i64) (param $b i64) (result i64)
        \\  (local $pa i32) (local $pb i32) (local $la i32) (local $lb i32)
        \\  (local $dst i32) (local $i i32) (local $need i32)
        \\  (local.set $pa (i32.wrap_i64 (local.get $a)))
        \\  (local.set $pb (i32.wrap_i64 (local.get $b)))
        \\  (block $da (loop $la_l
        \\    (br_if $da (i32.eqz (i32.load8_u (i32.add (local.get $pa) (local.get $la)))))
        \\    (local.set $la (i32.add (local.get $la) (i32.const 1)))
        \\    (br $la_l)))
        \\  (block $db (loop $lb_l
        \\    (br_if $db (i32.eqz (i32.load8_u (i32.add (local.get $pb) (local.get $lb)))))
        \\    (local.set $lb (i32.add (local.get $lb) (i32.const 1)))
        \\    (br $lb_l)))
        \\  (local.set $dst (global.get $heap_ptr))
        \\  (local.set $need (i32.add (i32.add (local.get $la) (local.get $lb)) (i32.const 1)))
        \\  (global.set $heap_ptr (i32.add (local.get $dst) (local.get $need)))
        \\  (if (i32.gt_u (global.get $heap_ptr) (i32.mul (memory.size) (i32.const 65536)))
        \\    (then
        \\      (if (i32.lt_s (memory.grow (i32.add (i32.shr_u (i32.sub (global.get $heap_ptr) (i32.mul (memory.size) (i32.const 65536))) (i32.const 16)) (i32.const 1))) (i32.const 0))
        \\        (then (unreachable)))))
        \\  (local.set $i (i32.const 0))
        \\  (block $ca_done (loop $ca_l
        \\    (br_if $ca_done (i32.ge_u (local.get $i) (local.get $la)))
        \\    (i32.store8 (i32.add (local.get $dst) (local.get $i)) (i32.load8_u (i32.add (local.get $pa) (local.get $i))))
        \\    (local.set $i (i32.add (local.get $i) (i32.const 1)))
        \\    (br $ca_l)))
        \\  (local.set $i (i32.const 0))
        \\  (block $cb_done (loop $cb_l
        \\    (br_if $cb_done (i32.ge_u (local.get $i) (local.get $lb)))
        \\    (i32.store8 (i32.add (i32.add (local.get $dst) (local.get $la)) (local.get $i)) (i32.load8_u (i32.add (local.get $pb) (local.get $i))))
        \\    (local.set $i (i32.add (local.get $i) (i32.const 1)))
        \\    (br $cb_l)))
        \\  (i32.store8 (i32.add (i32.add (local.get $dst) (local.get $la)) (local.get $lb)) (i32.const 0))
        \\  (i64.extend_i32_u (local.get $dst)))
        \\
    );

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
        try emitBody(w, &ctx, &def.fn_mir, &def, &root.fn_defs, sym);
        try w.writeAll(")\n");
    }

    if (loop_count <= 1) {
        // Wrapper simple : $main est le corps du root, inchange.
        try w.writeAll("(func $main (export \"main\") (result i64)\n");
        try emitBody(w, &ctx, root, null, &root.fn_defs, null);
        try w.writeAll(")\n)\n");
    } else {
        // $heaven_main : le corps du root.
        try w.writeAll("(func $heaven_main (result i64)\n");
        try emitBody(w, &ctx, root, null, &root.fn_defs, null);
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
fn emitBody(w: anytype, ctx: *const Ctx, f: *const MirFunction, def: ?*const FnDef, fdefs: *const FnDefs, cur_sym: ?u32) !void {
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
    if (cur_sym != null) {
        for (f.blocks.items, 0..) |*blk, i| {
            if (blk.instrs.items.len == 0) continue;
            const c = switch (blk.instrs.items[blk.instrs.items.len - 1]) {
                .call_user => |cc| cc,
                else => continue,
            };
            if (!fdefs.contains(c.name)) continue;
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
                    else => try emitInstr(w, ctx, inst, fdefs),
                }
            }
            // WASM tail-call natif : return_call $fN arg0 arg1 ...
            // Le moteur WASM (wasmtime, browser) reutilise la frame
            // courante. Marche pour self ET mutual recursion.
            try w.print("  (return_call $f{d}", .{c.name});
            for (c.args) |arg| {
                try w.print(" (local.get $r{d})", .{arg});
            }
            try w.writeAll(")\n");
            try w.writeAll("  ))\n");
            continue;
        }
        for (blk.instrs.items) |inst| {
            switch (inst) {
                .phi => {}, // émis par les prédécesseurs (contrat §4)
                .jump, .branch, .ret => return error.TerminatorInBody,
                else => try emitInstr(w, ctx, inst, fdefs),
            }
        }
        try emitTerminator(w, f, blk, bid);
        try w.writeAll("  ))\n");
    }
    try w.writeAll("br $dispatch\n)\n");
    try w.writeAll("(i64.const 0)\n");
}

fn emitInstr(w: anytype, ctx: *const Ctx, inst: Instr, fdefs: *const FnDefs) !void {
    switch (inst) {
        .const_int => |c| try w.print("(local.set $r{d} (i64.const {d}))\n", .{ c.dest, c.value }),
        .const_str => |c| try w.print("(local.set $r{d} (i64.const {d}))\n", .{ c.dest, ctx.str_addrs[c.sym] }),
        .add => |a| try w.print("(local.set $r{d} (i64.add (local.get $r{d}) (local.get $r{d})))\n", .{ a.dest, a.lhs, a.rhs }),
        .sub => |a| try w.print("(local.set $r{d} (i64.sub (local.get $r{d}) (local.get $r{d})))\n", .{ a.dest, a.lhs, a.rhs }),
        .mul => |a| try w.print("(local.set $r{d} (i64.mul (local.get $r{d}) (local.get $r{d})))\n", .{ a.dest, a.lhs, a.rhs }),
        .div => |a| try w.print("(local.set $r{d} (i64.div_s (local.get $r{d}) (local.get $r{d})))\n", .{ a.dest, a.lhs, a.rhs }),
        .rem => |a| try w.print("(local.set $r{d} (i64.rem_s (local.get $r{d}) (local.get $r{d})))\n", .{ a.dest, a.lhs, a.rhs }),
        .cmp_lt => |a| try w.print("(local.set $r{d} (i64.extend_i32_s (i64.lt_s (local.get $r{d}) (local.get $r{d}))))\n", .{ a.dest, a.lhs, a.rhs }),
        .cmp_eq => |a| try w.print("(local.set $r{d} (i64.extend_i32_s (i64.eq (local.get $r{d}) (local.get $r{d}))))\n", .{ a.dest, a.lhs, a.rhs }),
        .load => |l| try w.print("(local.set $r{d} (global.get $g{d}))\n", .{ l.dest, l.sym }),
        .store => |s| try w.print("(global.set $g{d} (local.get $r{d}))\n", .{ s.sym, s.src }),
        .call_user => |c| {
            if (!fdefs.contains(c.name)) return error.UnsupportedCall;
            {
                try w.print("(local.set $r{d} (call $f{d}", .{ c.dest, c.name });
                for (c.args) |arg| {
                    try w.print(" (local.get $r{d})", .{arg});
                }
                try w.writeAll("))\n");
            }
        },
        .extern_call => |c| {
            // strcmp est fourni en WAT ($__strcmp). Les autres externs
            // (libc, I/O) doivent passer par WASI : trap explicite en attendant.
            const st = ctx.store;
            const nm = if (st) |sx| sx.interner.resolve(c.name) else "";
            const bare = if (nm.len > 0 and nm[0] == '@') nm[1..] else nm;
            if (std.mem.eql(u8, bare, "strcmp") and c.args.len == 2) {
                try w.print("(local.set $r{d} (call $__strcmp (local.get $r{d}) (local.get $r{d})))\n", .{ c.dest, c.args[0], c.args[1] });
                return;
            }
            if ((std.mem.eql(u8, bare, "strlen") or std.mem.eql(u8, bare, "__strlen")) and c.args.len == 1) {
                try w.print("(local.set $r{d} (call $__strlen (local.get $r{d})))\n", .{ c.dest, c.args[0] });
                return;
            }
            if (std.mem.eql(u8, bare, "__strcat") and c.args.len == 2) {
                try w.print("(local.set $r{d} (call $__strcat (local.get $r{d}) (local.get $r{d})))\n", .{ c.dest, c.args[0], c.args[1] });
                return;
            }
            try w.writeAll("    unreachable\n");
        },
        .alloc => |a| {
            const aligned_sz: u32 = if (a.size == 0) 8 else ((a.size + 7) & ~@as(u32, 7));
            try w.print("(local.set $r{d} (i64.extend_i32_u (global.get $heap_ptr)))\n", .{a.dest});
            try w.print("(global.set $heap_ptr (i32.add (global.get $heap_ptr) (i32.const {d})))\n", .{aligned_sz});
            try w.writeAll("(if (i32.gt_u (global.get $heap_ptr) (i32.mul (memory.size) (i32.const 65536)))\n");
            try w.writeAll("  (then\n");
            try w.writeAll("    (if (i32.lt_s (memory.grow (i32.add (i32.shr_u (i32.sub (global.get $heap_ptr) (i32.mul (memory.size) (i32.const 65536))) (i32.const 16)) (i32.const 1))) (i32.const 0))\n");
            try w.writeAll("      (then (unreachable)))\n");
            try w.writeAll("  )\n");
            try w.writeAll(")\n");
        },
        .load_at => |l| {
            try w.print("(local.set $r{d} (i64.load (i32.add (i32.wrap_i64 (local.get $r{d})) (i32.const {d}))))\n", .{ l.dest, l.base, l.offset });
        },
        .store_at => |st| {
            try w.print("(i64.store (i32.add (i32.wrap_i64 (local.get $r{d})) (i32.const {d})) (local.get $r{d}))\n", .{ st.base, st.offset, st.src });
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
