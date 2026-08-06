const std = @import("std");
const matrix_lib = @import("matrix_lib");
const platform = @import("platform");
const ts = platform.ts;
const norm = @import("ts_normalize.zig");

const IngestError = error{
    ParseFailed,
    TSCursorFailed,
    QueryCompilationFailed,
    OutOfMemory,
    LanguageNotFound,
};

/// Ingesteur universel Tree-sitter — Green & Fast
/// - Zero-copy parsing (slices directes du source)
/// - Interning agressif des symboles
/// - Arena allocator pour les temporaires
/// - Support multi-langage (Heaven, Zig, C, Pie, etc.)
pub const UniversalIngestor = struct {
    matrix: *matrix_lib.Matrix,
    allocator: std.mem.Allocator,
    parser: *ts.TSParser,
    arena: std.heap.ArenaAllocator,

    // ─── Lifecycle ────────────────────────────────────────────

    pub fn init(allocator: std.mem.Allocator, matrix: *matrix_lib.Matrix) !UniversalIngestor {
        const parser = ts.ts_parser_new() orelse return error.ParseFailed;
        return .{
            .matrix = matrix,
            .allocator = allocator,
            .parser = parser,
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *UniversalIngestor) void {
        ts.ts_parser_delete(self.parser);
        self.arena.deinit();
    }

    // ─── Points d'entrée publics ──────────────────────────────

    pub fn ingest(self: *UniversalIngestor, file_path: []const u8, content: []const u8) !void {
        platform.debug.print("[INGEST] fichier={s}\n", .{file_path});
        const lang_name = self.getLanguageFromExt(file_path) orelse {
            platform.debug.print("[FORGE] Extension non reconnue: {s}\n", .{file_path});
            return error.LanguageNotFound;
        };

        const ts_lang = self.getTSLanguage(lang_name);
        const ok = ts.ts_parser_set_language(self.parser, @ptrCast(ts_lang));
        if (!ok) platform.debug.print("[FORGE] ERREUR: set_language ECHEC!\n", .{});

        const tree = ts.ts_parser_parse_string(self.parser, null, content.ptr, @intCast(content.len));
        if (tree == null) return error.ParseFailed;
        defer ts.ts_tree_delete(tree);

        const root = ts.ts_tree_root_node(tree);

        // Phase 1 : Queries sémantiques (optionnel, non-bloquant)
        self.runQueries(root, content, lang_name) catch {};

        // Phase 2 : Traversée IR récursive
        platform.debug.print("[DIAG] lang={s} children={d}\n", .{ lang_name, ts.ts_node_named_child_count(root) });
        var di: u32 = 0;
        while (di < @min(ts.ts_node_named_child_count(root), 5)) : (di += 1) {
            const dc = ts.ts_node_named_child(root, di);
            const dt = ts.ts_node_type(dc);
            if (dt != null) platform.debug.print("[DIAG]   child[{d}]: {s}\n", .{ di, std.mem.span(dt) });
        }
        _ = try self.traverseToIR(root, content);

        // GREEN : Libérer toutes les allocations temporaires d'un coup
        _ = self.arena.reset(.retain_capacity);

        platform.debug.print("[FORGE] ✓ {s} ({s}) → {d} nœuds\n", .{
            file_path,
            lang_name,
            self.matrix.nodes.count(),
        });
    }

    /// Variante pour le REPL
    pub fn ingestSource(self: *UniversalIngestor, content: []const u8) !void {
        return self.ingest("repl.hvn", content);
    }

    // ═══════════════════════════════════════════════════════════
    // TRAVERSÉE IR — Cœur universel
    // ═══════════════════════════════════════════════════════════

    fn traverseToIR(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) IngestError!matrix_lib.BobId {
        if (ts.ts_node_is_null(node)) return 0;
        if (ts.ts_node_is_error(node) or ts.ts_node_is_missing(node)) return 0;

        const ntype_ptr = ts.ts_node_type(node);
        if (ntype_ptr == null) return 0;
        const ntype = std.mem.span(ntype_ptr);
        const kind = norm.classifyNode(ntype);

        const start = ts.ts_node_start_byte(node);
        const end = ts.ts_node_end_byte(node);
        if (start > end or end > source.len) return 0;
        const content = source[start..end];

        return switch (kind) {
            .Function => self.buildFunction(node, source),
            .Call => self.buildCall(node, source),
            .Return => self.buildReturn(node, source),
            .BinOp => self.buildBinOp(node, source),
            .If => self.buildIf(node, source),
            .Loop => self.buildLoop(node, source),
            .VarDecl => self.buildVarDecl(node, source),
            .Assign => self.buildAssign(node, source),
            .StructDecl => self.buildStructDecl(node, source),
            .EnumDecl => self.buildEnumDecl(node, source),
            .ImplBlock => self.buildImplBlock(node, source),
            .EffectDecl => self.buildEffectDecl(node, source),
            .FactDecl => self.buildFactDecl(node, source),
            .RuleDecl => self.buildRuleDecl(node, source),
            .QueryExpr => self.buildQuery(node, source),
            .ActorDecl => self.buildActor(node, source),
            .SpawnExpr => self.buildSpawn(node, source),
            .SendExpr => self.buildSend(node, source),
            .MatchExpr => self.buildMatch(node, source),
            .Lambda => self.buildLambda(node, source),
            .Quote => self.buildQuote(node, source),
            .Unquote => self.buildUnquote(node, source),
            .PipeExpr => self.buildPipe(node, source),
            .RangeExpr => self.buildRange(node, source),
            .HandleExpr => self.buildHandle(node, source),
            .FieldAccess => self.buildFieldAccess(node, source),
            .IndexExpr => self.buildIndex(node, source),
            .Block => self.buildBlock(node, source),
            .LiteralInt => self.matrix.addNode(.{
                .HIntLit = std.fmt.parseInt(i64, content, 10) catch 0,
            }),
            .LiteralFloat => self.matrix.addNode(.{
                .HFloatLit = std.fmt.parseFloat(f64, content) catch 0.0,
            }),
            .LiteralString => blk: {
                const clean = if (content.len >= 2 and content[0] == '"')
                    content[1 .. content.len - 1]
                else
                    content;
                break :blk self.matrix.addNode(.{ .HStringLit = clean });
            },
            .LiteralBool => self.matrix.addNode(.{
                .HBoolLit = std.mem.eql(u8, content, "true"),
            }),
            .Identifier, .TypeName => self.matrix.addUniqueSymbol(content),
            .Unknown => self.buildFallbackBlock(node, source),
            .SigDecl => self.buildSigDecl(node, source),
            .EqDecl => self.buildEqDecl(node, source),
        };
    }

    // ═══════════════════════════════════════════════════════════
    // BUILDERS — Déclarations
    // ═══════════════════════════════════════════════════════════

    fn buildFunction(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) !matrix_lib.BobId {
        const name_id = try self.captureFieldAsSymbol(node, "name", source);
        const body_node = ts.ts_node_child_by_field_name(node, "body", 4);

        // Paramètres
        var params = std.ArrayListUnmanaged(matrix_lib.BobId){};
        const params_node = ts.ts_node_child_by_field_name(node, "params", 6);

        if (!ts.ts_node_is_null(params_node)) {
            var i: u32 = 0;
            const count = ts.ts_node_named_child_count(params_node);
            while (i < count) : (i += 1) { // Assure-toi d'avoir le "<" et le ": (i += 1)"
                const child = ts.ts_node_named_child(params_node, i);
                try params.append(self.arena.allocator(), try self.traverseToIR(child, source));
            }
        }

        const body_id = if (!ts.ts_node_is_null(body_node))
            try self.traverseToIR(body_node, source)
        else
            try self.matrix.addNode(.{ .HBlock = &[_]matrix_lib.BobId{} });

        return self.matrix.addNode(.{
            .HFunc = .{
                .name = name_id,
                .params = try params.toOwnedSlice(self.arena.allocator()),
                .ret_type = null,
                .body = body_id,
            },
        });
    }

    fn buildSigDecl(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) !matrix_lib.BobId {
        // Extraire le nom (champ "name")
        const name_id = try self.captureFieldAsSymbol(node, "name", source);
        if (name_id == 0) return 0;

        // Extraire le type complet (tout après le ':')
        // On prend le texte brut du nœud type
        const nc = ts.ts_node_named_child_count(node);
        var type_text: []const u8 = "unknown";

        // Parcourir les enfants pour trouver le type (après ':')
        var i: u32 = 0;
        while (i < nc) : (i += 1) {
            const child = ts.ts_node_named_child(node, i);
            const child_type_ptr = ts.ts_node_type(child);
            if (child_type_ptr == null) continue;
            const child_type = std.mem.span(child_type_ptr);

            // Le type est l'enfant qui n'est pas le nom (arrow_type, prim_type, type_ident, etc.)
            if (std.mem.indexOf(u8, child_type, "type") != null or
                std.mem.eql(u8, child_type, "arrow_type"))
            {
                const node_start = ts.ts_node_start_byte(child);
                const node_end = ts.ts_node_end_byte(child);
                if (node_start < node_end and node_end <= source.len) {
                    type_text = source[node_start..node_end];
                }
            }
        }

        // Stocker comme symbole SIG:name=type
        var sig_buf: [256]u8 = undefined;
        const name_start = ts.ts_node_start_byte(ts.ts_node_child_by_field_name(node, "name", 4));
        const name_end = ts.ts_node_end_byte(ts.ts_node_child_by_field_name(node, "name", 4));
        const name_text = source[name_start..name_end];

        const sig_label = std.fmt.bufPrint(&sig_buf, "SIG:{s}={s}", .{ name_text, type_text }) catch "SIG:?";
        const sig_id = try self.matrix.addUniqueSymbol(sig_label);

        // Créer une arête SIG entre le nom et la signature
        _ = try self.matrix.addEdge(name_id, sig_id, "HAS_TYPE");

        return name_id;
    }

    fn buildEqDecl(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) !matrix_lib.BobId {
        const name_id = try self.captureFieldAsSymbol(node, "name", source);
        if (name_id == 0) return 0;

        var params = std.ArrayListUnmanaged(matrix_lib.BobId){};
        var body_id: matrix_lib.BobId = 0;

        const nc = ts.ts_node_named_child_count(node);
        var found_eq = false;
        var i: u32 = 0;

        while (i < nc) : (i += 1) {
            const child = ts.ts_node_named_child(node, i);
            if (ts.ts_node_is_null(child)) continue;

            const child_type_ptr = ts.ts_node_type(child);
            if (child_type_ptr == null) continue;
            const child_type = std.mem.span(child_type_ptr);

            // Le nom est déjà capturé via field("name")
            // Les patterns sont des enfants "pattern" ou "identifier" AVANT le '='
            if (!found_eq) {
                // Vérifier si c'est le signe '=' ou '≔' (noeud anonyme, pas named)
                // Les named children avant le body sont les patterns
                if (std.mem.eql(u8, child_type, "pattern") or
                    std.mem.eql(u8, child_type, "identifier"))
                {
                    // Ignorer le premier identifier (c'est le nom de la fonction)
                    const cs = ts.ts_node_start_byte(child);
                    const ce = ts.ts_node_end_byte(child);
                    const child_text = source[cs..ce];
                    _ = child_text;

                    // Vérifier que ce n'est pas le nom de la fonction
                    const name_node = ts.ts_node_child_by_field_name(node, "name", 4);
                    if (!ts.ts_node_is_null(name_node)) {
                        const ns = ts.ts_node_start_byte(name_node);
                        const ne = ts.ts_node_end_byte(name_node);
                        if (cs == ns and ce == ne) {
                            continue; // Skip le nom lui-même
                        }
                    }

                    const param_id = try self.traverseToIR(child, source);
                    if (param_id != 0) try params.append(self.arena.allocator(), param_id);
                } else {
                    // C'est le corps (expression après '=')
                    found_eq = true;
                    body_id = try self.traverseToIR(child, source);
                }
            } else {
                // Après le premier non-pattern, tout est le body
                // (ne devrait pas arriver si la grammaire est correcte)
                body_id = try self.traverseToIR(child, source);
            }
        }

        return self.matrix.addNode(.{
            .HFunc = .{
                .name = name_id,
                .params = try params.toOwnedSlice(self.arena.allocator()),
                .ret_type = null,
                .body = body_id,
            },
        });
    }

    fn buildVarDecl(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) !matrix_lib.BobId {
        const name_id = try self.captureFieldAsSymbol(node, "name", source);
        const value_node = ts.ts_node_child_by_field_name(node, "value", 5);
        const value_id = if (!ts.ts_node_is_null(value_node)) try self.traverseToIR(value_node, source) else 0;

        return self.matrix.addNode(.{
            .Let = .{ .name = name_id, .value = value_id, .body = 0 },
        });
    }

    fn buildBlock(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) !matrix_lib.BobId {
        var stmts = std.ArrayListUnmanaged(matrix_lib.BobId){};
        var i: u32 = 0;
        const count = ts.ts_node_named_child_count(node);
        while (i < count) : (i += 1) {
            const child = ts.ts_node_named_child(node, i);
            try stmts.append(self.arena.allocator(), try self.traverseToIR(child, source));
        }
        return self.matrix.addNode(.{
            .HBlock = try stmts.toOwnedSlice(self.arena.allocator()),
        });
    }

    // Rediriger les implémentations complexes non encore vitales vers le fallback
    fn buildStructDecl(self: *UniversalIngestor, n: ts.TSNode, s: []const u8) !matrix_lib.BobId {
        return self.buildFallbackBlock(n, s);
    }
    fn buildEnumDecl(self: *UniversalIngestor, n: ts.TSNode, s: []const u8) !matrix_lib.BobId {
        return self.buildFallbackBlock(n, s);
    }
    fn buildImplBlock(self: *UniversalIngestor, n: ts.TSNode, s: []const u8) !matrix_lib.BobId {
        return self.buildFallbackBlock(n, s);
    }
    fn buildEffectDecl(self: *UniversalIngestor, n: ts.TSNode, s: []const u8) !matrix_lib.BobId {
        return self.buildFallbackBlock(n, s);
    }
    //fn buildFact(self: *UniversalIngestor, n: ts.TSNode, s: []const u8) !matrix_lib.BobId { return self.buildFallbackBlock(n, s); }
    //fn buildRule(self: *UniversalIngestor, n: ts.TSNode, s: []const u8) !matrix_lib.BobId { return self.buildFallbackBlock(n, s); }
    fn buildQuery(self: *UniversalIngestor, n: ts.TSNode, s: []const u8) !matrix_lib.BobId {
        return self.buildFallbackBlock(n, s);
    }
    fn buildActor(self: *UniversalIngestor, n: ts.TSNode, s: []const u8) !matrix_lib.BobId {
        return self.buildFallbackBlock(n, s);
    }
    fn buildSpawn(self: *UniversalIngestor, n: ts.TSNode, s: []const u8) !matrix_lib.BobId {
        return self.buildFallbackBlock(n, s);
    }
    fn buildSend(self: *UniversalIngestor, n: ts.TSNode, s: []const u8) !matrix_lib.BobId {
        return self.buildFallbackBlock(n, s);
    }
    fn buildLambda(self: *UniversalIngestor, n: ts.TSNode, s: []const u8) !matrix_lib.BobId {
        return self.buildFallbackBlock(n, s);
    }

    fn buildQuote(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) !matrix_lib.BobId {
        // quote expr ou 'expr : un seul enfant qui est l'expression quotée
        const child = ts.ts_node_named_child(node, 0);
        const child_id = if (!ts.ts_node_is_null(child)) try self.traverseToIR(child, source) else 0;
        return self.matrix.addNode(.{ .HQuote = .{ .expr = child_id } });
    }

    fn buildUnquote(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) !matrix_lib.BobId {
        // unquote expr ou ,expr : un seul enfant qui est l'expression unquotée
        const child = ts.ts_node_named_child(node, 0);
        const child_id = if (!ts.ts_node_is_null(child)) try self.traverseToIR(child, source) else 0;
        return self.matrix.addNode(.{ .HUnquote = .{ .expr = child_id } });
    }
    fn buildPipe(self: *UniversalIngestor, n: ts.TSNode, s: []const u8) !matrix_lib.BobId {
        return self.buildFallbackBlock(n, s);
    }
    fn buildRange(self: *UniversalIngestor, n: ts.TSNode, s: []const u8) !matrix_lib.BobId {
        return self.buildFallbackBlock(n, s);
    }
    fn buildHandle(self: *UniversalIngestor, n: ts.TSNode, s: []const u8) !matrix_lib.BobId {
        return self.buildFallbackBlock(n, s);
    }
    fn buildFieldAccess(self: *UniversalIngestor, n: ts.TSNode, s: []const u8) !matrix_lib.BobId {
        return self.buildFallbackBlock(n, s);
    }
    fn buildIndex(self: *UniversalIngestor, n: ts.TSNode, s: []const u8) !matrix_lib.BobId {
        return self.buildFallbackBlock(n, s);
    }

    fn buildAssign(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) !matrix_lib.BobId {
        const left = ts.ts_node_named_child(node, 0);
        const right = ts.ts_node_named_child(node, 1);
        const leftid = if (!ts.ts_node_is_null(left)) try self.traverseToIR(left, source) else 0;
        const rightid = if (!ts.ts_node_is_null(right)) try self.traverseToIR(right, source) else 0;
        return self.matrix.addNode(.{
            .HAssign = .{ .target = leftid, .value = rightid },
        });
    }

    fn buildReturn(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) !matrix_lib.BobId {
        const nc = ts.ts_node_named_child_count(node);
        const val_id: ?matrix_lib.BobId = if (nc > 0) blk: {
            const child = ts.ts_node_named_child(node, 0);
            break :blk if (!ts.ts_node_is_null(child)) try self.traverseToIR(child, source) else null;
        } else null;
        return self.matrix.addNode(.{ .HReturn = .{ .value = val_id } });
    }

    fn buildBinOp(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) !matrix_lib.BobId {
        // Named children : seulement left et right (l'opérateur est anonyme)
        const left_node = ts.ts_node_named_child(node, 0);
        const right_node = ts.ts_node_named_child(node, 1);

        const left_id = if (!ts.ts_node_is_null(left_node)) try self.traverseToIR(left_node, source) else 0;
        const right_id = if (!ts.ts_node_is_null(right_node)) try self.traverseToIR(right_node, source) else 0;

        // L'opérateur est entre left et right dans les children TOTAUX (pas named)
        // On le trouve en scannant tous les children
        var op_str: []const u8 = "+";
        const total_children = ts.ts_node_child_count(node);
        var ci: u32 = 0;
        while (ci < total_children) : (ci += 1) {
            const child = ts.ts_node_child(node, ci);
            if (!ts.ts_node_is_named(child)) {
                const cs = ts.ts_node_start_byte(child);
                const ce = ts.ts_node_end_byte(child);
                if (cs < ce and ce <= source.len) {
                    const text = source[cs..ce];
                    // Vérifier que c'est un opérateur (pas une parenthèse)
                    if (text.len > 0 and text[0] != '(' and text[0] != ')') {
                        op_str = text;
                        break;
                    }
                }
            }
        }

        return self.matrix.addNode(.{
            .HBinOp = .{
                .left = left_id,
                .op = classifyOp(op_str),
                .right = right_id,
            },
        });
    }

    fn buildIf(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) !matrix_lib.BobId {
        const nc = ts.ts_node_named_child_count(node);
        const cond_node = ts.ts_node_named_child(node, 0);
        const then_node = if (nc > 1) ts.ts_node_named_child(node, 1) else cond_node;

        const cond_id = if (!ts.ts_node_is_null(cond_node)) try self.traverseToIR(cond_node, source) else 0;
        const then_id = if (!ts.ts_node_is_null(then_node)) try self.traverseToIR(then_node, source) else 0;
        const else_id: ?matrix_lib.BobId = if (nc > 2) blk: {
            const else_node = ts.ts_node_named_child(node, 2);
            break :blk if (!ts.ts_node_is_null(else_node)) try self.traverseToIR(else_node, source) else null;
        } else null;

        return self.matrix.addNode(.{
            .HIf = .{ .condition = cond_id, .then_body = then_id, .else_body = else_id },
        });
    }

    fn buildLoop(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) !matrix_lib.BobId {
        const nc = ts.ts_node_named_child_count(node);
        const cond_node = ts.ts_node_named_child(node, 0);

        const cond_id = if (!ts.ts_node_is_null(cond_node))
            try self.traverseToIR(cond_node, source)
        else
            try self.matrix.addNode(.{ .HBoolLit = true });

        const body_node = if (nc > 1) ts.ts_node_named_child(node, 1) else cond_node;
        const body_id = if (!ts.ts_node_is_null(body_node))
            try self.traverseToIR(body_node, source)
        else
            try self.matrix.addNode(.{ .HBlock = &[_]matrix_lib.BobId{} });

        return self.matrix.addNode(.{
            .HWhile = .{ .condition = cond_id, .body = body_id },
        });
    }

    fn buildMatch(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) !matrix_lib.BobId {
        return self.buildFallbackBlock(node, source);
    }

    // ═══════════════════════════════════════════════════════════
    // BUILDERS — Expressions
    // ═══════════════════════════════════════════════════════════

    fn buildCall(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) !matrix_lib.BobId {
        const func_node = ts.ts_node_named_child(node, 0);
        const func_id = if (!ts.ts_node_is_null(func_node))
            try self.traverseToIR(func_node, source)
        else
            0;

        var args = std.ArrayListUnmanaged(matrix_lib.BobId){};
        var i: u32 = 1;
        const count = ts.ts_node_named_child_count(node);
        while (i < count) : (i += 1) {
            const child = ts.ts_node_named_child(node, i);
            try args.append(self.arena.allocator(), try self.traverseToIR(child, source));
        }

        return self.matrix.addNode(.{
            .HCall = .{
                .callee = func_id,
                .args = try args.toOwnedSlice(self.arena.allocator()),
            },
        });
    }

    fn captureFieldOrFallback(self: *UniversalIngestor, node: ts.TSNode, field: []const u8, source: []const u8) !matrix_lib.BobId {
        const field_node = ts.ts_node_child_by_field_name(node, field.ptr, @intCast(field.len));
        if (!ts.ts_node_is_null(field_node)) {
            return try self.traverseToIR(field_node, source);
        }
        return try self.buildFallbackBlock(node, source);
    }

    // ═══════════════════════════════════════════════════════════
    // QUERIES SÉMANTIQUES (optionnel, non-bloquant)
    // ═══════════════════════════════════════════════════════════

    fn runQueries(self: *UniversalIngestor, root: ts.TSNode, source: []const u8, lang_name: []const u8) !void {
        const query_ptr = try self.loadQueryForLanguage(lang_name);
        defer ts.ts_query_delete(query_ptr);

        const cursor = ts.ts_query_cursor_new() orelse return error.TSCursorFailed;
        defer ts.ts_query_cursor_delete(cursor);

        ts.ts_query_cursor_exec(cursor, query_ptr, root);
        var match: ts.TSQueryMatch = undefined;
        while (ts.ts_query_cursor_next_match(cursor, &match)) {
            self.dispatchCapture(match, source, query_ptr) catch {};
        }
    }

    fn dispatchCapture(self: UniversalIngestor, match: ts.TSQueryMatch, source: []const u8, query: *ts.TSQuery) !void {
        var current_symbol: ?[]const u8 = null;

        for (0..match.capture_count) |i| {
            const capture = match.captures[i];
            var name_len: u32 = 0;
            const nameptr = ts.ts_query_capture_name_for_id(query, capture.index, &name_len);
            const tag = nameptr[0..name_len];
            const content = source[ts.ts_node_start_byte(capture.node)..ts.ts_node_end_byte(capture.node)];

            if (std.mem.eql(u8, tag, "def.symbol")) {
                current_symbol = content;
            } else if (std.mem.eql(u8, tag, "link.ref")) {
                const target_id = try self.matrix.addUniqueSymbol(content);
                if (current_symbol) |srcsym| {
                    if (self.matrix.findSymbol(srcsym)) |srcid| {
                        _ = try self.matrix.addEdge(srcid, target_id, "Ref");
                    }
                }
            }
        }
    }

    fn loadQueryForLanguage(self: UniversalIngestor, lang_name: []const u8) !*ts.TSQuery {
        var path_buf: [256]u8 = undefined;
        const querypath = try std.fmt.bufPrint(&path_buf, "vendor/queries/{s}.scm", .{lang_name});

        const file_content = platform.fs.cwd().readFileAlloc(self.allocator, querypath, 1024 * 1024) catch {
            return error.QueryCompilationFailed;
        };
        defer self.allocator.free(file_content);

        var error_offset: u32 = 0;
        var error_type: ts.TSQueryError = undefined;
        const ts_lang: ?*const ts.TSLanguage = @ptrCast(self.getTSLanguage(lang_name));

        const query = ts.ts_query_new(ts_lang, file_content.ptr, @intCast(file_content.len), &error_offset, &error_type);
        return query orelse error.QueryCompilationFailed;
    }

    // ═══════════════════════════════════════════════════════════
    // DÉTECTION LANGAGE & TREE-SITTER BINDINGS
    // ═══════════════════════════════════════════════════════════

    pub fn getLanguageFromExt(_: *UniversalIngestor, path: []const u8) ?[]const u8 {
        if (std.mem.endsWith(u8, path, ".hvn") or std.mem.endsWith(u8, path, ".heaven")) return "heaven";
        if (std.mem.endsWith(u8, path, ".zig")) return "zig";
        if (std.mem.endsWith(u8, path, ".c") or std.mem.endsWith(u8, path, ".h")) return "c";
        if (std.mem.endsWith(u8, path, ".pie")) return "pie";
        return null;
    }

    pub fn getTSLanguage(_: UniversalIngestor, lang_name: []const u8) *const anyopaque {
        if (std.mem.eql(u8, lang_name, "heaven")) return platform.tree_sitter_heaven();
        if (std.mem.eql(u8, lang_name, "zig")) return platform.tree_sitter_zig();
        if (std.mem.eql(u8, lang_name, "c")) return platform.tree_sitter_c();
        if (std.mem.eql(u8, lang_name, "pie")) return platform.tree_sitter_pie();
        return platform.tree_sitter_heaven();
    }

    fn captureFieldAsSymbol(self: *UniversalIngestor, node: ts.TSNode, field: []const u8, source: []const u8) !matrix_lib.BobId {
        const field_node = ts.ts_node_child_by_field_name(node, field.ptr, @intCast(field.len));
        if (ts.ts_node_is_null(field_node)) return 0;

        const start = ts.ts_node_start_byte(field_node);
        const end = ts.ts_node_end_byte(field_node);
        return self.matrix.addUniqueSymbol(source[start..end]);
    }

    fn buildFallbackBlock(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) !matrix_lib.BobId {
        var stmts: std.ArrayListUnmanaged(matrix_lib.BobId) = .{};
        var i: u32 = 0;
        const nc = ts.ts_node_named_child_count(node);
        while (i < nc) : (i += 1) {
            const child = ts.ts_node_named_child(node, i);
            if (!ts.ts_node_is_null(child)) {
                const id = try self.traverseToIR(child, source);
                if (id != 0) try stmts.append(self.arena.allocator(), id);
            }
        }
        if (stmts.items.len == 0) return 0;
        if (stmts.items.len == 1) return stmts.items[0];
        const owned = try self.allocator.dupe(matrix_lib.BobId, stmts.items);
        return self.matrix.addNode(.{ .HBlock = owned });
    }

    // Ajoute aussi cette petite correction pour processSource qui est appelée par le shell
    pub fn processSource(self: *UniversalIngestor, root: ts.TSNode, source: []const u8, _: []const u8) !void {
        _ = try self.traverseToIR(root, source);
    }

    fn buildFactDecl(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) !matrix_lib.BobId {
        // Extraire le texte brut du fait (sans "fact " et sans ".")
        const start = ts.ts_node_start_byte(node);
        const end = ts.ts_node_end_byte(node);
        const full_text = source[start..end];

        // Retirer "fact " au début et "." à la fin
        var text = full_text;
        if (std.mem.startsWith(u8, text, "fact ")) text = text[5..];
        if (text.len > 0 and text[text.len - 1] == '.') text = text[0 .. text.len - 1];
        text = std.mem.trim(u8, text, " \t\r\n");

        // Stocker comme FACT:parent(socrate, platon)
        var buf: [256]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "FACT:{s}", .{text}) catch return self.matrix.addNode(.{ .HIntLit = 0 });

        return self.matrix.addUniqueSymbol(label);
    }

    fn buildRuleDecl(self: *UniversalIngestor, node: ts.TSNode, source: []const u8) !matrix_lib.BobId {
        // Extraire le texte brut de la règle (sans "rule " et sans ".")
        const start = ts.ts_node_start_byte(node);
        const end = ts.ts_node_end_byte(node);
        const full_text = source[start..end];

        // Retirer "rule " au début et "." à la fin
        var text = full_text;
        if (std.mem.startsWith(u8, text, "rule ")) text = text[5..];
        if (text.len > 0 and text[text.len - 1] == '.') text = text[0 .. text.len - 1];
        text = std.mem.trim(u8, text, " \t\r\n");

        // Stocker comme RULE:ancestor(X, Y) :- parent(X, Y)
        var buf: [512]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "RULE:{s}", .{text}) catch return self.matrix.addNode(.{ .HIntLit = 0 });

        return self.matrix.addUniqueSymbol(label);
    }
};

// ═══════════════════════════════════════════════════════════
// Utilitaire — Classification des opérateurs
// ═══════════════════════════════════════════════════════════
fn classifyOp(op: []const u8) matrix_lib.HBinOpKind {
    if (std.mem.eql(u8, op, "+")) return .Add;
    if (std.mem.eql(u8, op, "-")) return .Sub;
    if (std.mem.eql(u8, op, "*") or std.mem.eql(u8, op, "×")) return .Mul;
    if (std.mem.eql(u8, op, "/") or std.mem.eql(u8, op, "÷")) return .Div;
    if (std.mem.eql(u8, op, "%")) return .Mod;
    if (std.mem.eql(u8, op, "==") or std.mem.eql(u8, op, "≡")) return .Eq;
    if (std.mem.eql(u8, op, "!=") or std.mem.eql(u8, op, "≢")) return .Neq;
    if (std.mem.eql(u8, op, "<=") or std.mem.eql(u8, op, "≤")) return .Lte;
    if (std.mem.eql(u8, op, ">=") or std.mem.eql(u8, op, "≥")) return .Gte;
    if (op.len == 1 and op[0] == '<') return .Lt;
    if (op.len == 1 and op[0] == '>') return .Gt;
    if (std.mem.eql(u8, op, "and") or std.mem.eql(u8, op, "&&") or std.mem.eql(u8, op, "∧")) return .And;
    if (std.mem.eql(u8, op, "or") or std.mem.eql(u8, op, "||") or std.mem.eql(u8, op, "∨")) return .Or;
    if (std.mem.eql(u8, op, "∘")) return .Compose;
    if (op.len == 1 and op[0] == '&') return .BitAnd;
    if (op.len == 1 and op[0] == '|') return .BitOr;
    if (op.len == 1 and op[0] == '^') return .Xor;
    if (std.mem.eql(u8, op, "<<")) return .Shl;
    if (std.mem.eql(u8, op, ">>")) return .Shr;
    return .Add;
}
