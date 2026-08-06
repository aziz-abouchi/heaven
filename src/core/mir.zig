const std = @import("std");
const expr_mod = @import("expr");
const engine_mod = @import("engine_expr");
const Store = expr_mod.Store;
pub const Id = expr_mod.Id;

// ValueId remplacé par Id (Expr IR)
// pub const ValueId = u32;
pub const BlockId = u32;

pub const MirError = error{
    UnsupportedExpr,
    UnsupportedLiteral,
    UnsupportedOp,
    OutOfMemory,
    DivisionByZero,
    InvalidInstruction,
    ValueNotDefined,
    UndefinedVariable,
    TooManyIterations,
    BreakOutsideLoop,
};

const PhiEntry = struct { value: Id, block: BlockId };

pub const Instr = union(enum) {
    const_int: struct { dest: Id, value: i64 },
    add: struct { dest: Id, lhs: Id, rhs: Id },
    sub: struct { dest: Id, lhs: Id, rhs: Id },
    mul: struct { dest: Id, lhs: Id, rhs: Id },
    div: struct { dest: Id, lhs: Id, rhs: Id },
    cmp_lt: struct { dest: Id, lhs: Id, rhs: Id },
    cmp_eq: struct { dest: Id, lhs: Id, rhs: Id },
    jump: struct { target: BlockId },
    branch: struct { cond: Id, then_block: BlockId, else_block: BlockId },
    ret: struct { value: Id },
    phi: struct { dest: Id, incoming: []const PhiEntry },
    load: struct { dest: Id, sym: u32 },
    store: struct { sym: u32, src: Id },
    call_user: struct { dest: Id, name: u32, args: []const Id },
};

pub const BasicBlock = struct {
    instrs: std.ArrayListUnmanaged(Instr),
    terminator: union(enum) {
        jump: BlockId,
        branch: struct { cond: Id, then_block: BlockId, else_block: BlockId },
        ret: Id,
        fallthrough,
    },
};

pub const MirFunction = struct {
    allocator: std.mem.Allocator,
    blocks: std.ArrayListUnmanaged(BasicBlock),
    next_value: Id = 0,
    next_block: BlockId = 0,
    loop_exit_block: ?BlockId = null,
    break_values: std.ArrayListUnmanaged(PhiEntry) = .{},
    store: ?*Store = null,
    engine: ?*engine_mod.Engine = null,
    store_ref: ?*Store = null,

    pub fn init(allocator: std.mem.Allocator) MirFunction {
        return .{
            .allocator = allocator,
            .blocks = .{},
            .store = null,
        };
    }

    pub fn initWithStore(allocator: std.mem.Allocator, store: *Store) MirFunction {
        return .{
            .allocator = allocator,
            .blocks = .{},
            .store = store,
        };
    }

    pub fn deinit(self: *MirFunction) void {
        for (self.blocks.items) |*blk| {
            blk.instrs.deinit(self.allocator);
        }
        self.blocks.deinit(self.allocator);
        self.break_values.deinit(self.allocator);
    }

    /// Alloue un nœud placeholder dans le Store Expr IR pour une valeur MIR
    pub fn newValue(self: *MirFunction) !Id {
        const s = self.store orelse {
            // Fallback: mode legacy sans store (pour tests unitaires)
            defer self.next_value += 1;
            return @as(Id, self.next_value);
        };
        // Créer un nœud lit(0) comme placeholder - sera remplacé par l'instruction réelle
        return s.int(0);
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

    pub fn compileExpr(self: *MirFunction, store: *Store, id: Id, target_block: BlockId, locals: std.AutoHashMap(u32, Id)) MirError!Id {
        const node = store.get(id);
        switch (node.tag) {
            .bind => {
                const sym = node.payload;
                const value_id = node.aux;
                const val_reg = try self.compileExpr(store, value_id, target_block, locals);
                var new_locals = try locals.clone();
                defer new_locals.deinit();
                try new_locals.put(sym, val_reg);
                // Si span_a n'est pas vide, c'est le corps du let
                if (node.span_a.len > 0) {
                    const body_id = node.span_a.start;
                    return try self.compileExpr(store, body_id, target_block, new_locals);
                }
                return val_reg;
            },
            .sym => {
                const sym = node.payload;
                if (locals.get(sym)) |reg| {
                    return reg;
                }
                const dest = try self.newValue();
                try self.blocks.items[target_block].instrs.append(self.allocator, .{ .load = .{ .dest = dest, .sym = sym } });
                return dest;
            },
            .lit => {
                const l = store.lits.items[node.aux];
                switch (l) {
                    .int => |v| {
                        const dest = try self.newValue();
                        try self.blocks.items[target_block].instrs.append(self.allocator, .{ .const_int = .{ .dest = dest, .value = v } });
                        return dest;
                    },
                    else => return error.UnsupportedLiteral,
                }
            },
            .apply => {
                const func_node = store.get(node.payload);
                if (func_node.tag != .sym) return error.UnsupportedExpr;
                const op_name = store.interner.resolve(func_node.payload);
                const args = node.span_a.slice(store.pool.items);

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
                        const dest = try self.newValue();
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
                    const dest = try self.newValue();
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
            else => return error.UnsupportedExpr,
        }
    }

    fn compileIf(self: *MirFunction, store: *Store, cond_id: Id, then_id: Id, else_id: Id, entry_block: BlockId, locals: std.AutoHashMap(u32, Id)) MirError!Id {
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

        const phi_dest = try self.newValue();
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

    fn compileWhile(self: *MirFunction, store: *Store, cond_id: Id, body_id: Id, entry_block: BlockId, locals: std.AutoHashMap(u32, Id)) MirError!Id {
        const cond_block = try self.newBlock();
        const body_block = try self.newBlock();
        const exit_block = try self.newBlock();

        // Sauvegarder l'état de la boucle parente
        const old_exit = self.loop_exit_block;
        const old_break_values_len = self.break_values.items.len;

        self.loop_exit_block = exit_block;

        self.blocks.items[entry_block].terminator = .{ .jump = cond_block };

        const cond_val = try self.compileExpr(store, cond_id, cond_block, locals);
        self.blocks.items[cond_block].terminator = .{ .branch = .{ .cond = cond_val, .then_block = body_block, .else_block = exit_block } };

        _ = try self.compileExpr(store, body_id, body_block, locals);
        // Si le corps ne s'est pas terminé par un break, on reboucle
        if (self.blocks.items[body_block].terminator == .fallthrough) {
            self.blocks.items[body_block].terminator = .{ .jump = cond_block };
        }

        // Collecter les valeurs de break pour le phi à la sortie
        const break_entries = self.break_values.items[old_break_values_len..];
        const phi_dest = try self.newValue();

        if (break_entries.len > 0) {
            // On a des break avec valeurs, créer un phi
            const incoming_copy = try self.allocator.dupe(PhiEntry, break_entries);
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

    fn compileBreak(self: *MirFunction, store: *Store, value_expr_id: Id, target_block: BlockId, locals: std.AutoHashMap(u32, Id)) MirError!Id {
        const exit_block = self.loop_exit_block orelse return error.BreakOutsideLoop;
        const val_reg = try self.compileExpr(store, value_expr_id, target_block, locals);

        // Enregistrer la valeur de break pour le phi à la sortie
        try self.break_values.append(self.allocator, .{ .value = val_reg, .block = target_block });

        // Sauter au bloc de sortie de la boucle
        self.blocks.items[target_block].terminator = .{ .jump = exit_block };
        return val_reg;
    }

    /// TODO: Réécrire execute pour opérer sur Id (Expr IR) au lieu de ValueId
    pub fn execute(self: *MirFunction, global_vars: *std.AutoHashMap(u32, i64)) MirError!i64 {
        _ = self;
        _ = global_vars;
        return error.UnsupportedExpr;
    }

    /// Ancienne implémentation execute désactivée pendant la réécriture Id-based
    fn executeLegacy(self: *MirFunction, global_vars: *std.AutoHashMap(u32, i64)) MirError!i64 {
        if (self.blocks.items.len == 0) return 0;
        var current_block: BlockId = 0;
        var values = std.ArrayListUnmanaged(i64){};
        defer values.deinit(self.allocator);
        var prev_block: BlockId = 0;

        var iterations: u32 = 0;
        while (true) : (iterations += 1) {
            if (iterations > 1000) return error.TooManyIterations;
            const block = self.blocks.items[current_block];
            for (block.instrs.items) |inst| {
                switch (inst) {
                    .const_int => |c| {
                        if (c.dest >= values.items.len) try values.resize(self.allocator, c.dest + 1);
                        values.items[c.dest] = c.value;
                    },
                    .add => |a| {
                        if (a.dest >= values.items.len) try values.resize(self.allocator, a.dest + 1);
                        values.items[a.dest] = values.items[a.lhs] + values.items[a.rhs];
                    },
                    .sub => |a| {
                        if (a.dest >= values.items.len) try values.resize(self.allocator, a.dest + 1);
                        values.items[a.dest] = values.items[a.lhs] - values.items[a.rhs];
                    },
                    .mul => |a| {
                        if (a.dest >= values.items.len) try values.resize(self.allocator, a.dest + 1);
                        values.items[a.dest] = values.items[a.lhs] * values.items[a.rhs];
                    },
                    .div => |a| {
                        if (a.dest >= values.items.len) try values.resize(self.allocator, a.dest + 1);
                        if (values.items[a.rhs] == 0) return error.DivisionByZero;
                        values.items[a.dest] = @divTrunc(values.items[a.lhs], values.items[a.rhs]);
                    },
                    .cmp_lt => |a| {
                        if (a.dest >= values.items.len) try values.resize(self.allocator, a.dest + 1);
                        values.items[a.dest] = if (values.items[a.lhs] < values.items[a.rhs]) 1 else 0;
                    },
                    .cmp_eq => |a| {
                        if (a.dest >= values.items.len) try values.resize(self.allocator, a.dest + 1);
                        values.items[a.dest] = if (values.items[a.lhs] == values.items[a.rhs]) 1 else 0;
                    },
                    .load => |ld| {
                        const val = global_vars.get(ld.sym) orelse return error.UndefinedVariable;
                        if (ld.dest >= values.items.len) try values.resize(self.allocator, ld.dest + 1);
                        values.items[ld.dest] = val;
                    },
                    .store => |st| {
                        const val = values.items[st.src];
                        try global_vars.put(st.sym, val);
                    },
                    .phi => |p| {
                        var found = false;
                        for (p.incoming) |in| {
                            if (in.block == prev_block) {
                                if (in.value >= values.items.len) return error.ValueNotDefined;
                                const val = values.items[in.value];
                                if (p.dest >= values.items.len) try values.resize(self.allocator, p.dest + 1);
                                values.items[p.dest] = val;
                                found = true;
                                break;
                            }
                        }
                        if (!found) return error.InvalidInstruction;
                    },
                    .jump, .branch, .ret => unreachable,
                    .call_user => |cu| {
                        const store = self.store_ref orelse return error.InvalidInstruction;
                        const engine = self.engine orelse return error.InvalidInstruction;
                        const name = store.interner.resolve(cu.name);
                        var args_list = std.ArrayListUnmanaged(Id){};
                        defer args_list.deinit(self.allocator);
                        for (cu.args) |arg_reg| {
                            const val = values.items[arg_reg];
                            const id = try store.int(val);
                            try args_list.append(self.allocator, id);
                        }
                        const result_id = engine.evalFunction(name, args_list.items) catch return error.InvalidInstruction;
                        const result_node = store.get(result_id);
                        if (result_node.tag == .lit) {
                            const lit = store.lits.items[result_node.aux];
                            switch (lit) {
                                .int => |v| {
                                    if (cu.dest >= values.items.len) try values.resize(self.allocator, cu.dest + 1);
                                    values.items[cu.dest] = v;
                                },
                                else => return error.InvalidInstruction,
                            }
                        } else {
                            return error.InvalidInstruction;
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
                    const cond = values.items[b.cond];
                    prev_block = current_block;
                    current_block = if (cond != 0) b.then_block else b.else_block;
                },
                .ret => |r| {
                    if (r >= values.items.len) return error.ValueNotDefined;
                    return values.items[r];
                },
                .fallthrough => return 0,
            }
        }
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
    _ = try mir.compileExpr(&store, expr_id, entry, std.AutoHashMap(u32, Id).init(allocator));
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
    var locals = std.AutoHashMap(u32, Id).init(allocator);
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
    var locals = std.AutoHashMap(u32, Id).init(allocator);
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
    var locals = std.AutoHashMap(u32, Id).init(allocator);
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
    var locals = std.AutoHashMap(u32, Id).init(allocator);
    defer locals.deinit();

    // let x = 0 in while(...)
    const full_expr = try store.bind("x", try store.int(0), while_expr);
    _ = try mir.compileExpr(&store, full_expr, entry, locals);

    var globals = std.AutoHashMap(u32, i64).init(allocator);
    defer globals.deinit();
    const result = try mir.execute(&globals);
    try std.testing.expectEqual(3, result); // break(x) quand x=3
}
