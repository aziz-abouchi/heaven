const std = @import("std");
const expr_mod = @import("expr");
const engine_mod = @import("engine_expr");
const mir_mod = @import("../mir.zig");

const Sym = expr_mod.Sym;
const Store = expr_mod.Store;
const Id = mir_mod.Id;
const Reg = mir_mod.Reg;
const BlockId = mir_mod.BlockId;
const MirError = mir_mod.MirError;
const PhiEntry = mir_mod.PhiEntry;
const Instr = mir_mod.Instr;
const BasicBlock = mir_mod.BasicBlock;
const FnDef = mir_mod.FnDef;
const MirFunction = mir_mod.MirFunction;
const isBuiltinHeapCtor = mir_mod.isBuiltinHeapCtor;

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
        if (fn_def_user.num_clauses == 0) continue;
        if (fn_def_user.num_clauses > 1) {
            // Soundness : aucune clause multi-clause gardee ne doit
            // etre precompilee tant que MIR ne combine pas garde et motifs.
            var has_guard = false;
            for (0..fn_def_user.num_clauses) |ci| {
                if (fn_def_user.clauses[ci].guard != null) {
                    has_guard = true;
                    break;
                }
            }
            if (has_guard) continue;

            if (!self.multiClauseEligible(&fn_def_user)) continue;
            try eligible.append(self.allocator, name_str);
            continue;
        }

        const clause = fn_def_user.clauses[0];

        // Soundness : MIR ne compile pas les gardes. Compiler une
        // clause gardée sans appliquer sa garde produit une réponse
        // fausse à l'exécution. Exclure tant que MIR ne sait pas les
        // traiter ; l'interpréteur prend le relais.
        if (clause.guard != null) continue;

        var all_syms = true;
        for (0..clause.num_patterns) |i| {
            const pat = store.get(clause.patterns[i]);
            if (pat.tag != .sym) {
                all_syms = false;
                break;
            }
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
            const param_sym = if (fn_def_user.num_clauses > 1)
                try MirFunction.multiParamSym(store, i)
            else
                pat_node.payload;
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

        // Le corps est en forme frontend (tags legacy `.call`,
        // `.binary`, etc.). MIR attend du Core (`.apply`, `.lit`,
        // `.sym`). Note : `store.binop(op, a, b)` n'est PAS un
        // tag — c'est un helper qui construit
        // `apply(sym(op), [a, b])`. La conversion legacy → Core
        // se fait en amont via `lower`/`lowerRec` (expr.zig) et
        // le même pipeline que `parseLastExpr` (qbe_cmd/wasm_cmd).
        const lowered_body = (if (fn_def_user.num_clauses > 1)
            self.desugarClauses(store, &fn_def_user)
        else
            store.lowerRec(clause.body)) catch |err| {
            std.debug.print(
                "[MIR precompile] lowerRec failed: {s}: {s}\\n",
                .{ name_str, @errorName(err) },
            );
            if (self.fn_defs.fetchRemove(name_sym)) |kv| {
                var v = kv.value;
                v.fn_mir.deinit();
                self.allocator.free(v.param_names);
                self.allocator.free(v.param_regs);
            }
            continue;
        };
        var blk_zero: BlockId = 0;
        const result = def.fn_mir.compileExpr(store, lowered_body, &blk_zero, locals) catch |err| {
            std.debug.print(
                "[MIR precompile] compileExpr failed: {s}: {s}\\n",
                .{ name_str, @errorName(err) },
            );
            // 2026-10-30 : skip propre (fetchRemove) au lieu de stub
            // (le stub cassait les phis MIR).
            if (self.fn_defs.fetchRemove(name_sym)) |kv| {
                var v = kv.value;
                v.fn_mir.deinit();
                self.allocator.free(v.param_names);
                self.allocator.free(v.param_regs);
            }
            continue;
        };
        // `ret` va sur le bloc ACTIF (blk_zero) : apres un `if` le corps se
        // termine dans le bloc de fusion, pas dans le bloc 0 (celui-ci finit
        // par cond_br). Poser le ret sur le bloc 0 laissait la fonction sans
        // retour : toute fonction dont le corps est un `if` renvoyait 0.
        if (def.fn_mir.blocks.items[blk_zero].terminator == .fallthrough) {
            def.fn_mir.blocks.items[blk_zero].terminator = .{ .ret = result };
        }
    }

    // Retrait transitif des fonctions orphelines : une fonction dont le
    // corps appelle (call_user) un nom absent de fn_defs ne peut pas etre
    // emise (checkCallUsers la rejette a juste titre, sans stub). Sans ce
    // retrait, UNE fonction non compilable du prelude (ex. sup_restart,
    // multi-clauses a constructeurs) fait echouer TOUT programme.
    // Le root, lui, reste verifie plus tard : un appel reel vers une
    // fonction retiree donne toujours UnsupportedCall (rejet explicite).
    try self.pruneOrphanCallers();

    // G.34 fix : migrer str_pool des fn_defs vers root.
    // Pour chaque const_str dans chaque fn_def, on ajoute la
    // string à root.str_pool et on remap l'index. Ainsi mir_qbe
    // peut émettre les data $str_N sans préfixe par fn, et G.31
    // skip ne se déclenche plus (str_pool fn_def vidé).
    var mig_it = self.fn_defs.valueIterator();
    while (mig_it.next()) |def| {
        if (def.fn_mir.str_pool.items.len == 0) continue;
        for (def.fn_mir.blocks.items) |*blk| {
            for (blk.instrs.items) |*inst| {
                switch (inst.*) {
                    .const_str => {
                        const cs_ptr = &inst.*.const_str;
                        const str = def.fn_mir.str_pool.items[cs_ptr.sym];
                        const new_idx: u32 = @intCast(self.str_pool.items.len);
                        try self.str_pool.append(self.allocator, str);
                        cs_ptr.sym = new_idx;
                    },
                    else => {},
                }
            }
        }
        def.fn_mir.str_pool.clearRetainingCapacity();
    }
}

fn emitExternCall(
    mir_fn: *MirFunction,
    store_ref: *Store,
    sym_name: []const u8,
    call_args: []const Id,
    target_block: BlockId,
) !Reg {
    const sym = try store_ref.interner.intern(sym_name);
    const arg_slice = try mir_fn.allocator.alloc(Id, call_args.len);
    errdefer mir_fn.allocator.free(arg_slice);
    @memcpy(arg_slice, call_args);
    const dest = mir_fn.newReg();
    try mir_fn.blocks.items[target_block].instrs.append(mir_fn.allocator, .{
        .extern_call = .{ .dest = dest, .name = sym, .args = arg_slice },
    });
    return dest;
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

pub fn compileLambda(self: *MirFunction, store: *Store, lambda_id: Reg) !FnDef {
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
    var cur_block = try fn_mir.newBlock();
    const result_reg = try fn_mir.compileExpr(store, current_id, &cur_block, param_map);
    if (fn_mir.blocks.items[cur_block].terminator == .fallthrough) {
        fn_mir.blocks.items[cur_block].terminator = .{ .ret = result_reg };
    }
    // Créer la définition
    return FnDef{
        .fn_mir = fn_mir,
        .param_names = try params.toOwnedSlice(self.allocator),
        .param_regs = try param_regs.toOwnedSlice(self.allocator),
    };
}

pub fn compileExpr(self: *MirFunction, store: *Store, id: Id, target_block: *BlockId, locals: std.AutoHashMap(u32, Reg)) MirError!Reg {
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
            // Ctors 0-arity booléens : résoudre en const_int.
            // (fix 2026-11-09 — true/false étaient chargés comme
            // variables non initialisées → 0)
            const name = store.interner.resolve(sym);
            // true/false AVANT le lookup général : ils ont un ctor_tag
            // de bootstrap (0/1 inversés) qu'il ne faut pas utiliser.
            if (std.mem.eql(u8, name, "true") or std.mem.eql(u8, name, "True")) {
                const dest = self.newReg();
                try self.blocks.items[target_block.*].instrs.append(self.allocator, .{ .const_int = .{ .dest = dest, .value = 1 } });
                return dest;
            }
            if (std.mem.eql(u8, name, "false") or std.mem.eql(u8, name, "False")) {
                const dest = self.newReg();
                try self.blocks.items[target_block.*].instrs.append(self.allocator, .{ .const_int = .{ .dest = dest, .value = 0 } });
                return dest;
            }
            // Ctors 0-arity user (Red, Green, ...) : tag général = position
            // dans le `data` d'origine (2026-11-09).
            if (self.engine) |eng| {
                if (eng.fns.get(name)) |fd| {
                    if (fd.ctor_arity) |arity| {
                        if (arity == 0) {
                            if (fd.ctor_tag) |tag| {
                                const dest = self.newReg();
                                try self.blocks.items[target_block.*].instrs.append(self.allocator, .{ .const_int = .{ .dest = dest, .value = @intCast(tag) } });
                                return dest;
                            }
                        }
                    }
                }
            }
            if (locals.get(sym)) |reg| {
                return reg;
            }
            const dest = self.newReg();
            try self.blocks.items[target_block.*].instrs.append(self.allocator, .{ .load = .{ .dest = dest, .sym = sym } });
            return dest;
        },
        .lit => {
            const l = store.lits.items[node.aux];
            switch (l) {
                .int => |v| {
                    const dest = self.newReg();
                    try self.blocks.items[target_block.*].instrs.append(self.allocator, .{ .const_int = .{ .dest = dest, .value = v } });
                    return dest;
                },
                .boolean => |b| {
                    const dest = self.newReg();
                    try self.blocks.items[target_block.*].instrs.append(self.allocator, .{ .const_int = .{ .dest = dest, .value = if (b) 1 else 0 } });
                    return dest;
                },
                .str => |sym| {
                    // 2026-10-30 : strings litterales via const_str.
                    // Sym = index interner, bytes valides tant que
                    // l'interner vit (emitQbe s'exécute avant deinit).
                    const bytes = store.interner.resolve(sym);
                    const pool_idx: u32 = @intCast(self.str_pool.items.len);
                    try self.str_pool.append(self.allocator, bytes);
                    const dest = self.newReg();
                    try self.blocks.items[target_block.*].instrs.append(self.allocator, .{ .const_str = .{ .dest = dest, .sym = pool_idx } });
                    return dest;
                },
                else => return error.UnsupportedLiteral,
            }
        },
        .apply => {
            if (self.engine) |engine| {
                var curried_args: [8]Id = undefined;
                if (MirFunction.unwindCurriedApply(store, id, &curried_args)) |unwound| {
                    const cname = store.interner.resolve(unwound.head_sym);
                    if (if (isBuiltinHeapCtor(cname)) null else engine.fns.get(cname)) |fd| {
                        if (fd.ctor_arity) |arity| {
                            if (arity > 0 and unwound.len == arity) {
                                const tag = fd.ctor_tag orelse return error.UnsupportedExpr;
                                const dest = self.newReg();
                                const total_bytes: u32 = @as(u32, arity + 1) * 8;
                                try self.blocks.items[target_block.*].instrs.append(self.allocator, .{
                                    .alloc = .{ .dest = dest, .size = total_bytes },
                                });
                                const tag_reg = self.newReg();
                                try self.blocks.items[target_block.*].instrs.append(self.allocator, .{
                                    .const_int = .{ .dest = tag_reg, .value = @intCast(tag) },
                                });
                                try self.blocks.items[target_block.*].instrs.append(self.allocator, .{
                                    .store_at = .{ .base = dest, .offset = 0, .src = tag_reg },
                                });
                                for (0..unwound.len) |k| {
                                    const arg_reg = try self.compileExpr(store, curried_args[k], target_block, locals);
                                    try self.blocks.items[target_block.*].instrs.append(self.allocator, .{
                                        .store_at = .{ .base = dest, .offset = @intCast((k + 1) * 8), .src = arg_reg },
                                    });
                                }
                                return dest;
                            }
                        }
                    }
                }
            }
            const apply_func_node = store.get(node.payload);
            if (apply_func_node.tag == .lambda) {
                const raw_apply = node.span_a.slice(store.pool.items);
                const arg_slice = if (raw_apply.len > 0 and raw_apply[0] == node.payload)
                    raw_apply[1..]
                else
                    raw_apply;
                const lambda_bodies = apply_func_node.span_a.slice(store.pool.items);
                if (arg_slice.len == 1 and lambda_bodies.len >= 1) {
                    const val_reg = try self.compileExpr(store, arg_slice[0], target_block, locals);
                    var new_locals = try locals.clone();
                    defer new_locals.deinit();
                    try new_locals.put(apply_func_node.payload, val_reg);
                    return try self.compileExpr(store, lambda_bodies[0], target_block, new_locals);
                }
            }
            var unwound_buf: [8]Id = undefined;
            var op_name: []const u8 = undefined;
            var op_sym: Sym = 0;
            var args: []const Id = undefined;
            const func_node = store.get(node.payload);
            if (func_node.tag == .sym) {
                op_sym = func_node.payload;
                op_name = store.interner.resolve(op_sym);
                const raw_args = node.span_a.slice(store.pool.items);
                args = if (raw_args.len > 0 and raw_args[0] == node.payload)
                    raw_args[1..]
                else
                    raw_args;
            } else if (MirFunction.unwindCurriedApply(store, id, &unwound_buf)) |uw| {
                op_sym = uw.head_sym;
                op_name = store.interner.resolve(op_sym);
                args = unwound_buf[0..uw.len];
            } else {
                return error.UnsupportedExpr;
            }

            if (std.mem.eql(u8, op_name, "while") and args.len == 2) {
                return try self.compileWhile(store, args[0], args[1], target_block.*, locals);
            }
            if (std.mem.eql(u8, op_name, "if") and args.len == 3) {
                return try self.compileIf(store, args[0], args[1], args[2], target_block.*, target_block, locals);
            }
            if (std.mem.eql(u8, op_name, "break") and args.len == 1) {
                return try self.compileBreak(store, args[0], target_block.*, locals);
            }
            if ((std.mem.eql(u8, op_name, "^") or std.mem.eql(u8, op_name, "pow")) and args.len == 2) {
                return try self.compilePow(store, args[0], args[1], target_block.*, locals);
            }

            // 2026-10-30 : builtins heap (pair, fst, snd, cons, head, tail)
            if (std.mem.eql(u8, op_name, "pair") and args.len == 2) {
                const a = try self.compileExpr(store, args[0], target_block, locals);
                const b = try self.compileExpr(store, args[1], target_block, locals);
                const dest = self.newReg();
                const instrs = &self.blocks.items[target_block.*].instrs;
                try instrs.append(self.allocator, .{ .alloc = .{ .dest = dest, .size = 16 } });
                try instrs.append(self.allocator, .{ .store_at = .{ .base = dest, .offset = 0, .src = a } });
                try instrs.append(self.allocator, .{ .store_at = .{ .base = dest, .offset = 8, .src = b } });
                return dest;
            }
            if (std.mem.eql(u8, op_name, "fst") and args.len == 1) {
                const p_in = try self.compileExpr(store, args[0], target_block, locals);
                const dest = self.newReg();
                try self.blocks.items[target_block.*].instrs.append(self.allocator, .{ .load_at = .{ .dest = dest, .base = p_in, .offset = 0 } });
                return dest;
            }
            if (std.mem.eql(u8, op_name, "snd") and args.len == 1) {
                const p_in = try self.compileExpr(store, args[0], target_block, locals);
                const dest = self.newReg();
                try self.blocks.items[target_block.*].instrs.append(self.allocator, .{ .load_at = .{ .dest = dest, .base = p_in, .offset = 8 } });
                return dest;
            }
            if (std.mem.eql(u8, op_name, "cons") and args.len == 2) {
                const a = try self.compileExpr(store, args[0], target_block, locals);
                const b = try self.compileExpr(store, args[1], target_block, locals);
                const dest = self.newReg();
                const instrs = &self.blocks.items[target_block.*].instrs;
                try instrs.append(self.allocator, .{ .alloc = .{ .dest = dest, .size = 16 } });
                try instrs.append(self.allocator, .{ .store_at = .{ .base = dest, .offset = 0, .src = a } });
                try instrs.append(self.allocator, .{ .store_at = .{ .base = dest, .offset = 8, .src = b } });
                return dest;
            }
            if (std.mem.eql(u8, op_name, "head") and args.len == 1) {
                const p_in = try self.compileExpr(store, args[0], target_block, locals);
                const dest = self.newReg();
                try self.blocks.items[target_block.*].instrs.append(self.allocator, .{ .load_at = .{ .dest = dest, .base = p_in, .offset = 0 } });
                return dest;
            }
            if (std.mem.eql(u8, op_name, "tail") and args.len == 1) {
                const p_in = try self.compileExpr(store, args[0], target_block, locals);
                const dest = self.newReg();
                try self.blocks.items[target_block.*].instrs.append(self.allocator, .{ .load_at = .{ .dest = dest, .base = p_in, .offset = 8 } });
                return dest;
            }

            if (args.len == 2 and (std.mem.eql(u8, op_name, "==") or std.mem.eql(u8, op_name, "eq") or
                std.mem.eql(u8, op_name, "!=") or std.mem.eql(u8, op_name, "neq") or
                std.mem.eql(u8, op_name, "lt") or std.mem.eql(u8, op_name, "<") or
                std.mem.eql(u8, op_name, "gt") or std.mem.eql(u8, op_name, ">") or
                std.mem.eql(u8, op_name, "le") or std.mem.eql(u8, op_name, "<=") or
                std.mem.eql(u8, op_name, "ge") or std.mem.eql(u8, op_name, ">=") or
                std.mem.eql(u8, op_name, "add") or std.mem.eql(u8, op_name, "+") or
                std.mem.eql(u8, op_name, "sub") or std.mem.eql(u8, op_name, "-") or
                std.mem.eql(u8, op_name, "mul") or std.mem.eql(u8, op_name, "*") or
                std.mem.eql(u8, op_name, "div") or std.mem.eql(u8, op_name, "/") or
                std.mem.eql(u8, op_name, "rem") or std.mem.eql(u8, op_name, "%")))
            {
                const lhs = try self.compileExpr(store, args[0], target_block, locals);
                const rhs = try self.compileExpr(store, args[1], target_block, locals);
                const dest = self.newReg();
                const instrs = &self.blocks.items[target_block.*].instrs;
                if (std.mem.eql(u8, op_name, "==") or std.mem.eql(u8, op_name, "eq")) {
                    try instrs.append(self.allocator, .{ .cmp_eq = .{ .dest = dest, .lhs = lhs, .rhs = rhs } });
                } else if (std.mem.eql(u8, op_name, "!=") or std.mem.eql(u8, op_name, "neq")) {
                    const eq = self.newReg();
                    try instrs.append(self.allocator, .{ .cmp_eq = .{ .dest = eq, .lhs = lhs, .rhs = rhs } });
                    const one = self.newReg();
                    try instrs.append(self.allocator, .{ .const_int = .{ .dest = one, .value = 1 } });
                    try instrs.append(self.allocator, .{ .sub = .{ .dest = dest, .lhs = one, .rhs = eq } });
                } else if (std.mem.eql(u8, op_name, "lt") or std.mem.eql(u8, op_name, "<")) {
                    try instrs.append(self.allocator, .{ .cmp_lt = .{ .dest = dest, .lhs = lhs, .rhs = rhs } });
                } else if (std.mem.eql(u8, op_name, "gt") or std.mem.eql(u8, op_name, ">")) {
                    try instrs.append(self.allocator, .{ .cmp_lt = .{ .dest = dest, .lhs = rhs, .rhs = lhs } });
                } else if (std.mem.eql(u8, op_name, "le") or std.mem.eql(u8, op_name, "<=")) {
                    const lt = self.newReg();
                    try instrs.append(self.allocator, .{ .cmp_lt = .{ .dest = lt, .lhs = rhs, .rhs = lhs } });
                    const one = self.newReg();
                    try instrs.append(self.allocator, .{ .const_int = .{ .dest = one, .value = 1 } });
                    try instrs.append(self.allocator, .{ .sub = .{ .dest = dest, .lhs = one, .rhs = lt } });
                } else if (std.mem.eql(u8, op_name, "ge") or std.mem.eql(u8, op_name, ">=")) {
                    const lt = self.newReg();
                    try instrs.append(self.allocator, .{ .cmp_lt = .{ .dest = lt, .lhs = lhs, .rhs = rhs } });
                    const one = self.newReg();
                    try instrs.append(self.allocator, .{ .const_int = .{ .dest = one, .value = 1 } });
                    try instrs.append(self.allocator, .{ .sub = .{ .dest = dest, .lhs = one, .rhs = lt } });
                } else if (std.mem.eql(u8, op_name, "add") or std.mem.eql(u8, op_name, "+")) {
                    try instrs.append(self.allocator, .{ .add = .{ .dest = dest, .lhs = lhs, .rhs = rhs } });
                } else if (std.mem.eql(u8, op_name, "sub") or std.mem.eql(u8, op_name, "-")) {
                    try instrs.append(self.allocator, .{ .sub = .{ .dest = dest, .lhs = lhs, .rhs = rhs } });
                } else if (std.mem.eql(u8, op_name, "mul") or std.mem.eql(u8, op_name, "*")) {
                    try instrs.append(self.allocator, .{ .mul = .{ .dest = dest, .lhs = lhs, .rhs = rhs } });
                } else if (std.mem.eql(u8, op_name, "div") or std.mem.eql(u8, op_name, "/")) {
                    try instrs.append(self.allocator, .{ .div = .{ .dest = dest, .lhs = lhs, .rhs = rhs } });
                } else if (std.mem.eql(u8, op_name, "rem") or std.mem.eql(u8, op_name, "%")) {
                    try instrs.append(self.allocator, .{ .rem = .{ .dest = dest, .lhs = lhs, .rhs = rhs } });
                }
                return dest;
            }

            if (std.mem.eql(u8, op_name, "__mir_load_at") and args.len == 2) {
                const p_in = try self.compileExpr(store, args[0], target_block, locals);
                const off_node = store.get(args[1]);
                if (off_node.tag != .lit) return error.UnsupportedExpr;
                const off_val = switch (store.lits.items[off_node.aux]) {
                    .int => |v| v,
                    else => return error.UnsupportedExpr,
                };
                const dest = self.newReg();
                try self.blocks.items[target_block.*].instrs.append(self.allocator, .{
                    .load_at = .{ .dest = dest, .base = p_in, .offset = @intCast(off_val) },
                });
                return dest;
            }

            // Appel de fonction utilisateur ou constructeur ADT n-aire
            if (self.engine) |engine| {
                if (if (isBuiltinHeapCtor(op_name)) null else engine.fns.get(op_name)) |fd| {
                    if (fd.ctor_arity) |arity| {
                        if (arity > 0 and args.len == arity) {
                            const tag = fd.ctor_tag orelse return error.UnsupportedExpr;
                            const dest = self.newReg();
                            const total_bytes: u32 = @as(u32, arity + 1) * 8;
                            try self.blocks.items[target_block.*].instrs.append(self.allocator, .{
                                .alloc = .{ .dest = dest, .size = total_bytes },
                            });
                            const tag_reg = self.newReg();
                            try self.blocks.items[target_block.*].instrs.append(self.allocator, .{
                                .const_int = .{ .dest = tag_reg, .value = @intCast(tag) },
                            });
                            try self.blocks.items[target_block.*].instrs.append(self.allocator, .{
                                .store_at = .{ .base = dest, .offset = 0, .src = tag_reg },
                            });
                            for (args, 0..) |arg, k| {
                                const arg_reg = try self.compileExpr(store, arg, target_block, locals);
                                try self.blocks.items[target_block.*].instrs.append(self.allocator, .{
                                    .store_at = .{ .base = dest, .offset = @intCast((k + 1) * 8), .src = arg_reg },
                                });
                            }
                            return dest;
                        }
                    }
                }
                if (engine.fns.get(op_name) != null) {
                    var arg_regs = std.ArrayListUnmanaged(Id){};
                    defer arg_regs.deinit(self.allocator);
                    for (args) |arg| {
                        const arg_reg = try self.compileExpr(store, arg, target_block, locals);
                        try arg_regs.append(self.allocator, arg_reg);
                    }
                    const dest = self.newReg();
                    const name_sym = op_sym;
                    const arg_slice = try self.allocator.dupe(Id, arg_regs.items);
                    errdefer self.allocator.free(arg_slice);
                    try self.blocks.items[target_block.*].instrs.append(self.allocator, .{
                        .call_user = .{ .dest = dest, .name = name_sym, .args = arg_slice },
                    });
                    return dest;
                }
            }

            // G.32 : magic @argv — lit argv[N] (char*).
            // Charge le global heaven_argv, offset = N*8, load_at 0.
            if (std.mem.eql(u8, op_name, "@argv") and args.len == 1) {
                const store_ref = self.store orelse return error.UnsupportedExpr;
                if (self.argv_sym == null) {
                    self.argv_sym = try store_ref.interner.intern("heaven_argv");
                }
                const idx = try self.compileExpr(store, args[0], target_block, locals);
                const instrs = &self.blocks.items[target_block.*].instrs;
                const eight = self.newReg();
                try instrs.append(self.allocator, .{ .const_int = .{ .dest = eight, .value = 8 } });
                const off = self.newReg();
                try instrs.append(self.allocator, .{ .mul = .{ .dest = off, .lhs = idx, .rhs = eight } });
                const argv_ptr = self.newReg();
                try instrs.append(self.allocator, .{ .load = .{ .dest = argv_ptr, .sym = self.argv_sym.? } });
                const ptr = self.newReg();
                try instrs.append(self.allocator, .{ .add = .{ .dest = ptr, .lhs = argv_ptr, .rhs = off } });
                const dest = self.newReg();
                try instrs.append(self.allocator, .{ .load_at = .{ .dest = dest, .base = ptr, .offset = 0 } });
                return dest;
            }

            // Appel externe : convention de nommage `@nom`.
            // Résolu à l'édition de liens (libc, crt).
            if (op_name.len > 0 and op_name[0] == '@') {
                var arg_regs = std.ArrayListUnmanaged(Id){};
                defer arg_regs.deinit(self.allocator);
                for (args) |arg| {
                    const arg_reg = try self.compileExpr(store, arg, target_block, locals);
                    try arg_regs.append(self.allocator, arg_reg);
                }
                const dest = self.newReg();
                const name_sym = op_sym;
                const arg_slice = try self.allocator.dupe(Id, arg_regs.items);
                errdefer self.allocator.free(arg_slice);
                try self.blocks.items[target_block.*].instrs.append(self.allocator, .{
                    .extern_call = .{ .dest = dest, .name = name_sym, .args = arg_slice },
                });
                return dest;
            }

            if (std.mem.eql(u8, op_name, "string_length") and args.len == 1) {
                const store_ref = self.store orelse return error.UnsupportedExpr;
                const arg_reg = try self.compileExpr(store, args[0], target_block, locals);
                return emitExternCall(self, store_ref, "strlen", &.{arg_reg}, target_block.*);
            }
            // `(let nom val corps)` : magic de l'interpreteur (forme produite par
            // `f x = let r = v in corps` sans parentheses). Meme abaissement que
            // `((lambda nom corps) val)` : valeur, liaison locale, corps. `let _`
            // (trou) evalue la valeur pour son effet et ne lie rien.
            if (std.mem.eql(u8, op_name, "let") and args.len == 3) {
                const name_node = store.get(args[0]);
                if (name_node.tag == .sym or name_node.tag == .hole) {
                    const val_reg = try self.compileExpr(store, args[1], target_block, locals);
                    if (name_node.tag == .hole) {
                        return try self.compileExpr(store, args[2], target_block, locals);
                    }
                    var let_locals = try locals.clone();
                    defer let_locals.deinit();
                    try let_locals.put(name_node.payload, val_reg);
                    return try self.compileExpr(store, args[2], target_block, let_locals);
                }
            }
            // Memoire brute et chaines dynamiques (string_substring de la stdlib).
            // Les trois "unit" (poke_byte, raw_free) rendent 0 en natif.
            const raw_prims = [_]struct { name: []const u8, arity: usize, ext: []const u8 }{
                .{ .name = "raw_alloc", .arity = 1, .ext = "__raw_alloc" },
                .{ .name = "raw_free", .arity = 2, .ext = "__raw_free" },
                .{ .name = "poke_byte", .arity = 3, .ext = "__poke_byte" },
                .{ .name = "string_of_bytes", .arity = 2, .ext = "__str_of_bytes" },
            };
            for (raw_prims) |rp| {
                if (std.mem.eql(u8, op_name, rp.name) and args.len == rp.arity) {
                    const store_ref = self.store orelse return error.UnsupportedExpr;
                    var regs: [3]Id = undefined;
                    for (args, 0..) |a, k| regs[k] = try self.compileExpr(store, a, target_block, locals);
                    return emitExternCall(self, store_ref, rp.ext, regs[0..rp.arity], target_block.*);
                }
            }
            // string_ptr : une chaine est deja son adresse en natif -> identite.
            if (std.mem.eql(u8, op_name, "string_ptr") and args.len == 1) {
                return try self.compileExpr(store, args[0], target_block, locals);
            }
            // peek_byte p i : octet non signe a p+i, sans test de borne
            // (meme semantique que l'interpreteur).
            if (std.mem.eql(u8, op_name, "peek_byte") and args.len == 2) {
                const store_ref = self.store orelse return error.UnsupportedExpr;
                const p_reg = try self.compileExpr(store, args[0], target_block, locals);
                const i_reg = try self.compileExpr(store, args[1], target_block, locals);
                return emitExternCall(self, store_ref, "__peek_byte", &.{ p_reg, i_reg }, target_block.*);
            }
            if (std.mem.eql(u8, op_name, "string_concat") and args.len == 2) {
                const store_ref = self.store orelse return error.UnsupportedExpr;
                const a_reg = try self.compileExpr(store, args[0], target_block, locals);
                const b_reg = try self.compileExpr(store, args[1], target_block, locals);
                return emitExternCall(self, store_ref, "__strcat", &.{ a_reg, b_reg }, target_block.*);
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
                else if (std.mem.eql(u8, op_name, "=") or std.mem.eql(u8, op_name, "=="))
                    .{ .cmp_eq = .{ .dest = dest, .lhs = lhs, .rhs = rhs } }
                else if (std.mem.eql(u8, op_name, "!=")) blk: {
                    const eq = self.newReg();
                    const instrs = &self.blocks.items[target_block.*].instrs;
                    try instrs.append(self.allocator, .{ .cmp_eq = .{ .dest = eq, .lhs = lhs, .rhs = rhs } });
                    const one = self.newReg();
                    try instrs.append(self.allocator, .{ .const_int = .{ .dest = one, .value = 1 } });
                    break :blk .{ .sub = .{ .dest = dest, .lhs = one, .rhs = eq } };
                }
                else if (std.mem.eql(u8, op_name, ">"))
                    .{ .cmp_lt = .{ .dest = dest, .lhs = rhs, .rhs = lhs } }
                else if (std.mem.eql(u8, op_name, "<=")) blk: {
                    // x <= y  ≡  not(y < x)  →  1 - cmp_lt(y,x)
                    const lt = self.newReg();
                    const instrs = &self.blocks.items[target_block.*].instrs;
                    try instrs.append(self.allocator, .{ .cmp_lt = .{ .dest = lt, .lhs = rhs, .rhs = lhs } });
                    const one = self.newReg();
                    try instrs.append(self.allocator, .{ .const_int = .{ .dest = one, .value = 1 } });
                    break :blk .{ .sub = .{ .dest = dest, .lhs = one, .rhs = lt } };
                }
                else if (std.mem.eql(u8, op_name, ">=")) blk: {
                    // x >= y  ≡  not(x < y)
                    const lt = self.newReg();
                    const instrs = &self.blocks.items[target_block.*].instrs;
                    try instrs.append(self.allocator, .{ .cmp_lt = .{ .dest = lt, .lhs = lhs, .rhs = rhs } });
                    const one = self.newReg();
                    try instrs.append(self.allocator, .{ .const_int = .{ .dest = one, .value = 1 } });
                    break :blk .{ .sub = .{ .dest = dest, .lhs = one, .rhs = lt } };
                }
                else
                    return error.UnsupportedOp;
                try self.blocks.items[target_block.*].instrs.append(self.allocator, op);
                return dest;
            }
            return error.UnsupportedExpr;
        },
        else => {
            return error.UnsupportedExpr;
        },
    }
}

pub fn compileIf(self: *MirFunction, store: *Store, cond_id: Reg, then_id: Reg, else_id: Reg, entry_block: BlockId, current_block: *BlockId, locals: std.AutoHashMap(u32, Reg)) MirError!Id {
    var b_entry = entry_block;
    const cond_val = try self.compileExpr(store, cond_id, &b_entry, locals);
    const then_block = try self.newBlock();
    const else_block = try self.newBlock();
    const merge_block = try self.newBlock();

    self.blocks.items[b_entry].terminator = .{ .branch = .{ .cond = cond_val, .then_block = then_block, .else_block = else_block } };

    var b_then = then_block;
    const then_val = try self.compileExpr(store, then_id, &b_then, locals);
    // Si le bloc courant de la branche then ne s'est pas déjà terminé (par un break/ret), on jump au merge
    if (std.meta.activeTag(self.blocks.items[b_then].terminator) == .fallthrough) {
        self.blocks.items[b_then].terminator = .{ .jump = merge_block };
    }

    var b_else = else_block;
    const else_val = try self.compileExpr(store, else_id, &b_else, locals);
    if (self.blocks.items[b_else].terminator == .fallthrough) {
        self.blocks.items[b_else].terminator = .{ .jump = merge_block };
    }

    const phi_dest = self.newReg();
    // Ne collecter que les blocs terminaux qui jumpent vers merge_block
    var incoming = std.ArrayListUnmanaged(PhiEntry){};
    defer incoming.deinit(self.allocator);

    if (std.meta.activeTag(self.blocks.items[b_then].terminator) == .jump and self.blocks.items[b_then].terminator.jump == merge_block) {
        try incoming.append(self.allocator, .{ .value = then_val, .block = b_then });
    }
    if (std.meta.activeTag(self.blocks.items[b_else].terminator) == .jump and self.blocks.items[b_else].terminator.jump == merge_block) {
        try incoming.append(self.allocator, .{ .value = else_val, .block = b_else });
    }

    // S'il y a au moins un incoming, on crée un phi ; on laisse merge_block en fallthrough
    // pour permettre la poursuite dans une expression englobante.
    if (incoming.items.len > 0) {
        const incoming_copy = try self.allocator.dupe(PhiEntry, incoming.items);
        errdefer self.allocator.free(incoming_copy);
        try self.blocks.items[merge_block].instrs.append(self.allocator, .{ .phi = .{ .dest = phi_dest, .incoming = incoming_copy } });
    } else {
        try self.blocks.items[merge_block].instrs.append(self.allocator, .{ .const_int = .{ .dest = phi_dest, .value = 0 } });
    }

    current_block.* = merge_block;
    return phi_dest;
}

pub fn compileWhile(self: *MirFunction, store: *Store, cond_id: Reg, body_id: Reg, entry_block: BlockId, locals: std.AutoHashMap(u32, Reg)) MirError!Id {
    const cond_block = try self.newBlock();
    const body_block = try self.newBlock();
    const exit_block = try self.newBlock();

    // Sauvegarder l'état de la boucle parente
    const old_exit = self.loop_exit_block;
    const old_break_values_len = self.break_values.items.len;

    self.loop_exit_block = exit_block;

    self.blocks.items[entry_block].terminator = .{ .jump = cond_block };

    var b_cond = cond_block;
    const cond_val = try self.compileExpr(store, cond_id, &b_cond, locals);

    // Valeur de sortie normale (condition fausse). Doit figurer
    // comme incoming du phi de sortie si des breaks existent : le
    // CFG a un arc cond_block -> exit_block (else du branch), et
    // QBE exige que TOUS les predecesseurs reels d'un bloc
    // apparaissent dans ses phis ("predecessors not matched").
    const normal_exit_reg = self.newReg();
    try self.blocks.items[cond_block].instrs.append(self.allocator, .{ .const_int = .{ .dest = normal_exit_reg, .value = 0 } });

    self.blocks.items[cond_block].terminator = .{ .branch = .{ .cond = cond_val, .then_block = body_block, .else_block = exit_block } };

    var b_body = body_block;
    _ = try self.compileExpr(store, body_id, &b_body, locals);
    // Si le corps ne s'est pas terminé par un break, on reboucle depuis le bloc courant final
    if (self.blocks.items[b_body].terminator == .fallthrough) {
        self.blocks.items[b_body].terminator = .{ .jump = cond_block };
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

pub fn compileBreak(self: *MirFunction, store: *Store, value_expr_id: Reg, target_block: BlockId, locals: std.AutoHashMap(u32, Reg)) MirError!Id {
    const exit_block = self.loop_exit_block orelse return error.BreakOutsideLoop;
    var b_target = target_block;
    const val_reg = try self.compileExpr(store, value_expr_id, &b_target, locals);

    // Enregistrer la valeur de break pour le phi à la sortie depuis le bloc courant final
    try self.break_values.append(self.allocator, .{ .value = val_reg, .block = b_target });

    // Sauter au bloc de sortie de la boucle
    self.blocks.items[b_target].terminator = .{ .jump = exit_block };
    return val_reg;
}

pub fn compilePow(
    self: *MirFunction,
    store: *Store,
    base_id: Id,
    exp_id: Id,
    entry_block: BlockId,
    locals: std.AutoHashMap(u32, Reg),
) MirError!Reg {
    var b_entry = entry_block;
    const base_val = try self.compileExpr(store, base_id, &b_entry, locals);
    const exp_val = try self.compileExpr(store, exp_id, &b_entry, locals);

    const acc0 = self.newReg();
    try self.blocks.items[entry_block].instrs.append(self.allocator, .{
        .const_int = .{ .dest = acc0, .value = 1 },
    });

    const hdr_block = try self.newBlock();
    const body_block = try self.newBlock();
    const exit_block = try self.newBlock();

    self.blocks.items[entry_block].terminator = .{ .jump = hdr_block };

    const cur_acc = self.newReg();
    const cur_exp = self.newReg();
    const acc_next = self.newReg();
    const exp_next = self.newReg();

    const hdr_acc_in = try self.allocator.dupe(PhiEntry, &.{
        .{ .value = acc0, .block = entry_block },
        .{ .value = acc_next, .block = body_block },
    });
    errdefer self.allocator.free(hdr_acc_in);
    try self.blocks.items[hdr_block].instrs.append(self.allocator, .{
        .phi = .{ .dest = cur_acc, .incoming = hdr_acc_in },
    });

    const hdr_exp_in = try self.allocator.dupe(PhiEntry, &.{
        .{ .value = exp_val, .block = entry_block },
        .{ .value = exp_next, .block = body_block },
    });
    errdefer self.allocator.free(hdr_exp_in);
    try self.blocks.items[hdr_block].instrs.append(self.allocator, .{
        .phi = .{ .dest = cur_exp, .incoming = hdr_exp_in },
    });

    const zero = self.newReg();
    try self.blocks.items[hdr_block].instrs.append(self.allocator, .{
        .const_int = .{ .dest = zero, .value = 0 },
    });
    const cond = self.newReg();
    try self.blocks.items[hdr_block].instrs.append(self.allocator, .{
        .cmp_lt = .{ .dest = cond, .lhs = zero, .rhs = cur_exp },
    });
    self.blocks.items[hdr_block].terminator = .{ .branch = .{
        .cond = cond,
        .then_block = body_block,
        .else_block = exit_block,
    } };

    try self.blocks.items[body_block].instrs.append(self.allocator, .{
        .mul = .{ .dest = acc_next, .lhs = cur_acc, .rhs = base_val },
    });
    const one = self.newReg();
    try self.blocks.items[body_block].instrs.append(self.allocator, .{
        .const_int = .{ .dest = one, .value = 1 },
    });
    try self.blocks.items[body_block].instrs.append(self.allocator, .{
        .sub = .{ .dest = exp_next, .lhs = cur_exp, .rhs = one },
    });
    self.blocks.items[body_block].terminator = .{ .jump = hdr_block };

    self.blocks.items[exit_block].terminator = .fallthrough;
    return cur_acc;
}

