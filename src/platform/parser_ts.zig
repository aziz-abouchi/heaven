// HEAVEN:parser_ts — extraction tree-sitter (refactor plateforme)
const std = @import("std");

pub const ts = @cImport({
    @cInclude("tree_sitter/api.h");
});

// Déclarations des parsers (on unifie le typage ici)
pub extern fn tree_sitter_heaven() *ts.TSLanguage;
pub extern fn tree_sitter_pie() *ts.TSLanguage;
pub extern fn tree_sitter_c() *ts.TSLanguage;
pub extern fn tree_sitter_zig() *ts.TSLanguage;

pub const shell_parser_types = @import("shell_parser_types");

/// Parser par défaut : grammaire Heaven
pub const ShellParser = shell_parser_types.TreeSitterParser(ts, tree_sitter_heaven);

/// Parser multi-langage : union taguée pour supporter plusieurs grammaires
pub const MultiParser = union(shell_parser_types.Language) {
    heaven: shell_parser_types.TreeSitterParser(ts, tree_sitter_heaven),
    pie: shell_parser_types.TreeSitterParser(ts, tree_sitter_pie),
    c: shell_parser_types.TreeSitterParser(ts, tree_sitter_c),
    zig: shell_parser_types.TreeSitterParser(ts, tree_sitter_zig),
    turtle: void,  // Pas de parser tree-sitter pour turtle, géré séparément

    pub fn init(alloc: std.mem.Allocator, lang: shell_parser_types.Language) shell_parser_types.ParseError!MultiParser {
        return switch (lang) {
            .heaven => .{ .heaven = try shell_parser_types.TreeSitterParser(ts, tree_sitter_heaven).init(alloc) },
            .pie => .{ .pie = try shell_parser_types.TreeSitterParser(ts, tree_sitter_pie).init(alloc) },
            .c => .{ .c = try shell_parser_types.TreeSitterParser(ts, tree_sitter_c).init(alloc) },
            .zig => .{ .zig = try shell_parser_types.TreeSitterParser(ts, tree_sitter_zig).init(alloc) },
            .turtle => .{ .turtle = {} },  // Jamais utilisé, turtle est géré avant
        };
    }

    pub fn parse(self: *MultiParser, source: []const u8) shell_parser_types.ParseError!shell_parser_types.Matrix {
        return switch (self.*) {
            .heaven => |*p| p.parse(source),
            .pie => |*p| p.parse(source),
            .c => |*p| p.parse(source),
            .zig => |*p| p.parse(source),
            .turtle => error.NotSupported,  // Turtle est géré séparément
        };
    }

    pub fn reset(self: *MultiParser) void {
        switch (self.*) {
            .heaven => |*p| p.reset(),
            .pie => |*p| p.reset(),
            .c => |*p| p.reset(),
            .zig => |*p| p.reset(),
            .turtle => {},  // Rien à faire
        }
    }

    pub fn deinit(self: *MultiParser) void {
        switch (self.*) {
            .heaven => |*p| p.deinit(),
            .pie => |*p| p.deinit(),
            .c => |*p| p.deinit(),
            .zig => |*p| p.deinit(),
            .turtle => {},  // Rien à libérer
        }
    }
};
