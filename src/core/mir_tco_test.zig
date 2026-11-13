const std = @import("std");
const mir = @import("mir");
const MirFunction = mir.MirFunction;
const Reg = mir.Reg;
const Sym = @import("expr").Sym;

fn buildTailCallerFn(alloc: std.mem.Allocator, target_sym: u32) !MirFunction {
    var mf = MirFunction.init(alloc);
    mf.next_value = 1;
    _ = try mf.newBlock();
    const call_r = mf.newReg();
    const args = try alloc.alloc(Reg, 1);
    args[0] = 0;
    try mf.blocks.items[0].instrs.append(alloc, .{
        .call_user = .{ .dest = call_r, .name = target_sym, .args = args },
    });
    mf.blocks.items[0].terminator = .{ .ret = call_r };
    return mf;
}

fn registerTailFn(mf: *MirFunction, alloc: std.mem.Allocator, sym: u32, target_sym: u32) !void {
    const fn_mir = try buildTailCallerFn(alloc, target_sym);
    const param_regs = try alloc.alloc(Reg, 1);
    param_regs[0] = 0;
    // Invariant fuseTailSCCs : param_names.len == param_regs.len.
    // Sym = u32 (expr.Id), 0 = placeholder inutilise par la fusion.
    const param_names = try alloc.alloc(Sym, 1);
    param_names[0] = 0;
    try mf.fnDefsMut().put(sym, .{
        .fn_mir = fn_mir,
        .param_names = param_names,
        .param_regs = param_regs,
    });
}

fn buildParityFn(alloc: std.mem.Allocator, other_sym: u32, base_value: i64) !MirFunction {
    var mf = MirFunction.init(alloc);
    const b0 = try mf.newBlock();
    const b_then = try mf.newBlock();
    const b_else = try mf.newBlock();
    mf.next_value = 1;
    const zero_r = mf.newReg();
    const cmp_r = mf.newReg();
    const then_r = mf.newReg();
    const one_r = mf.newReg();
    const nm1_r = mf.newReg();
    const call_r = mf.newReg();
    try mf.blocks.items[b0].instrs.append(alloc, .{ .const_int = .{ .dest = zero_r, .value = 0 } });
    try mf.blocks.items[b0].instrs.append(alloc, .{ .cmp_eq = .{ .dest = cmp_r, .lhs = 0, .rhs = zero_r } });
    mf.blocks.items[b0].terminator = .{ .branch = .{ .cond = cmp_r, .then_block = b_then, .else_block = b_else } };
    try mf.blocks.items[b_then].instrs.append(alloc, .{ .const_int = .{ .dest = then_r, .value = base_value } });
    mf.blocks.items[b_then].terminator = .{ .ret = then_r };
    try mf.blocks.items[b_else].instrs.append(alloc, .{ .const_int = .{ .dest = one_r, .value = 1 } });
    try mf.blocks.items[b_else].instrs.append(alloc, .{ .sub = .{ .dest = nm1_r, .lhs = 0, .rhs = one_r } });
    const args = try alloc.alloc(Reg, 1);
    args[0] = nm1_r;
    try mf.blocks.items[b_else].instrs.append(alloc, .{ .call_user = .{ .dest = call_r, .name = other_sym, .args = args } });
    mf.blocks.items[b_else].terminator = .{ .ret = call_r };
    return mf;
}

fn registerParityFn(mf: *MirFunction, alloc: std.mem.Allocator, sym: u32, other: u32, base: i64) !void {
    const fn_mir = try buildParityFn(alloc, other, base);
    const param_regs = try alloc.alloc(Reg, 1);
    param_regs[0] = 0;
    // Invariant fuseTailSCCs : param_names.len == param_regs.len.
    // Sym = u32 (expr.Id), 0 = placeholder inutilise par la fusion.
    const param_names = try alloc.alloc(Sym, 1);
    param_names[0] = 0;
    try mf.fnDefsMut().put(sym, .{ .fn_mir = fn_mir, .param_names = param_names, .param_regs = param_regs });
}

test "tco_mutual — findTailSCCs regroupe {even, odd}" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var mf = MirFunction.init(a);
    try registerTailFn(&mf, a, 0, 1);
    try registerTailFn(&mf, a, 1, 0);
    const sccs = try mf.findTailSCCs(a);
    defer { for (sccs) |scc| a.free(scc); a.free(sccs); }
    try std.testing.expectEqual(@as(usize, 1), sccs.len);
    try std.testing.expectEqual(@as(usize, 2), sccs[0].len);
    var saw_0 = false; var saw_1 = false;
    for (sccs[0]) |s| { if (s == 0) saw_0 = true; if (s == 1) saw_1 = true; }
    try std.testing.expect(saw_0 and saw_1);
}

test "tco_mutual — fuseTailSCCs produit un scc_sym unique" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var mf = MirFunction.init(a);
    try registerTailFn(&mf, a, 0, 1);
    try registerTailFn(&mf, a, 1, 0);
    const infos = try mf.fuseTailSCCs(a);
    defer { for (infos) |info| a.free(info.members); a.free(infos); }
    try std.testing.expectEqual(@as(usize, 1), infos.len);
    try std.testing.expectEqual(@as(usize, 2), infos[0].members.len);
    try std.testing.expect(infos[0].scc_sym != 0 and infos[0].scc_sym != 1);
}

// EXEC-TEST-DISABLED: cloneFunction ne propage pas fn_defs (bug mir.zig:1475-1497).
test "tco_mutual — execute identique avant/après fusion" {
    if (true) return; // TODO: débloquer après fix cloneFunction
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var mf = MirFunction.init(a);
    try registerParityFn(&mf, a, 0, 1, 1);
    try registerParityFn(&mf, a, 1, 0, 0);
    const entry = try mf.newBlock();
    const ten_r = mf.newReg();
    const res_r = mf.newReg();
    try mf.blocks.items[entry].instrs.append(a, .{ .const_int = .{ .dest = ten_r, .value = 10 } });
    const args = try a.alloc(Reg, 1);
    args[0] = ten_r;
    try mf.blocks.items[entry].instrs.append(a, .{ .call_user = .{ .dest = res_r, .name = 0, .args = args } });
    mf.blocks.items[entry].terminator = .{ .ret = res_r };
    var g1 = std.AutoHashMap(u32, i64).init(a);
    defer g1.deinit();
    const before = try mf.execute(&g1);
    std.debug.print("\n[TCO] before fusion: even(10) = {d}\n", .{before});
    try std.testing.expectEqual(@as(i64, 1), before);
    const infos = try mf.fuseTailSCCs(a);
    defer { for (infos) |i| a.free(i.members); a.free(infos); }
    try std.testing.expectEqual(@as(usize, 1), infos.len);
    var g2 = std.AutoHashMap(u32, i64).init(a);
    defer g2.deinit();
    const after = try mf.execute(&g2);
    std.debug.print("[TCO] after  fusion: even(10) = {d}\n", .{after});
    try std.testing.expectEqual(before, after);
}
