const std = @import("std");
const ast = @import("../kernel/ast.zig");

const c = @cImport({
    @cInclude("tree_sitter/api.h");
});

extern fn tree_sitter_heaven() ?*c.TSLanguage;

pub const Parser = struct {
    allocator: std.mem.Allocator,
    ts_parser: *c.TSParser,

    pub fn init(allocator: std.mem.Allocator) !Parser {
        const p = c.ts_parser_new() orelse return error.TSParserCreationFailed;
        if (c.ts_parser_set_language(p, tree_sitter_heaven()) == false) {
            c.ts_parser_delete(p);
            return error.TSLanguageSetFailed;
        }
        return .{
            .allocator = allocator,
            .ts_parser = p,
        };
    }

    pub fn deinit(self: *Parser) void {
        c.ts_parser_delete(self.ts_parser);
    }

    pub fn parseSource(self: *Parser, source: [:0]const u8) !ast.Term {
        const tree = c.ts_parser_parse_string(
            self.ts_parser,
            null,
            source.ptr,
            @intCast(source.len),
        ) orelse return error.ParsingFailed;
        defer c.ts_tree_delete(tree);

        const root_node = c.ts_tree_root_node(tree);
        return self.nodeToTerm(root_node, source);
    }

    fn nodeToTerm(self: *Parser, node: c.TSNode, source: [:0]const u8) !ast.Term {
        const type_str = std.mem.span(c.ts_node_type(node));

        if (std.mem.eql(u8, type_str, "source_file") or std.mem.eql(u8, type_str, "program")) {
            const child_count = c.ts_node_child_count(node);
            if (child_count == 0) return ast.Term{ .sort = .{ .type_sort = .{ .concrete = 0 } } };
            const first_child = c.ts_node_child(node, 0);
            return self.nodeToTerm(first_child, source);
        }

        if (std.mem.eql(u8, type_str, "number") or std.mem.eql(u8, type_str, "integer")) {
            return ast.Term{ .variable = 42 };
        }

        if (std.mem.eql(u8, type_str, "identifier") or std.mem.eql(u8, type_str, "variable")) {
            return ast.Term{ .variable = 0 };
        }

        if (std.mem.eql(u8, type_str, "class_expr")) {
            const elem_node = c.ts_node_child_by_field_name(node, "element", 7);
            const elem = try self.allocator.create(ast.Term);
            elem.* = if (c.ts_node_is_null(elem_node))
                ast.Term{ .variable = 0 }
            else
                try self.nodeToTerm(elem_node, source);

            const dummy_quot = try self.allocator.create(ast.Term);
            dummy_quot.* = ast.Term{ .sort = .{ .type_sort = .{ .concrete = 0 } } };

            return ast.Term{
                .class = .{
                    .quot_type = dummy_quot,
                    .element = elem,
                },
            };
        }

        return ast.Term{ .variable = 0 };
    }
};
