//! Découpage "expression[, variable]" des commandes shell (derive, solve, ...).
const std = @import("std");

/// Sépare "expression, variable" — la variable est optionnelle (défaut : "x")
pub fn splitExprVar(input: []const u8) struct { expr: []const u8, varname: []const u8 } {
    // 1. Virgule (priorite) : "x^2, y" -> expr="x^2", var="y"
    if (std.mem.lastIndexOfScalar(u8, input, ',')) |comma| {
        const expr = std.mem.trim(u8, input[0..comma], " ");
        const varname = std.mem.trim(u8, input[comma + 1 ..], " ");
        if (expr.len > 0 and varname.len > 0 and isIdentifier(varname)) {
            return .{ .expr = expr, .varname = varname };
        }
    }
    // 2. Dernier espace : "(x^2) x" -> expr="(x^2)", var="x"
    //    "x * x x"  -> expr="x * x",  var="x"
    if (std.mem.lastIndexOfScalar(u8, input, ' ')) |sp| {
        const expr = std.mem.trim(u8, input[0..sp], " ");
        const varname = std.mem.trim(u8, input[sp + 1 ..], " ");
        // La variable commence par une lettre/_ (pas "1") et l'expression
        // restante ne finit pas par un opérateur ("x +" + "y" = expression infixe).
        if (expr.len > 0 and varname.len > 0 and isIdentifier(varname) and
            (std.ascii.isAlphabetic(varname[0]) or varname[0] == '_') and
            std.mem.indexOfScalar(u8, "+-*/^%=<>&|!(,:~", expr[expr.len - 1]) == null)
        {
            return .{ .expr = expr, .varname = varname };
        }
    }
    // 3. Defaut : variable implicite "x", expression = input entier.
    return .{ .expr = input, .varname = "x" };
}

fn isIdentifier(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
    }
    return true;
}

test "splitExprVar : expressions infixes non coupées" {
    const t = std.testing;
    const cases = [_]struct { in: []const u8, e: []const u8, v: []const u8 }{
        .{ .in = "x^2", .e = "x^2", .v = "x" },
        .{ .in = "x^2 + 1", .e = "x^2 + 1", .v = "x" },
        .{ .in = "x * x", .e = "x * x", .v = "x" },
        .{ .in = "x + y", .e = "x + y", .v = "x" },
        .{ .in = "x * x x", .e = "x * x", .v = "x" },
        .{ .in = "(x^2) y", .e = "(x^2)", .v = "y" },
        .{ .in = "x^2, y", .e = "x^2", .v = "y" },
        .{ .in = "sin(x) y", .e = "sin(x)", .v = "y" },
    };
    for (cases) |c| {
        const r = splitExprVar(c.in);
        try t.expectEqualStrings(c.e, r.expr);
        try t.expectEqualStrings(c.v, r.varname);
    }
}
