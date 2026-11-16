const std = @import("std");

pub fn labelFromEvalProve(out: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, out, " \t\r\n");

    if (std.mem.indexOf(u8, trimmed, "proved (")) |start| {
        const p = start + "proved (".len;
        if (std.mem.indexOfPos(u8, trimmed, p, ")")) |end| {
            const m = trimmed[p..end];
            if (m.len > 0 and !std.mem.eql(u8, m, "kernel")) return m;
        }
    }

    if (std.mem.indexOf(u8, trimmed, "via ")) |start| {
        const p = start + "via ".len;
        var end = p;
        while (end < trimmed.len and trimmed[end] != '\n' and trimmed[end] != ' ') : (end += 1) {}
        const m = trimmed[p..end];
        if (m.len > 0 and !std.mem.eql(u8, m, "kernel")) return m;
    }

    return "unverified-by-kernel";
}


test "labelFromEvalProve - tactics" {
    try std.testing.expectEqualStrings("tactics", labelFromEvalProve("OK [t1] proved (tactics)\n"));
}
test "labelFromEvalProve - simplify" {
    try std.testing.expectEqualStrings("simplify", labelFromEvalProve("OK [t1] proved (simplify)"));
}
test "labelFromEvalProve - induction" {
    try std.testing.expectEqualStrings("induction", labelFromEvalProve("OK [t1] proved (induction)"));
}
test "labelFromEvalProve - eval" {
    try std.testing.expectEqualStrings("eval", labelFromEvalProve("OK [t1] proved (eval)"));
}
test "labelFromEvalProve - rewrite" {
    try std.testing.expectEqualStrings("rewrite", labelFromEvalProve("OK [t1] proved (rewrite)"));
}
test "labelFromEvalProve - via skill" {
    try std.testing.expectEqualStrings("skill", labelFromEvalProve("OK [t1] y proved via skill\nreport"));
}
test "labelFromEvalProve - kernel banned form 1" {
    try std.testing.expectEqualStrings("unverified-by-kernel", labelFromEvalProve("OK [t1] proved (kernel)"));
}
test "labelFromEvalProve - kernel banned form 2" {
    try std.testing.expectEqualStrings("unverified-by-kernel", labelFromEvalProve("OK [t1] proved via kernel"));
}
test "labelFromEvalProve - no marker" {
    try std.testing.expectEqualStrings("unverified-by-kernel", labelFromEvalProve("OK module Foo ouvert"));
}
test "labelFromEvalProve - empty" {
    try std.testing.expectEqualStrings("unverified-by-kernel", labelFromEvalProve(""));
}
test "labelFromEvalProve - failure message" {
    try std.testing.expectEqualStrings("unverified-by-kernel", labelFromEvalProve("FAIL [t1] goal(s) remaining"));
}
