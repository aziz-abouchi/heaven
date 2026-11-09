const std = @import("std");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const Scope = @import("scope.zig").Scope;
const TypeInfo = @import("scope.zig").TypeInfo;
const DiagnosticList = @import("diagnostics.zig").DiagnosticList;
const platform = @import("platform");
const ts = platform.ts;

pub const Bridge = struct {
    store: *Store,
    scope: *Scope,
    diags: *DiagnosticList,
    source: []const u8,
    allocator: std.mem.Allocator,
    /// Ids des nœuds top-level réellement définis (pas les fallbacks
    /// tree-sitter `sym(ntype)`). Utilisé par unbound_check.
    roots: std.ArrayListUnmanaged(Id) = .{},

    pub fn init(
        allocator: std.mem.Allocator,
        store: *Store,
        scope: *Scope,
        diags: *DiagnosticList,
        source: []const u8,
    ) Bridge {
        return .{
            .store = store,
            .scope = scope,
            .diags = diags,
            .source = source,
            .allocator = allocator,
        };
    }

    pub fn deinitRoots(self: *Bridge) void {
        self.roots.deinit(self.allocator);
    }

    pub fn buildFile(self: *Bridge, root: ts.TSNode) !void {
        const count = ts.ts_node_child_count(root);

//         platform.debug.print(
//             "ROOT={s} children={d}\n",
//             .{
//                 ts.ts_node_type(root),
//                 count,
//             },
//         );

        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const child = ts.ts_node_child(root, i);

//             platform.debug.print(
//                 "CHILD[{d}] {s}\n",
//                 .{
//                     i,
//                     ts.ts_node_type(child),
//                 },
//             );
            if (std.mem.eql(u8, self.nodeType(child), "ERROR")) {
                const start = ts.ts_node_start_point(child);
                self.diags.err(start.row, start.column, "syntax error in source");
                continue;
            }
            const id = try self.buildTopLevel(child);
            if (id != expr.NULL) {
                try self.roots.append(self.allocator, id);
            }
        }
    }
    //pub fn buildFile(self: *Bridge, root: ts.TSNode) anyerror!void {
    //    const count = ts.ts_node_child_count(root);
    //    var i: u32 = 0;
    //    while (i < count) : (i += 1) {
    //        const child = ts.ts_node_child(root, i);
    //        _ = self.buildTopLevel(child) catch |e| {
    //            const start = ts.ts_node_start_point(child);
    //            const msg = std.fmt.allocPrint(self.allocator, "Failed to process: {}", .{e}) catch "internal error";
    //            self.diags.err(start.row, start.column, msg);
    //            continue;
    //        };
    //    }
    //}

    fn buildTopLevel(self: *Bridge, node: ts.TSNode) anyerror!Id {
        const ntype = self.nodeType(node);

        if (std.mem.eql(u8, ntype, "fn_decl") or std.mem.eql(u8, ntype, "dist_fn")) {
            return self.buildFnDecl(node);
        } else if (std.mem.eql(u8, ntype, "var_decl")) {
            return self.buildVarDecl(node);
        } else if (std.mem.eql(u8, ntype, "struct_decl")) {
            return self.buildStructDecl(node);
        } else if (std.mem.eql(u8, ntype, "enum_decl")) {
            return self.buildEnumDecl(node);
        } else if (std.mem.eql(u8, ntype, "effect_decl")) {
            return self.buildNamedDecl(node, "effect");
        } else if (std.mem.eql(u8, ntype, "actor_decl")) {
            return self.buildNamedDecl(node, "actor");
        } else if (std.mem.eql(u8, ntype, "class_decl")) {
            return self.buildNamedDecl(node, "class");
        } else if (std.mem.eql(u8, ntype, "instance_decl")) {
            return self.buildNamedDecl(node, "instance");
        } else if (std.mem.eql(u8, ntype, "test_decl")) {
            return self.buildTestDecl(node);
        } else if (std.mem.eql(u8, ntype, "sig_decl")) {
            return self.buildSigDecl(node);
        } else if (std.mem.eql(u8, ntype, "eq_decl")) {
            return self.buildEqDecl(node);
        } else if (std.mem.eql(u8, ntype, "assign")) {
            return self.buildAssign(node);
        } else if (std.mem.eql(u8, ntype, "prove_decl") or
                   std.mem.eql(u8, ntype, "skill_decl")) {
            // Nœuds top-level sans sémantique dans ast_bridge : juste un symbole.
            return self.store.sym(ntype);
        } else if (std.mem.eql(u8, ntype, "comment")) {
            return expr.NULL;
        } else {
            // Fallback : ne PAS stocker de `sym(ntype)` (faux positifs
            // pour unbound_check : import_decl, eq_decl non gérés).
            return expr.NULL;
        }
    }

    fn buildFnDecl(self: *Bridge, node: ts.TSNode) anyerror!Id {
        const name = self.getFieldText(node, "name") orelse "anonymous";
        var param_names = std.ArrayListUnmanaged([]const u8){};
        defer param_names.deinit(self.allocator);

        const count = ts.ts_node_child_count(node);
        var i: u32 = 0;
        var body_id: Id = expr.NULL;
        var after_eq: bool = false;
        while (i < count) : (i += 1) {
            const child = ts.ts_node_child(node, i);
            const ct = self.nodeType(child);
            if (std.mem.eql(u8, ct, "params")) {
                try self.collectParams(child, &param_names);
            } else if (std.mem.eql(u8, ct, "block")) {
                try self.scope.push(name);
                for (param_names.items) |p| {
                    try self.scope.define(p, .{ .type_name = "?", .kind = .variable });
                }
                body_id = try self.buildBlock(child);
                self.scope.pop();
            } else if (std.mem.eql(u8, ct, "=")) {
                after_eq = true;
            } else if (after_eq and body_id == expr.NULL) {
                // Forme `fn name(params) = expr`
                try self.scope.push(name);
                for (param_names.items) |p| {
                    try self.scope.define(p, .{ .type_name = "?", .kind = .variable });
                }
                body_id = try self.buildExpr(child);
                self.scope.pop();
            }
        }

        const fn_id = try self.store.lambda(param_names.items, body_id);
        const bind_id = try self.store.bind(name, fn_id);
        try self.scope.define(name, .{ .type_name = "fn", .expr_id = fn_id, .kind = .function });
        return bind_id;
    }

    fn buildVarDecl(self: *Bridge, node: ts.TSNode) anyerror!Id {
        const name = self.getFieldText(node, "name") orelse "_";
        var value_id: Id = expr.NULL;
        const count = ts.ts_node_child_count(node);
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const child = ts.ts_node_child(node, i);
            const ct = self.nodeType(child);
            if (!std.mem.eql(u8, ct, "identifier") and
                !std.mem.eql(u8, ct, "let") and
                !std.mem.eql(u8, ct, "var") and
                !std.mem.eql(u8, ct, "const") and
                !std.mem.eql(u8, ct, "mut") and
                !std.mem.eql(u8, ct, "prim_type") and
                !std.mem.eql(u8, ct, "="))
            {
                value_id = try self.buildExpr(child);
            }
        }
        const bind_id = try self.store.bind(name, value_id);
        try self.scope.define(name, .{ .type_name = "?", .expr_id = value_id, .kind = .variable });
        return bind_id;
    }

    fn buildStructDecl(self: *Bridge, node: ts.TSNode) anyerror!Id {
        const name = self.getFieldText(node, "name") orelse "Struct";
        try self.scope.define(name, .{ .type_name = "Type", .kind = .type_decl });
        return self.store.sym(name);
    }

    fn buildEnumDecl(self: *Bridge, node: ts.TSNode) anyerror!Id {
        const name = self.getFieldText(node, "name") orelse "Enum";
        try self.scope.define(name, .{ .type_name = "Type", .kind = .type_decl });
        return self.store.sym(name);
    }

    fn buildNamedDecl(self: *Bridge, node: ts.TSNode, kind: []const u8) anyerror!Id {
        const name = self.getFieldText(node, "name") orelse kind;
        try self.scope.define(name, .{ .type_name = kind, .kind = .type_decl });
        return self.store.sym(name);
    }

    fn buildTestDecl(self: *Bridge, node: ts.TSNode) anyerror!Id {
        const name = self.getFieldText(node, "name") orelse "test";
        const sym = try self.store.interner.intern(name);
        const lit_id = try self.store.lit(.{ .str = sym });
        return self.store.call("__test", &.{lit_id});
    }

    fn buildSigDecl(self: *Bridge, node: ts.TSNode) anyerror!Id {
        const name = self.getFieldText(node, "name") orelse "_";
        try self.scope.define(name, .{ .type_name = "sig", .kind = .function });
        return self.store.sym(name);
    }

    fn buildEqDecl(self: *Bridge, node: ts.TSNode) anyerror!Id {
        // Syntaxe: add x y = x + y
        //   children: identifier 'add', pattern 'x', pattern 'y', '=', binary
        const name = self.getFieldText(node, "name") orelse blk: {
            // fallback : premier identifier enfant
            const c = ts.ts_node_child_count(node);
            var k: u32 = 0;
            while (k < c) : (k += 1) {
                const ch = ts.ts_node_child(node, k);
                if (std.mem.eql(u8, self.nodeType(ch), "identifier")) {
                    break :blk self.nodeText(ch);
                }
            }
            break :blk "_";
        };

        var param_names = std.ArrayListUnmanaged([]const u8){};
        defer param_names.deinit(self.allocator);

        var body_id: Id = expr.NULL;
        var seen_eq = false;
        const count = ts.ts_node_child_count(node);
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const child = ts.ts_node_child(node, i);
            const ct = self.nodeType(child);
            if (std.mem.eql(u8, ct, "pattern")) {
                // pattern simple ('x', 'y') est terminal : pas d'enfant,
                // le texte est directement le nom du paramètre.
                try param_names.append(self.allocator, self.nodeText(child));
            } else if (std.mem.eql(u8, ct, "=")) {
                seen_eq = true;
            } else if (std.mem.eql(u8, ct, "identifier")) {
                // skip : c'est le nom, déjà lu
            } else if (seen_eq) {
                body_id = try self.buildExpr(child);
            }
        }

        if (body_id == expr.NULL) {
            return self.store.sym("eq_decl");
        }

        const fn_id = try self.store.lambda(param_names.items, body_id);
        const bind_id = try self.store.bind(name, fn_id);
        try self.scope.define(name, .{ .type_name = "fn", .expr_id = fn_id, .kind = .function });
        return bind_id;
    }

    fn buildBlock(self: *Bridge, node: ts.TSNode) anyerror!Id {
        const count = ts.ts_node_child_count(node);
        var last_id: Id = try self.store.lit(.unit);
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const child = ts.ts_node_child(node, i);
            const ct = self.nodeType(child);
            if (std.mem.eql(u8, ct, "{") or std.mem.eql(u8, ct, "}") or std.mem.eql(u8, ct, ";")) continue;
            last_id = try self.buildStmt(child);
        }
        return last_id;
    }

    fn buildStmt(self: *Bridge, node: ts.TSNode) anyerror!Id {
        const ntype = self.nodeType(node);
        if (std.mem.eql(u8, ntype, "var_decl")) {
            return self.buildVarDecl(node);
        } else if (std.mem.eql(u8, ntype, "ret")) {
            return self.buildReturn(node);
        } else if (std.mem.eql(u8, ntype, "assign")) {
            return self.buildAssign(node);
        } else if (std.mem.eql(u8, ntype, "if_stmt")) {
            return self.buildExpr(node);
        } else if (std.mem.eql(u8, ntype, "for_stmt")) {
            return self.buildExpr(node);
        } else if (std.mem.eql(u8, ntype, "comment")) {
            return expr.NULL;
        } else {
            return self.buildExpr(node);
        }
    }

    fn buildReturn(self: *Bridge, node: ts.TSNode) anyerror!Id {
        const count = ts.ts_node_child_count(node);
        if (count >= 2) {
            const val = ts.ts_node_child(node, 1);
            return self.buildExpr(val);
        }
        return self.store.lit(.unit);
    }

    fn buildAssign(self: *Bridge, node: ts.TSNode) anyerror!Id {
        const count = ts.ts_node_child_count(node);
        if (count < 3) return expr.NULL;

        const name = self.nodeText(ts.ts_node_child(node, 0));

        // Trouver l'index de '=' (normalement 1, mais robuste).
        var eq_idx: u32 = 2;
        var k: u32 = 0;
        while (k < count) : (k += 1) {
            if (std.mem.eql(u8, self.nodeType(ts.ts_node_child(node, k)), "=")) {
                eq_idx = k;
                break;
            }
        }

        // Collecter toutes les expressions après '=' (skip ';' et ',').
        // Syntaxe applicative Heaven : 'add 1' -> tree-sitter produit une
        // sequence plate [add, 1], PAS un noeud 'call'. On reconstruit
        // l'application manuellement.
        var expr_ids = std.ArrayListUnmanaged(Id){};
        defer expr_ids.deinit(self.allocator);
        var i: u32 = eq_idx + 1;
        while (i < count) : (i += 1) {
            const child = ts.ts_node_child(node, i);
            const ct = self.nodeType(child);
            if (std.mem.eql(u8, ct, ";") or std.mem.eql(u8, ct, ",")) continue;
            try expr_ids.append(self.allocator, try self.buildExpr(child));
        }

        if (expr_ids.items.len == 0) return expr.NULL;

        const val_id: Id = if (expr_ids.items.len == 1)
            expr_ids.items[0]
        else
            try self.store.apply(expr_ids.items[0], expr_ids.items[1..]);

        return self.store.bind(name, val_id);
    }

    pub fn buildExpr(self: *Bridge, node: ts.TSNode) anyerror!Id {
        const ntype = self.nodeType(node);

        if (std.mem.eql(u8, ntype, "int")) {
            const text = self.nodeText(node);
            const val = std.fmt.parseInt(i64, text, 10) catch 0;
            return self.store.int(val);
        } else if (std.mem.eql(u8, ntype, "float")) {
            const text = self.nodeText(node);
            const val = std.fmt.parseFloat(f64, text) catch 0.0;
            return self.store.float(val);
        } else if (std.mem.eql(u8, ntype, "str")) {
            const text = self.nodeText(node);
            return self.store.lit(.{ .str = try self.store.interner.intern(text) });
        } else if (std.mem.eql(u8, ntype, "bool_lit")) {
            const text = self.nodeText(node);
            return self.store.boolean(std.mem.eql(u8, text, "true"));
        } else if (std.mem.eql(u8, ntype, "identifier")) {
            const name = self.nodeText(node);
            return self.store.sym(name);
        } else if (std.mem.eql(u8, ntype, "type_name")) {
            return self.store.sym(self.nodeText(node));
        } else if (std.mem.eql(u8, ntype, "binary")) {
            return self.buildBinary(node);
        } else if (std.mem.eql(u8, ntype, "call") or std.mem.eql(u8, ntype, "app_expr")) {
            return self.buildCall(node);
        } else if (std.mem.eql(u8, ntype, "simple_expr")) {
            // simple_expr est un wrapper transparent : descendre sur son premier enfant
            const cc = ts.ts_node_child_count(node);
            if (cc > 0) return self.buildExpr(ts.ts_node_child(node, 0));
            return expr.NULL;
        } else if (std.mem.eql(u8, ntype, "block")) {
            return self.buildBlock(node);
        } else if (std.mem.eql(u8, ntype, "lambda")) {
            return self.buildLambda(node);
        } else if (std.mem.eql(u8, ntype, "atom")) {
            return self.store.sym(self.nodeText(node));
        } else if (std.mem.eql(u8, ntype, "arr")) {
            return self.buildArray(node);
        } else if (std.mem.eql(u8, ntype, "if_expr")) {
            return self.buildIfExpr(node);
        } else if (std.mem.eql(u8, ntype, "paren_expr")) {
            if (ts.ts_node_child_count(node) >= 2) {
                return self.buildExpr(ts.ts_node_child(node, 1));
            }
            return expr.NULL;
        } else {
            return self.store.sym(ntype);
        }
    }

    fn buildBinary(self: *Bridge, node: ts.TSNode) anyerror!Id {
        const count = ts.ts_node_child_count(node);
        if (count >= 3) {
            const left = try self.buildExpr(ts.ts_node_child(node, 0));
            const op_text = self.nodeText(ts.ts_node_child(node, 1));
            const right = try self.buildExpr(ts.ts_node_child(node, 2));
            const op = try self.store.sym(op_text);
            return self.store.apply(op, &.{ left, right });
        }
        return expr.NULL;
    }

    fn buildCall(self: *Bridge, node: ts.TSNode) anyerror!Id {
        var args = std.ArrayListUnmanaged(Id){};
        defer args.deinit(self.allocator);
        var func_id: Id = expr.NULL;
        const count = ts.ts_node_child_count(node);
        var i: u32 = 0;
        var first_expr = true;
        while (i < count) : (i += 1) {
            const child = ts.ts_node_child(node, i);
            const ct = self.nodeType(child);
            if (std.mem.eql(u8, ct, "(") or std.mem.eql(u8, ct, ")") or std.mem.eql(u8, ct, ",")) continue;
            const id = try self.buildExpr(child);
            if (first_expr) {
                func_id = id;
                first_expr = false;
            } else {
                try args.append(self.allocator, id);
            }
        }
        return self.store.apply(func_id, args.items);
    }

    fn buildLambda(self: *Bridge, node: ts.TSNode) anyerror!Id {
        var param_names = std.ArrayListUnmanaged([]const u8){};
        defer param_names.deinit(self.allocator);
        var body_id: Id = expr.NULL;
        const count = ts.ts_node_child_count(node);
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const child = ts.ts_node_child(node, i);
            const ct = self.nodeType(child);
            if (std.mem.eql(u8, ct, "identifier")) {
                try param_names.append(self.allocator, self.nodeText(child));
            } else if (std.mem.eql(u8, ct, "param")) {
                try self.collectSingleParam(child, &param_names);
            }
        }

        try self.scope.push("<lambda>");
        for (param_names.items) |p| {
            try self.scope.define(p, .{ .type_name = "?", .kind = .variable });
        }

        i = 0;
        while (i < count) : (i += 1) {
            const child = ts.ts_node_child(node, i);
            const ct = self.nodeType(child);
            if (std.mem.eql(u8, ct, "block") or std.mem.eql(u8, ct, "binary")) {
                body_id = try self.buildExpr(child);
            }
        }

        self.scope.pop();

        return self.store.lambda(param_names.items, body_id);
    }

    fn buildArray(self: *Bridge, node: ts.TSNode) anyerror!Id {
        var elems = std.ArrayListUnmanaged(Id){};
        defer elems.deinit(self.allocator);
        const count = ts.ts_node_child_count(node);
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const child = ts.ts_node_child(node, i);
            const ct = self.nodeType(child);
            if (std.mem.eql(u8, ct, "[") or std.mem.eql(u8, ct, "]") or std.mem.eql(u8, ct, ",")) continue;
            try elems.append(self.allocator, try self.buildExpr(child));
        }
        const list_sym = try self.store.sym("__list");
        return self.store.apply(list_sym, elems.items);
    }

    fn buildIfExpr(self: *Bridge, node: ts.TSNode) anyerror!Id {
        // Filtre les tokens de structure : `(`, `)`, `if`, `then`, `else`.
        // Prend les 3 expressions restantes dans l'ordre (S-expr ou classique).
        var vals: [3]Id = .{ expr.NULL, expr.NULL, expr.NULL };
        var idx: usize = 0;
        const count = ts.ts_node_child_count(node);
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const child = ts.ts_node_child(node, i);
            const ct = self.nodeType(child);
            if (std.mem.eql(u8, ct, "(") or std.mem.eql(u8, ct, ")") or
                std.mem.eql(u8, ct, "if") or std.mem.eql(u8, ct, "then") or
                std.mem.eql(u8, ct, "else")) continue;
            if (idx < 3) {
                vals[idx] = try self.buildExpr(child);
                idx += 1;
            }
        }
        const if_sym = try self.store.sym("if");
        return self.store.apply(if_sym, &vals);
    }

    fn collectParams(self: *Bridge, node: ts.TSNode, names: *std.ArrayListUnmanaged([]const u8)) !void {
        const count = ts.ts_node_child_count(node);
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const child = ts.ts_node_child(node, i);
            if (std.mem.eql(u8, self.nodeType(child), "param")) {
                try self.collectSingleParam(child, names);
            }
        }
    }

    fn collectSingleParam(self: *Bridge, node: ts.TSNode, names: *std.ArrayListUnmanaged([]const u8)) !void {
        const count = ts.ts_node_child_count(node);
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const child = ts.ts_node_child(node, i);
            const ct = self.nodeType(child);
            if (std.mem.eql(u8, ct, "identifier") or std.mem.eql(u8, ct, "type_name")) {
                try names.append(self.allocator, self.nodeText(child));
                return;
            } else if (std.mem.eql(u8, ct, "self")) {
                try names.append(self.allocator, "self");
                return;
            }
        }
    }

    fn nodeType(self: *Bridge, node: ts.TSNode) []const u8 {
        _ = self;
        return std.mem.span(ts.ts_node_type(node));
    }

    fn nodeText(self: *Bridge, node: ts.TSNode) []const u8 {
        const start = ts.ts_node_start_byte(node);
        const end = ts.ts_node_end_byte(node);
        return self.source[start..end];
    }

    fn getFieldText(self: *Bridge, node: ts.TSNode, field: []const u8) ?[]const u8 {
        const child = ts.ts_node_child_by_field_name(node, field.ptr, @intCast(field.len));
        if (ts.ts_node_is_null(child)) return null;
        return self.nodeText(child);
    }

    fn dumpTree(self: *Bridge, node: ts.TSNode, depth: usize) void {
        // debug only, désactivé 2026-11-05 (P2-bis)
        _ = self; _ = node; _ = depth;
    }
};
