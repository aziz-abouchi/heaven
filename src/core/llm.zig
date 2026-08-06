const std = @import("std");
const Allocator = std.mem.Allocator;

extern fn js_ollama_query(prompt_ptr: [*]const u8, prompt_len: usize, out_ptr: [*]u8, out_max: usize) usize;

pub fn query(prompt: []const u8, allocator: Allocator) !?[]const u8 {
    // Tenter Ollama en WASM (si disponible)
    if (@import("builtin").target.cpu.arch.isWasm()) {
        var buf: [1024]u8 = undefined;
        const len = js_ollama_query(prompt.ptr, prompt.len, &buf, buf.len);
        if (len > 0) {
            return @as(?[]const u8, try allocator.dupe(u8, buf[0..len]));
        }
    }

    // Enrichir les patterns simulés
    const patterns = [_]struct { keywords: []const u8, response: []const u8 }{
        .{ .keywords = "commutativité,commute", .response = "theorem comm_test : a + b = b + a" },
        .{ .keywords = "factorielle,fact", .response = "let fac(n) = (if (== n 0) 1 (* n (fac (- n 1))))" },
        .{ .keywords = "simplifie,réduis,simplify", .response = "simplify x + 0" },
        .{ .keywords = "dérive,dérivé,derive", .response = "derive x ^ 2" },
        .{ .keywords = "intègre,intégrale,integrate", .response = "integrate x ^ 2" },
        .{ .keywords = "prouve,preuve,prove", .response = "prove add_zero by simplify" },
        .{ .keywords = "transform,transformation", .response = "transform x + 0 = x" },
        .{ .keywords = "MIR,mir,compile", .response = "mir (+ 2 3)" },
        .{ .keywords = "JavaScript,js,transpile", .response = "js 2 + 3 * 4" },
        .{ .keywords = "aide,aide,help", .response = "help" },
        .{ .keywords = "stats,statistiques", .response = "stats" },
        .{ .keywords = "théorème,theorem", .response = "theorem add_zero : a + 0 = a" },
        .{ .keywords = "Peano,entiers naturels,succ,zero", .response = "let add(zero, n) = n; add(succ(n), m) = succ(add(n, m))" },
        .{ .keywords = "liste,list,cons,nil", .response = "let length(nil) = 0; length(cons(_, xs)) = succ(length(xs))" },
        .{ .keywords = "résous,solve,équation", .response = "solve x + 2 = 5" },
        .{ .keywords = "développe,expand,développer", .response = "expand (x + 1) * (x + 2)" },
        .{ .keywords = "trace,tracer", .response = "trace 2 + 3 * 4" },
        .{ .keywords = "optimise,optimiser,optimize", .response = "optimize x * 1 + 0" },
        .{ .keywords = "LaTeX,latex,formule", .response = "latex x ^ 2 + 1" },
        .{ .keywords = "explique,expliquer,explain", .response = "explain x + 0" },
    };

    for (patterns) |p| {
        var it = std.mem.tokenizeAny(u8, p.keywords, ",");
        while (it.next()) |kw| {
            const kw_trimmed = std.mem.trim(u8, kw, " ");
            if (std.mem.containsAtLeast(u8, prompt, 1, kw_trimmed)) {
                return @as(?[]const u8, try allocator.dupe(u8, p.response));
            }
        }
    }

    return null;
}
