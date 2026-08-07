const std = @import("std");
const Shell = @import("init.zig").Shell;
const platform = @import("platform");
const PROOF_DEBUG = false;

pub fn bridgeTheoremToProofEnv(self: *Shell, name: []const u8, stmt: []const u8) void {
    if (PROOF_DEBUG) platform.debug.print("DEBUG: bridging theorem name='{s}'\n", .{name});
    if (self.heaven.proof_core.theorems.get(name)) |thm| {
        if (PROOF_DEBUG) platform.debug.print("DEBUG: found in proof_core, lhs={d} rhs={d}\n", .{ thm.lhs, thm.rhs });
        self.proofs.theorem(name, stmt, thm.lhs, thm.rhs) catch |err| {
            if (PROOF_DEBUG) platform.debug.print("DEBUG: self.proofs.theorem failed: {s}\n", .{@errorName(err)});
        };
    } else {
        if (PROOF_DEBUG) platform.debug.print("DEBUG: NOT found in heaven.proof_core.theorems for name='{s}'\n", .{name});
    }
}

pub fn evalHeavenCode(self: *Shell, code: []const u8) void {
    const trimmed = std.mem.trim(u8, code, " \t\r\n");
    if (trimmed.len == 0) return;
    const result = self.heaven.eval(trimmed) catch |err| {
        platform.debug.print(
            "[EVAL ERROR] {}\n",
            .{err},
        );
        self.ingestor.ingest("repl.hvn", trimmed) catch {};
        return;
    };
    defer self.allocator.free(result);
    platform.debug.print("\xe2\x86\x92 {s}\n", .{result});
}

// Fonctions requises par commands.zig — redirigent toutes vers Heaven.eval
pub fn exprEval(self: *Shell, input: []const u8) void {
    const result = self.heaven.eval(input) catch return;
    defer self.allocator.free(result);
    if (PROOF_DEBUG) platform.debug.print("\xe2\x86\x92 {s}\n", .{result});
}

pub fn exprSimplify(self: *Shell, input: []const u8) void {
    const result = self.heaven.simplify(input) catch return;
    defer self.allocator.free(result);
    if (PROOF_DEBUG) platform.debug.print("\xe2\x86\x92 {s}\n", .{result});
}

pub fn exprFact(self: *Shell, input: []const u8) void {
    const result = self.heaven.eval(input) catch return;
    defer self.allocator.free(result);
    if (PROOF_DEBUG) platform.debug.print("\xe2\x86\x92 {s}\n", .{result});
}

pub fn exprRule(self: *Shell, input: []const u8) void {
    const result = self.heaven.eval(input) catch return;
    defer self.allocator.free(result);
    if (PROOF_DEBUG) platform.debug.print("\xe2\x86\x92 {s}\n", .{result});
}

pub fn exprQuery(self: *Shell, input: []const u8) void {
    const result = self.heaven.eval(input) catch return;
    defer self.allocator.free(result);
    if (PROOF_DEBUG) platform.debug.print("\xe2\x86\x92 {s}\n", .{result});
}

pub fn exprRewrite(self: *Shell, input: []const u8) void {
    const result = self.heaven.eval(input) catch return;
    defer self.allocator.free(result);
    if (PROOF_DEBUG) platform.debug.print("\xe2\x86\x92 {s}\n", .{result});
}
