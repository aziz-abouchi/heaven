//! Wrappers de génération de code pour Heaven
//! Extrait de heaven_expr.zig pour modularité

const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const codegen_c = @import("codegen_expr_c");
const codegen_latex = @import("codegen_expr_latex");

pub const CodegenWrapper = struct {
    store: *Store,
    allocator: Allocator,

    pub fn init(store: *Store, allocator: Allocator) CodegenWrapper {
        return .{ .store = store, .allocator = allocator };
    }

    /// Génère du C pour une liste d'expressions
    pub fn toC(self: *CodegenWrapper, ids: []const Id) ![]u8 {
        var cg = codegen_c.Codegen.init(self.store, self.allocator);
        defer cg.deinit();
        return cg.generate(ids);
    }

    /// Génère du LaTeX pour une liste d'expressions
    pub fn toLaTeX(self: *CodegenWrapper, ids: []const Id) ![]u8 {
        var gen = codegen_latex.LaTeX.init(self.store, self.allocator);
        defer gen.deinit();
        return gen.generate(ids);
    }

    /// Génère du LaTeX inline pour une expression unique
    pub fn toLaTeXInline(self: *CodegenWrapper, id: Id) ![]u8 {
        var gen = codegen_latex.LaTeX.init(self.store, self.allocator);
        defer gen.deinit();
        return gen.renderInline(id);
    }

    /// Formate une expression en string
    pub fn format(self: *CodegenWrapper, id: Id) ![]u8 {
        return expr.toString(self.store, id, self.allocator);
    }

    /// Génère du C pour une expression unique
    pub fn exprToC(self: *CodegenWrapper, input: []const u8) ![]u8 {
        _ = input; // TODO: parser l'input et générer du C
        return try self.allocator.dupe(u8, "// exprToC not yet wired");
    }
};
