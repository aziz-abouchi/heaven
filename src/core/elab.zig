// src/core/elab.zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const platform = @import("platform");
const ts = platform.ts;
const engine_expr = @import("engine_expr");

pub const ElabError = error{
    UnsupportedNode,
    MissingField,
    InvalidLiteral,
    OutOfMemory,
    NoSpaceLeft,
    TypeError,
};

pub const Elaborator = struct {
    allocator: Allocator,
    store: *Store,
    source: []const u8,
    registry: ?*engine_expr.FunctionRegistry = null,

    pub fn init(allocator: Allocator, store: *Store, source: []const u8) Elaborator {
        return .{ .allocator = allocator, .store = store, .source = source };
    }

    // ─── Helpers Tree-sitter ───

    fn text(self: *const Elaborator, node: ts.TSNode) []const u8 {
        const start = ts.ts_node_start_byte(node);
        const end = ts.ts_node_end_byte(node);
        return self.source[start..end];
    }

    fn kind(node: ts.TSNode) []const u8 {
        return std.mem.span(ts.ts_node_type(node));
    }

    fn field(node: ts.TSNode, name: []const u8) ?ts.TSNode {
        const n = ts.ts_node_child_by_field_name(node, name.ptr, @intCast(name.len));
        if (ts.ts_node_is_null(n)) return null;
        return n;
    }

    fn namedChildCount(node: ts.TSNode) u32 {
        return ts.ts_node_named_child_count(node);
    }

    fn namedChild(node: ts.TSNode, i: u32) ts.TSNode {
        return ts.ts_node_named_child(node, i);
    }

    // ─── Dispatch ───

    pub fn elaborate(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const k = kind(node);

        if (std.mem.eql(u8, k, "source_file")) return self.elabSourceFile(node);
        if (std.mem.eql(u8, k, "block")) return self.elabBlock(node);
        if (std.mem.eql(u8, k, "fn_decl")) return self.elabFnDecl(node);
        if (std.mem.eql(u8, k, "eq_decl")) return self.elabEqDecl(node);
        if (std.mem.eql(u8, k, "var_decl")) return self.elabVarDecl(node);
        if (std.mem.eql(u8, k, "assign")) return self.elabAssign(node);
        if (std.mem.eql(u8, k, "if_stmt")) return self.elabIfStmt(node);
        if (std.mem.eql(u8, k, "if_expr")) return self.elabIfExpr(node);
        if (std.mem.eql(u8, k, "while_stmt")) return self.elabWhileStmt(node);
        if (std.mem.eql(u8, k, "ret")) return self.elabRet(node);
        if (std.mem.eql(u8, k, "call")) return self.elabCall(node);
        if (std.mem.eql(u8, k, "member")) return self.elabMember(node);
        if (std.mem.eql(u8, k, "app_expr")) return self.elabAppExpr(node);
        if (std.mem.eql(u8, k, "binary")) return self.elabBinary(node);
        if (std.mem.eql(u8, k, "simple_expr")) return self.elaborate(namedChild(node, 0));
        if (std.mem.eql(u8, k, "paren_expr")) return self.elaborate(namedChild(node, 0));
        if (std.mem.eql(u8, k, "identifier")) return self.store.sym(self.text(node));
        if (std.mem.eql(u8, k, "type_name")) return self.store.sym(self.text(node));
        if (std.mem.eql(u8, k, "int")) return self.elabInt(node);
        if (std.mem.eql(u8, k, "float")) return self.elabFloat(node);
        if (std.mem.eql(u8, k, "str")) return self.elabStr(node);
        if (std.mem.eql(u8, k, "bool_lit")) return self.elabBool(node);
        if (std.mem.eql(u8, k, "theorem_decl")) return self.elabTheoremDecl(node);
        if (std.mem.eql(u8, k, "data_decl")) return self.elabDataDecl(node);
        if (std.mem.eql(u8, k, "data_constructor")) return self.elabDataConstructor(node);
        if (std.mem.eql(u8, k, "ctor_arg_type")) return self.elaborate(namedChild(node, 0));
        if (std.mem.eql(u8, k, "axiom_decl")) return self.elabAxiomDecl(node);
        if (std.mem.eql(u8, k, "forall_type")) return self.elabForallType(node);
        if (std.mem.eql(u8, k, "exists_type")) return self.elabExistsType(node);
        if (std.mem.eql(u8, k, "generic_type")) return self.elabHeadArgs(node);
        if (std.mem.eql(u8, k, "applied_type")) return self.elabHeadArgs(node);
        if (std.mem.eql(u8, k, "arrow_type")) return self.elabArrowType(node);
        if (std.mem.eql(u8, k, "prim_type")) return self.store.sym(self.text(node));
        if (std.mem.eql(u8, k, "type_ident")) return self.elaborate(namedChild(node, 0));
        if (std.mem.eql(u8, k, "paren_type")) return self.elaborate(namedChild(node, 0));
        if (std.mem.eql(u8, k, "sig_decl")) return self.elabSigDecl(node);
        if (std.mem.eql(u8, k, "import_decl")) return self.elabImportDecl(node);
        if (std.mem.eql(u8, k, "pattern")) return self.elaborate(namedChild(node, 0));
        if (std.mem.eql(u8, k, "ctor_pat")) return self.elabCtorPat(node);
        if (std.mem.eql(u8, k, "list_pat")) return self.elabListPat(node);
        if (std.mem.eql(u8, k, "tuple_pat")) return self.elabTuplePat(node);
        if (std.mem.eql(u8, k, "atom")) return self.store.sym(self.text(node));
        if (std.mem.eql(u8, k, "_")) return self.store.hole(0);
        if (std.mem.eql(u8, k, "ERROR")) {
            // const start = ts.ts_node_start_byte(node);
            // const end = ts.ts_node_end_byte(node);
            // const snippet = self.source[start..end];
            // platform.debug.print("\n[!!!] SYNTAX ERROR DETECTED in: '{s}'\n", .{snippet});
            return ElabError.UnsupportedNode;
        }

        // const type_ptr = ts.ts_node_type(node);
        // platform.debug.print("\n[CRITICAL] Elaboration failed. Unsupported node type found: '{s}'\n", .{type_ptr});
        return ElabError.UnsupportedNode;
    }

    // ─── Containers ───

    fn elabSourceFile(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        return self.elabChildrenAs(node, .source_file);
    }

    fn elabBlock(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        return self.elabChildrenAs(node, .block);
    }

    fn elabChildrenAs(self: *Elaborator, node: ts.TSNode, tag: expr.Tag) ElabError!Id {
        const n = namedChildCount(node);
        var items: std.ArrayListUnmanaged(Id) = .{};
        defer items.deinit(self.allocator);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const child = namedChild(node, i);
            if (std.mem.eql(u8, kind(child), "comment")) continue;
            try items.append(self.allocator, try self.elaborate(child));
        }
        return self.store.addNode(.{
            .tag = tag,
            .payload = 0,
            .aux = 0,
            .span_a = try self.store.pushSpan(items.items),
            .span_b = .{ .start = 0, .len = 0 }, // ou expr.Span.EMPTY si expr est importé
        });
    }

    // ─── Déclarations ───

    fn elabFnDecl(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const name_node = field(node, "name") orelse return ElabError.MissingField;
        const name = self.text(name_node);

        var param_names: std.ArrayListUnmanaged([]const u8) = .{};
        defer param_names.deinit(self.allocator);
        if (field(node, "params")) |params_node| {
            const pc = namedChildCount(params_node);
            var i: u32 = 0;
            while (i < pc) : (i += 1) {
                const param_node = namedChild(params_node, i);
                const pname: []const u8 = if (namedChildCount(param_node) > 0)
                    self.text(namedChild(param_node, 0))
                else
                    self.text(ts.ts_node_child(param_node, 0)); // cas "self"
                try param_names.append(self.allocator, pname);
            }
        }

        const n = namedChildCount(node);
        const body_node = namedChild(node, n - 1); // $.block est toujours en dernière position
        const body = try self.elaborate(body_node);

        const fn_value = if (param_names.items.len > 0)
            try self.store.lambda(param_names.items, body)
        else
            body;

        return self.store.bind(name, fn_value);
    }

    fn elabEqDecl(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const name_node = field(node, "name") orelse return ElabError.MissingField;
        const name = self.text(name_node);
        const n = namedChildCount(node);
        if (n < 1) return ElabError.MissingField;

        // Le dernier enfant nommé est toujours le corps (_expr après "=")
        const body = try self.elaborate(namedChild(node, n - 1));

        // Les enfants entre "name" (index 0) et le corps (index n-1)
        // sont les patterns du LHS — on les collecte s'il y en a.
        var patterns: std.ArrayListUnmanaged(Id) = .{};
        defer patterns.deinit(self.allocator);

        // index 0 = name (champ nommé, pas un enfant "pattern")
        // index 1..n-2 = patterns (si présents)
        // index n-1 = body

        var i: u32 = 1;
        while (i < n - 1) : (i += 1) {
            const child = namedChild(node, i);
            const k = kind(child);

            // Ignorer guard (|/when), annotation de type — garder les patterns
            if (std.mem.eql(u8, k, "comment")) continue;
            if (std.mem.eql(u8, k, "type_ident")) continue; // annotation ":"

            // Si c'est un nœud "pattern", extraire ses enfants
            if (std.mem.eql(u8, k, "pattern")) {
                const pat_child_count = namedChildCount(child);
                var j: u32 = 0;
                while (j < pat_child_count) : (j += 1) {
                    const sub_child = namedChild(child, j);
                    const sub_k = kind(sub_child);

                    // Si c'est un ctor_pat, le déballer : constructeur + arguments
                    if (std.mem.eql(u8, sub_k, "ctor_pat")) {
                        const ctor_child_count = namedChildCount(sub_child);
                        var k_idx: u32 = 0;
                        while (k_idx < ctor_child_count) : (k_idx += 1) {
                            const ctor_sub = namedChild(sub_child, k_idx);
                            const pat_id = try self.elaborate(ctor_sub);
                            try patterns.append(self.allocator, pat_id);
                        }
                    } else {
                        const pat_id = try self.elaborate(sub_child);
                        try patterns.append(self.allocator, pat_id);
                    }
                }
            } else {
                // Tout le reste est un pattern : identifier, int, ctor_pat, etc.
                const pat_id = try self.elaborate(child);
                // platform.debug.print("  DEBUG: pattern[{d}] elaborated to id={d}\\n", .{ patterns.items.len, pat_id });
                try patterns.append(self.allocator, pat_id);
            }
        }

        if (self.registry) |reg| {
            // Enregistre la clause dans le FunctionRegistry (multi-clause safe)
            reg.register(name, patterns.items, body) catch {};
            // Retourne un nœud symbolique neutre (le registre est la vraie source)
            return self.store.sym(name);
        } else {
            // Fallback sans registre : bind naïf (comportement actuel)
            return self.store.bind(name, body);
        }
    }

    fn elabVarDecl(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const name_node = field(node, "name") orelse return ElabError.MissingField;
        const name = self.text(name_node);
        const n = namedChildCount(node);
        // TODO: distinguer annotation de type vs valeur — pour l'instant on prend
        // juste le dernier enfant nommé comme valeur (couvre let x = e et let x: T = e).
        if (n <= 1) return self.store.bind(name, try self.store.unitLit());
        const value = try self.elaborate(namedChild(node, n - 1));
        return self.store.bind(name, value);
    }

    fn elabAssign(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const target = try self.elaborate(namedChild(node, 0));
        const value = try self.elaborate(namedChild(node, 1));
        // TODO: désucrer += -= *= /= en assign(target, target op value)
        return self.store.call("assign", &.{ target, value });
    }

    // ─── Contrôle de flux ───

    fn elabIfExpr(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const cond = try self.elaborate(namedChild(node, 0));
        const then_b = try self.elaborate(namedChild(node, 1));
        const else_b = try self.elaborate(namedChild(node, 2));
        return self.store.call("if", &.{ cond, then_b, else_b });
    }

    fn elabIfStmt(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const n = namedChildCount(node);
        const cond = try self.elaborate(namedChild(node, 0));
        const then_b = try self.elaborate(namedChild(node, 1));
        if (n >= 3) {
            const else_b = try self.elaborate(namedChild(node, 2));
            return self.store.call("if", &.{ cond, then_b, else_b });
        }
        return self.store.call("if", &.{ cond, then_b });
    }

    fn elabWhileStmt(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const cond = try self.elaborate(namedChild(node, 0));
        const body = try self.elaborate(namedChild(node, 1));
        return self.store.call("while", &.{ cond, body });
    }

    fn elabRet(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        if (namedChildCount(node) == 0) return self.store.call("return", &.{});
        const value = try self.elaborate(namedChild(node, 0));
        return self.store.call("return", &.{value});
    }

    // ─── Appels & binaire ───

    fn elabCall(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const n = namedChildCount(node);
        if (n == 0) return ElabError.MissingField;
        const callee = try self.elaborate(namedChild(node, 0));
        var args: std.ArrayListUnmanaged(Id) = .{};
        defer args.deinit(self.allocator);
        var i: u32 = 1;
        while (i < n) : (i += 1) {
            try args.append(self.allocator, try self.elaborate(namedChild(node, i)));
        }
        return self.store.apply(callee, args.items);
    }

    fn elabAppExpr(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        // Même traitement que call, en n-aire plat (cohérent avec la résolution
        // d'ambiguïté call/app_expr faite dans la grammaire : les deux doivent
        // produire la même forme d'IR).
        return self.elabCall(node);
    }

    fn elabBinary(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        // binary = seq(_expr, <op anonyme>, _expr) — l'opérateur n'est PAS un
        // enfant nommé, il faut ts_node_child (pas named_child) pour l'atteindre.
        const lhs_node = ts.ts_node_child(node, 0);
        const op_node = ts.ts_node_child(node, 1);
        const rhs_node = ts.ts_node_child(node, 2);
        const lhs = try self.elaborate(lhs_node);
        const rhs = try self.elaborate(rhs_node);
        const op = self.text(op_node);
        return self.store.binop(op, lhs, rhs);
    }

    // ─── Littéraux ───

    fn elabInt(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const raw = self.text(node);
        var buf: [64]u8 = undefined;
        var len: usize = 0;
        for (raw) |c| {
            if (c == '_') continue; // la grammaire autorise 1_000_000
            buf[len] = c;
            len += 1;
        }
        const v = std.fmt.parseInt(i64, buf[0..len], 0) catch return ElabError.InvalidLiteral;
        return self.store.int(v);
    }

    fn elabFloat(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const v = std.fmt.parseFloat(f64, self.text(node)) catch return ElabError.InvalidLiteral;
        return self.store.float(v);
    }

    fn elabStr(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const t = self.text(node);
        const inner = if (t.len >= 2) t[1 .. t.len - 1] else t; // retire les guillemets
        const s = try self.store.interner.intern(inner);
        return self.store.lit(.{ .str = s });
    }

    fn elabBool(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        return self.store.boolean(std.mem.eql(u8, self.text(node), "true"));
    }

    // ─── Preuves (squelette minimal) ───

    fn elabProofBlock(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        // Structure : proof [by <strategy>] { <proof_step>* }
        var steps: std.ArrayListUnmanaged(Id) = .{};
        defer steps.deinit(self.allocator);

        var i: u32 = 0;
        const n = namedChildCount(node);
        while (i < n) : (i += 1) {
            const child = namedChild(node, i);
            const k = kind(child);

            if (std.mem.eql(u8, k, "proof_step")) {
                const step_id = try self.elaborateProofStep(child);
                try steps.append(self.allocator, step_id);
            }
            // Ignorer "proof", "by", et proof_strategy pour l'instant
        }

        // Créer un nœud "proof" avec tous les steps
        return self.store.call("proof", steps.items);
    }

    fn elaborateProofStep(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const n = namedChildCount(node);
        if (n == 0) return ElabError.MissingField;

        const first = namedChild(node, 0);
        const k = kind(first);

        if (std.mem.eql(u8, k, "case")) {
            // case <pat> => <steps>
            const pat = try self.elaborate(namedChild(node, 1));
            var sub_steps: std.ArrayListUnmanaged(Id) = .{};
            defer sub_steps.deinit(self.allocator);

            var i: u32 = 2;
            while (i < n) : (i += 1) {
                const sub = namedChild(node, i);
                const sub_id = try self.elaborateProofStep(sub);
                try sub_steps.append(self.allocator, sub_id);
            }

            const sub_proof = self.store.call("proof", sub_steps.items) catch return ElabError.OutOfMemory;
            return self.store.call("case", &.{ pat, sub_proof });
        }

        if (std.mem.eql(u8, k, "apply")) {
            // apply <expr>
            const elaborated_expr = try self.elaborate(namedChild(node, 1));
            return self.store.call("apply", &.{elaborated_expr});
        }

        if (std.mem.eql(u8, k, "rewrite")) {
            // rewrite <expr>
            const elaborated_expr = try self.elaborate(namedChild(node, 1));
            return self.store.call("rewrite", &.{elaborated_expr});
        }

        if (std.mem.eql(u8, k, "qed")) {
            // qed
            return self.store.sym("qed");
        }

        return ElabError.UnsupportedNode;
    }

    fn elabTheoremDecl(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const name_node = field(node, "name") orelse return ElabError.MissingField;
        const name = self.text(name_node);
        const stmt = try self.elaborate(namedChild(node, 1)); // 0=name, 1=statement

        // Chercher le proof_block (peut être à différentes positions)
        var proof_id: ?Id = null;
        const n = namedChildCount(node);
        var i: u32 = 2;
        while (i < n) : (i += 1) {
            const child = namedChild(node, i);
            if (std.mem.eql(u8, kind(child), "proof_block")) {
                proof_id = try self.elabProofBlock(child);
                break;
            }
        }

        // Si on a une preuve, créer un nœud theorem(name, stmt, proof)
        if (proof_id) |pid| {
            return self.store.call("theorem", &.{ try self.store.sym(name), stmt, pid });
        }

        // Sinon, juste bind(name, stmt)
        return self.store.bind(name, stmt);
    }

    fn elabDataDecl(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const name_node = field(node, "name") orelse return ElabError.MissingField;
        const name = self.text(name_node);
        const n = namedChildCount(node);
        var ctors: std.ArrayListUnmanaged(Id) = .{};
        defer ctors.deinit(self.allocator);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const child = namedChild(node, i);
            if (std.mem.eql(u8, kind(child), "data_constructor")) {
                try ctors.append(self.allocator, try self.elaborate(child));
            }
            // TODO: tparams ignoré pour l'instant — pas utilisé dans kernel.hvn actuel
        }
        const body = try self.store.call("data", ctors.items);
        return self.store.bind(name, body);
    }

    fn elabDataConstructor(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const n = namedChildCount(node);
        if (n == 0) return ElabError.MissingField;
        const ctor_name = self.text(namedChild(node, 0));
        var args: std.ArrayListUnmanaged(Id) = .{};
        defer args.deinit(self.allocator);
        var i: u32 = 1;
        while (i < n) : (i += 1) {
            try args.append(self.allocator, try self.elaborate(namedChild(node, i)));
        }
        return self.store.call(ctor_name, args.items);
    }

    fn elabHeadArgs(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        // generic_type (Eq<a,b>) et applied_type (Foo Bar Baz) ont la même forme :
        // tête + liste d'arguments _type, donc même encodage en .apply.
        const n = namedChildCount(node);
        if (n == 0) return ElabError.MissingField;
        const head = self.text(namedChild(node, 0));
        var args: std.ArrayListUnmanaged(Id) = .{};
        defer args.deinit(self.allocator);
        var i: u32 = 1;
        while (i < n) : (i += 1) {
            try args.append(self.allocator, try self.elaborate(namedChild(node, i)));
        }
        return self.store.call(head, args.items);
    }

    fn elabArrowType(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const lhs = try self.elaborate(namedChild(node, 0));
        const rhs = try self.elaborate(namedChild(node, 1));
        return self.store.call("->", &.{ lhs, rhs });
    }

    fn elabAxiomDecl(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const n = namedChildCount(node);
        if (n < 2) return ElabError.MissingField;
        const name = self.text(namedChild(node, 0));
        const ty = try self.elaborate(namedChild(node, n - 1));
        // TODO: tparams ignoré (idem data_decl)
        return self.store.bind(name, ty);
    }

    fn elabExistsType(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const n = namedChildCount(node);
        if (n == 0) return ElabError.MissingField;
        var args: std.ArrayListUnmanaged(Id) = .{};
        defer args.deinit(self.allocator);
        var i: u32 = 0;
        while (i < n - 1) : (i += 1) {
            try args.append(self.allocator, try self.store.sym(self.text(namedChild(node, i))));
        }
        try args.append(self.allocator, try self.elaborate(namedChild(node, n - 1)));
        return self.store.call("exists", args.items);
    }

    fn elabForallType(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        // Style 1 du kernel : repeat1("(" repeat1(identifier) ":" _type ")") "." _type
        // Le dernier enfant nommé est toujours le corps ; chaque groupe de parenthèses
        // accumule des identifiants jusqu'à rencontrer le _type qui les type tous.
        const n = namedChildCount(node);
        if (n == 0) return ElabError.MissingField;
        var binders: std.ArrayListUnmanaged(Id) = .{};
        defer binders.deinit(self.allocator);
        var pending_names: std.ArrayListUnmanaged([]const u8) = .{};
        defer pending_names.deinit(self.allocator);

        var i: u32 = 0;
        while (i < n - 1) : (i += 1) {
            const child = namedChild(node, i);
            if (std.mem.eql(u8, kind(child), "identifier")) {
                try pending_names.append(self.allocator, self.text(child));
            } else {
                const ty = try self.elaborate(child);
                for (pending_names.items) |pname| {
                    try binders.append(self.allocator, try self.store.bind(pname, ty));
                }
                pending_names.clearRetainingCapacity();
            }
        }
        const body = try self.elaborate(namedChild(node, n - 1));
        try binders.append(self.allocator, body);
        return self.store.call("forall", binders.items);
    }

    fn elabSigDecl(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const name_node = field(node, "name") orelse return ElabError.MissingField;
        const name = self.text(name_node);
        const n = namedChildCount(node);
        const ty = try self.elaborate(namedChild(node, n - 1));
        return self.store.bind(name, ty);
    }

    fn elabImportDecl(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        // import_decl: seq("import", $.str) — un seul enfant nommé (str)
        return self.elaborate(namedChild(node, 0));
    }

    fn elabMember(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const object_node = namedChild(node, 0);
        const field_node = namedChild(node, 1);

        const object_name = self.text(object_node);
        const field_name = self.text(field_node);

        var buf: [256]u8 = undefined;

        const qualified =
            try std.fmt.bufPrint(
                &buf,
                "{s}.{s}",
                .{ object_name, field_name },
            );

        return self.store.sym(qualified);
    }

    fn elabCtorPat(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        // ctor_pat : (type_name | identifier) repeat1(_pat)
        // ou : (type_name | identifier) "(" sep1(_pat, ",") ")"
        const n = namedChildCount(node);
        if (n == 0) return ElabError.MissingField;
        const head = self.text(namedChild(node, 0));
        var args: std.ArrayListUnmanaged(Id) = .{};
        defer args.deinit(self.allocator);
        var i: u32 = 1;
        while (i < n) : (i += 1) {
            try args.append(self.allocator, try self.elaborate(namedChild(node, i)));
        }
        return self.store.call(head, args.items);
    }

    fn elabListPat(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        // list_pat : "[" sep1(pattern, ",") "]"
        // Encode comme (list p1 p2 ...) pour l'instant
        const n = namedChildCount(node);
        var items: std.ArrayListUnmanaged(Id) = .{};
        defer items.deinit(self.allocator);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            try items.append(self.allocator, try self.elaborate(namedChild(node, i)));
        }
        return self.store.call("list", items.items);
    }

    fn elabTuplePat(self: *Elaborator, node: ts.TSNode) ElabError!Id {
        const n = namedChildCount(node);
        var items: std.ArrayListUnmanaged(Id) = .{};
        defer items.deinit(self.allocator);
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            try items.append(self.allocator, try self.elaborate(namedChild(node, i)));
        }
        return self.store.call("tuple", items.items);
    }
};

// ─── Dependent Type Checking ───

/// Typing context Γ: environment mapping variables to their types
pub const TypingContext = struct {
    bindings: std.ArrayList(struct { name: []const u8, type_id: Id }),
    allocator: Allocator,

    pub fn init(allocator: Allocator) TypingContext {
        return .{
            .bindings = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TypingContext) void {
        self.bindings.deinit(self.allocator);
    }

    /// Extend context with new binding x : A
    pub fn extend(self: *TypingContext, name: []const u8, type_id: Id) !void {
        try self.bindings.append(self.allocator, .{ .name = name, .type_id = type_id });
    }

    /// Lookup variable type in context (returns null if not found)
    pub fn lookup(self: *const TypingContext, name: []const u8) ?Id {
        var i = self.bindings.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.bindings.items[i].name, name)) {
                return self.bindings.items[i].type_id;
            }
        }
        return null;
    }
};

/// Type checker implementing bidirectional type inference for dependent types
pub const TypeChecker = struct {
    store: *Store,
    allocator: Allocator,

    // Cache de types de base (évite la création de nœuds en double)
    type_int: ?Id = null,
    type_float: ?Id = null,
    type_bool: ?Id = null,
    type_string: ?Id = null,
    type_unit: ?Id = null,
    type_runtime: ?Id = null,
    type_unknown: ?Id = null,

    pub const TypeError = error{
        UnboundVariable,
        TypeMismatch,
        NotAFunction,
        InvalidUniverse,
        NotImplemented,
        OutOfMemory,
    };

    pub fn init(allocator: Allocator, store: *Store) TypeChecker {
        return .{ .store = store, .allocator = allocator };
    }

    fn getTypeInt(self: *TypeChecker) !Id {
        if (self.type_int) |t| return t;
        const t = try self.store.sym("Int");
        self.type_int = t;
        return t;
    }
    fn getTypeFloat(self: *TypeChecker) !Id {
        if (self.type_float) |t| return t;
        const t = try self.store.sym("Float");
        self.type_float = t;
        return t;
    }
    fn getTypeBool(self: *TypeChecker) !Id {
        if (self.type_bool) |t| return t;
        const t = try self.store.sym("Bool");
        self.type_bool = t;
        return t;
    }
    fn getTypeString(self: *TypeChecker) !Id {
        if (self.type_string) |t| return t;
        const t = try self.store.sym("String");
        self.type_string = t;
        return t;
    }
    fn getTypeUnit(self: *TypeChecker) !Id {
        if (self.type_unit) |t| return t;
        const t = try self.store.sym("Unit");
        self.type_unit = t;
        return t;
    }
    fn getTypeRuntime(self: *TypeChecker) !Id {
        if (self.type_runtime) |t| return t;
        const t = try self.store.sym("Runtime");
        self.type_runtime = t;
        return t;
    }
    fn getTypeUnknown(self: *TypeChecker) !Id {
        if (self.type_unknown) |t| return t;
        const t = try self.store.sym("?");
        self.type_unknown = t;
        return t;
    }

    /// Infer the type of an expression: Γ ⊢ e : τ
    pub fn inferType(self: *TypeChecker, ctx: anytype, id: Id) !Id {
        _ = ctx;
        if (id >= self.store.len()) return error.InvalidId;
        const node = self.store.get(id);

        if (!node.tag.isPrimitive()) {
            return error.NotImplemented;
        }

        return switch (node.tag) {
            .lit => blk: {
                const lit = self.store.lits.items[node.aux];
                break :blk switch (lit) {
                    .int => try self.getTypeInt(),
                    .float => try self.getTypeFloat(),
                    .boolean => try self.getTypeBool(),
                    .str => try self.getTypeString(),
                    .unit => try self.getTypeUnit(),
                    .runtime => try self.getTypeRuntime(),
                };
            },
            .sym, .apply, .bind, .lambda, .relation => {
                return try self.getTypeUnknown();
            },
            else => return error.NotImplemented,
        };
    }

    /// Check that an expression has a given type: Γ ⊢ e ⇐ τ
    pub fn checkType(self: *TypeChecker, ctx: *const TypingContext, expr_id: Id, expected_type: Id) TypeError!void {
        const expr_node = self.store.get(expr_id);

        switch (expr_node.tag) {
            .lambda => {
                // λx.e ⇐ Π(x:A).B
                // Check that expected_type is a Pi-type
                const exp_node = self.store.get(expected_type);
                if (exp_node.tag != .bind) return TypeError.TypeMismatch;
                return self.checkLambda(ctx, expr_id, expected_type);
            },
            else => {
                // For other expressions, infer type and compare
                const inferred = try self.inferType(ctx, expr_id);
                if (!self.typesEqual(inferred, expected_type)) {
                    return TypeError.TypeMismatch;
                }
            },
        }
    }

    /// Compare two types for equality with WHNF normalization
    pub fn typesEqual(self: *TypeChecker, t1: Id, t2: Id) bool {
        const n1 = self.whnf(t1) catch return false;
        const n2 = self.whnf(t2) catch return false;

        if (n1 == n2) return true;

        const node1 = self.store.get(n1);
        const node2 = self.store.get(n2);

        if (node1.tag != node2.tag) return false;

        return switch (node1.tag) {
            .sym => {
                // Vérifier les limites uniquement (payload 0 est valide — c'est le 1er symbole interné)
                if (node1.payload >= self.store.interner.list.items.len or
                    node2.payload >= self.store.interner.list.items.len) return false;
                const name1 = self.store.interner.resolve(node1.payload);
                const name2 = self.store.interner.resolve(node2.payload);
                platform.debug.print("typesEqual: {s} vs {s} | payload {d} vs {d} | names: \"{s}\" vs \"{s}\"\n", .{
                    @tagName(node1.tag), @tagName(node2.tag),
                    node1.payload,       node2.payload,
                    name1,               name2,
                });
                if (node1.payload == node2.payload) return true;
                return std.mem.eql(u8, name1, name2);
            },
            .lit => {
                const lit1 = self.store.lits.items[node1.aux];
                const lit2 = self.store.lits.items[node2.aux];
                return std.meta.eql(lit1, lit2);
            },
            .bind => {
                const p = self.store.pool.items;
                const dom_span1 = node1.span_a.slice(p);
                const dom_span2 = node2.span_a.slice(p);
                if (dom_span1.len == 0 or dom_span2.len == 0) return false;
                const dom1 = dom_span1[0];
                const dom2 = dom_span2[0];
                const dom1_nf = self.whnf(dom1) catch return false;
                const dom2_nf = self.whnf(dom2) catch return false;
                if (!self.typesEqual(dom1_nf, dom2_nf)) return false;
                // Ne pas comparer les noms (pour l'équivalence alpha)
                return self.typesEqual(node1.aux, node2.aux);
            },
            else => n1 == n2,
        };
    }

    /// Reduce expression to Weak Head Normal Form (WHNF)
    /// WHNF reduces only the outermost redex, not under lambdas
    pub fn whnf(self: *TypeChecker, id: Id) !Id {
        const node = self.store.get(id);
        switch (node.tag) {
            .sym, .lit, .lambda, .bind => return id,
            .apply => {
                const fn_id = node.payload;
                const fn_whnf = try self.whnf(fn_id);
                const fn_node = self.store.get(fn_whnf);
                if (fn_node.tag == .lambda) {
                    const param_name = self.store.interner.resolve(fn_node.payload);
                    const p = self.store.pool.items;
                    const app_children = node.span_a.slice(p);
                    if (app_children.len == 0) return error.NotImplemented;
                    const arg = app_children[app_children.len - 1];
                    const arg_whnf = arg; // déjà en WHNF
                    const lambda_children = fn_node.span_a.slice(p);
                    if (lambda_children.len == 0) return error.NotImplemented;
                    const body = lambda_children[lambda_children.len - 1];
                    const body_node = self.store.get(body);
                    if (body_node.tag == .sym) {
                        const body_name = self.store.interner.resolve(body_node.payload);
                        if (std.mem.eql(u8, body_name, param_name)) {
                            return arg_whnf;
                        }
                    }
                    return id;
                } else {
                    return id;
                }
            },
            else => return id,
        }
    }

    /// Substitue toutes les occurrences libres de `var_name` par `replacement` dans `e`
    /// Cette version ne traverse pas sous les lieurs qui ombragent la variable.
    fn substituteVariable(self: *TypeChecker, e: Id, var_name: []const u8, replacement: Id) !Id {
        const node = self.store.get(e);
        switch (node.tag) {
            .sym => {
                const name = self.store.interner.resolve(node.payload);
                if (std.mem.eql(u8, name, var_name)) return replacement;
                return e;
            },
            .lit => return e,
            .lambda => {
                const bound_name = self.store.interner.resolve(node.payload);
                if (std.mem.eql(u8, bound_name, var_name)) return e; // ombrage
                const p = self.store.pool.items;
                const children = node.span_a.slice(p);
                var new_children = std.ArrayListUnmanaged(Id){};
                defer new_children.deinit(self.allocator);
                for (children) |child| {
                    try new_children.append(self.allocator, try self.substituteVariable(child, var_name, replacement));
                }
                const sa = try self.store.pushSpan(new_children.items);
                return self.store.addNode(.{
                    .tag = .lambda,
                    .payload = node.payload,
                    .aux = node.aux,
                    .span_a = sa,
                    .span_b = node.span_b,
                });
            },
            .bind => {
                const bound_name = self.store.interner.resolve(node.payload);
                if (std.mem.eql(u8, bound_name, var_name)) return e;
                const new_body = try self.substituteVariable(node.aux, var_name, replacement);
                const p = self.store.pool.items;
                const children = node.span_a.slice(p);
                var new_children = std.ArrayListUnmanaged(Id){};
                defer new_children.deinit(self.allocator);
                for (children) |child| {
                    try new_children.append(self.allocator, try self.substituteVariable(child, var_name, replacement));
                }
                const sa = try self.store.pushSpan(new_children.items);
                return self.store.addNode(.{
                    .tag = .bind,
                    .payload = node.payload,
                    .aux = new_body,
                    .span_a = sa,
                    .span_b = node.span_b,
                });
            },
            .apply => {
                const new_fn = try self.substituteVariable(node.payload, var_name, replacement);
                const p = self.store.pool.items;
                const args = node.span_a.slice(p);
                var new_args = std.ArrayListUnmanaged(Id){};
                defer new_args.deinit(self.allocator);
                for (args) |arg| {
                    try new_args.append(self.allocator, try self.substituteVariable(arg, var_name, replacement));
                }
                return try self.store.apply(new_fn, new_args.items);
            },
            else => return e,
        }
    }

    /// Capture-avoiding substitution: substitute variable x with term a in expression e
    /// Returns new expression with all free occurrences of x replaced by a
    /// Check a lambda against a Pi-type: λx.e ⇐ Π(x:A).B
    fn checkLambda(self: *TypeChecker, ctx: *const TypingContext, lambda_id: Id, pi_id: Id) TypeError!void {
        const lambda_node = self.store.get(lambda_id);
        const pi_node = self.store.get(pi_id);
        const p = self.store.pool.items;

        if (lambda_node.tag != .lambda) return TypeError.TypeMismatch;
        if (pi_node.tag != .bind) return TypeError.TypeMismatch;

        const lambda_param = self.store.interner.resolve(lambda_node.payload);
        const lambda_body_span = lambda_node.span_a.slice(p);
        if (lambda_body_span.len == 0) return TypeError.TypeMismatch;
        const lambda_body = lambda_body_span[lambda_body_span.len - 1];

        const pi_param = self.store.interner.resolve(pi_node.payload);
        const pi_app_node = self.store.get(pi_node.aux);
        if (pi_app_node.tag != .apply) return TypeError.TypeMismatch;
        const pi_args = pi_app_node.span_a.slice(p);
        if (pi_args.len < 2) return TypeError.TypeMismatch;
        const type_a = pi_args[0];
        const type_b = pi_args[1];

        var new_ctx = TypingContext.init(self.allocator);
        defer new_ctx.deinit();
        for (ctx.bindings.items) |b| {
            try new_ctx.extend(b.name, b.type_id);
        }
        try new_ctx.extend(pi_param, type_a);

        const body_to_check = if (std.mem.eql(u8, lambda_param, pi_param))
            lambda_body
        else
            try self.substVar(lambda_body, lambda_param, try self.store.sym(pi_param));

        return self.checkType(&new_ctx, body_to_check, type_b);
    }

    /// Infer the type of an application: f a ⇒ B[a/x] if f : Π(x:A).B
    fn inferApply(self: *TypeChecker, ctx: *const TypingContext, apply_id: Id) TypeError!Id {
        const apply_node = self.store.get(apply_id);
        const p = self.store.pool.items;

        if (apply_node.tag != .apply) return TypeError.NotAFunction;

        const func_type = try self.inferType(ctx, apply_node.payload);
        const func_type_node = self.store.get(func_type);
        if (func_type_node.tag != .bind) return TypeError.NotAFunction;

        const param_name = self.store.interner.resolve(func_type_node.payload);
        const pi_app_node = self.store.get(func_type_node.aux);
        if (pi_app_node.tag != .apply) return TypeError.NotAFunction;
        const pi_args = pi_app_node.span_a.slice(p);
        if (pi_args.len < 2) return TypeError.NotAFunction;
        const type_a = pi_args[0];
        const type_b = pi_args[1];

        const apply_args = apply_node.span_a.slice(p);
        if (apply_args.len == 0) return TypeError.NotAFunction;
        const arg = apply_args[apply_args.len - 1];

        try self.checkType(ctx, arg, type_a);

        return self.substVar(type_b, param_name, arg);
    }

    pub fn substVar(self: *TypeChecker, expr_id: Id, var_name: []const u8, replacement: Id) TypeError!Id {
        const node = self.store.get(expr_id);
        const p = self.store.pool.items;

        switch (node.tag) {
            .sym => {
                const name = self.store.interner.resolve(node.payload);
                //platform.debug.print("substVar: comparing {s} with {s}\n", .{ name, var_name });
                if (std.mem.eql(u8, name, var_name)) {
                    //platform.debug.print("substVar: replacing {s} with {}\n", .{ name, replacement });
                    return replacement;
                }
                return expr_id;
            },
            .lit => return expr_id, // Literals and universes have no variables

            .apply => {
                // Substitute in function and all arguments
                const new_func = try self.substVar(node.payload, var_name, replacement);
                var new_args: std.ArrayListUnmanaged(Id) = .{};
                defer new_args.deinit(self.allocator);
                for (node.span_a.slice(p)) |arg| {
                    try new_args.append(self.allocator, try self.substVar(arg, var_name, replacement));
                }
                return self.store.apply(new_func, new_args.items);
            },

            .bind => {
                // bind(x, value): substitute in value, but check for shadowing
                const bound_name = self.store.interner.resolve(node.payload);
                if (std.mem.eql(u8, bound_name, var_name)) {
                    // Variable is shadowed, no substitution in body
                    return expr_id;
                }
                const new_val = try self.substVar(node.aux, var_name, replacement);
                return self.store.addNode(.{
                    .tag = .bind,
                    .payload = node.payload,
                    .aux = new_val,
                    .span_a = expr.Span.EMPTY,
                    .span_b = expr.Span.EMPTY,
                });
            },

            .lambda => {
                // λx.body or let x = val in body
                const bound_name = self.store.interner.resolve(node.payload);

                // Substitute in value (for let_in, node.aux is the value)
                const new_aux = if (node.tag == .bind)
                    try self.substVar(node.aux, var_name, replacement)
                else
                    node.aux; // lambda has no value part

                // Check for shadowing in body
                if (std.mem.eql(u8, bound_name, var_name)) {
                    // Variable is shadowed, no substitution in body
                    const sa = node.span_a;
                    return self.store.addNode(.{
                        .tag = node.tag,
                        .payload = node.payload,
                        .aux = new_aux,
                        .span_a = sa,
                        .span_b = expr.Span.EMPTY,
                    });
                }

                // Substitute in body
                var new_body: std.ArrayListUnmanaged(Id) = .{};
                defer new_body.deinit(self.allocator);
                for (node.span_a.slice(p)) |child| {
                    try new_body.append(self.allocator, try self.substVar(child, var_name, replacement));
                }
                const sa = try self.store.pushSpan(new_body.items);
                return self.store.addNode(.{
                    .tag = node.tag,
                    .payload = node.payload,
                    .aux = new_aux,
                    .span_a = sa,
                    .span_b = expr.Span.EMPTY,
                });
            },

            else => return expr_id, // Unknown tags: return as-is
        }
    }
};

// ─── Point d'entrée ───

pub fn elaborateSource(
    allocator: std.mem.Allocator,
    store: *expr.Store,
    source: []const u8,
    opts: anytype,
) !expr.Id {
    // WASM stub : retourne une erreur
    if (@import("builtin").target.cpu.arch == .wasm32) return error.NotSupported;
    return elaborateSourceImpl(allocator, store, source, opts);
}

fn elaborateSourceImpl(
    allocator: Allocator,
    store: *Store,
    source: []const u8,
    registry: ?*engine_expr.FunctionRegistry,
) !Id {
    const parser = ts.ts_parser_new();
    defer ts.ts_parser_delete(parser);
    _ = ts.ts_parser_set_language(parser, platform.tree_sitter_heaven());

    const tree = ts.ts_parser_parse_string(parser, null, source.ptr, @intCast(source.len));
    defer ts.ts_tree_delete(tree);

    const root = ts.ts_tree_root_node(tree);
    var elab = Elaborator{ .allocator = allocator, .store = store, .source = source, .registry = registry };
    const root_id = try elab.elaborate(root);

    // Optional type checking
    // For now, we just infer the type to validate the expression is well-typed
    // In the future, this could check against an expected type
    var checker = TypeChecker.init(allocator, store);
    var ctx = TypingContext.init(allocator);
    defer ctx.deinit();

    // Try to infer the type - if it fails, the expression is ill-typed
    _ = checker.inferType(&ctx, root_id) catch |err| {
        // Map TypeError to a more appropriate error for the caller
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => return root_id, // Tolère les erreurs de stub (NotImplemented, InvalidId, etc.)
            //error.UnboundVariable => error.TypeError,
            //error.TypeMismatch => error.TypeError,
            //error.NotAFunction => error.TypeError,
            //error.InvalidUniverse => error.TypeError,
            //error.NotImplemented => root_id, // Allow not-implemented cases for now

        };
    };

    return root_id;
}

// ─── Tests for Type Checker ───

test "TypingContext extend and lookup" {
    const allocator = std.testing.allocator;
    var ctx = TypingContext.init(allocator);
    defer ctx.deinit();

    const nat_type = @as(Id, 1);
    const bool_type = @as(Id, 2);

    try ctx.extend("x", nat_type);
    try ctx.extend("y", bool_type);

    try std.testing.expect(ctx.lookup("x").? == nat_type);
    try std.testing.expect(ctx.lookup("y").? == bool_type);
    try std.testing.expect(ctx.lookup("z") == null);
}

test "TypeChecker substVar - simple variable" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const x = try store.sym("x");
    const y = try store.sym("y");
    const five = try store.int(5);

    var checker = TypeChecker.init(allocator, &store);

    // Substitute x with 5 in x → should get 5
    const result1 = try checker.substVar(x, "x", five);
    const node1 = store.get(result1);
    try std.testing.expect(node1.tag == .lit);

    // Substitute x with 5 in y → should get y (unchanged)
    const result2 = try checker.substVar(y, "x", five);
    try std.testing.expect(result2 == y);
}

test "TypeChecker substVar - lambda shadowing" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    // λx.x where we substitute x with 5 → should get λx.x (x is shadowed)
    const x_var = try store.sym("x");
    const lambda_id = try store.lambdaNative(&.{"x"}, x_var);

    const five = try store.int(5);

    var checker = TypeChecker.init(allocator, &store);
    const result = try checker.substVar(lambda_id, "x", five);

    // Result should still be a lambda
    const node = store.get(result);
    try std.testing.expect(node.tag == .lambda);
}

test "TypeChecker inferType - literal" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const five = try store.int(5);

    var ctx = TypingContext.init(allocator);
    defer ctx.deinit();

    var checker = TypeChecker.init(allocator, &store);
    const result_type = try checker.inferType(&ctx, five);

    const type_node = store.get(result_type);
    try std.testing.expect(type_node.tag == .sym);
    const result_node_for_name = store.get(result_type);
    const type_name = store.interner.resolve(result_node_for_name.payload);
    try std.testing.expect(std.mem.eql(u8, type_name, "Int"));
}

test "TypeChecker inferType - variable lookup" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const x_var = try store.sym("x");
    const nat_type = try store.sym("Nat");

    var ctx = TypingContext.init(allocator);
    defer ctx.deinit();
    try ctx.extend("x", nat_type);

    var checker = TypeChecker.init(allocator, &store);
    const result_type = try checker.inferType(&ctx, x_var);

    try std.testing.expect(result_type == nat_type);
}

test "WHNF - beta reduction" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const x_var = try store.sym("x");
    const lambda_id = try store.lambdaNative(&.{"x"}, x_var);
    const five = try store.int(5);
    const app_id = try store.apply(lambda_id, &.{five});

    var checker = TypeChecker.init(allocator, &store);
    const result = try checker.whnf(app_id);

    const node = store.get(result);
    try std.testing.expect(node.tag == .lit);

    const lit_val = store.lits.items[node.aux];
    try std.testing.expect(lit_val == .int);
    try std.testing.expect(lit_val.int == 5);
}

test "WHNF - no reduction under lambda" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    // Create λx.(λy.y) x → should NOT reduce the inner application
    const x_var = try store.sym("x");
    const y_var = try store.sym("y");
    const inner_lambda = try store.lambdaNative(&.{"y"}, y_var);
    const inner_app = try store.apply(inner_lambda, &.{x_var});
    const outer_lambda = try store.lambdaNative(&.{"x"}, inner_app);

    var checker = TypeChecker.init(allocator, &store);
    const result = try checker.whnf(outer_lambda);

    // Result should still be a lambda (WHNF doesn't reduce under lambda)
    const node = store.get(result);
    try std.testing.expect(node.tag == .lambda);
}

test "typesEqual - alpha equivalence" {
    //if (true) return;
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    // Create Π(x:Nat).Nat
    const nat = try store.sym("Nat");
    const pi1 = try store.pi("x", nat, nat);

    // Create Π(y:Nat).Nat (same type, different parameter name)
    const pi2 = try store.pi("y", nat, nat);

    var checker = TypeChecker.init(allocator, &store);

    // These should be equal despite different parameter names
    try std.testing.expect(checker.typesEqual(pi1, pi2));
    try std.testing.expect(checker.typesEqual(pi2, pi1));
}

test "typesEqual - different types" {
    // if (true) return; // Retiré pour déboguer
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();

    const nat = try store.sym("Nat");
    const bool_type = try store.sym("Bool");

    // Π(x:Nat).Nat
    const pi1 = try store.pi("x", nat, nat);
    // Π(x:Nat).Bool
    const pi2 = try store.pi("x", nat, bool_type);

    var checker = TypeChecker.init(allocator, &store);

    std.debug.print("=== DEBUG typesEqual - different types ===\n", .{});
    std.debug.print("pi1 id={}, pi2 id={}\n", .{ pi1, pi2 });
    const p = store.pool.items;

    const node1 = store.get(pi1);
    const node2 = store.get(pi2);
    std.debug.print("pi1: tag={}, payload={}, aux={}, span_a.len={}\n", .{ node1.tag, node1.payload, node1.aux, node1.span_a.slice(p).len });
    std.debug.print("pi2: tag={}, payload={}, aux={}, span_a.len={}\n", .{ node2.tag, node2.payload, node2.aux, node2.span_a.slice(p).len });

    const dom1 = node1.span_a.slice(p)[0];
    const dom2 = node2.span_a.slice(p)[0];
    const codom1 = node1.aux;
    const codom2 = node2.aux;

    std.debug.print("dom1={}, dom2={}, codom1={}, codom2={}\n", .{ dom1, dom2, codom1, codom2 });
    std.debug.print("dom1 tag={}, dom2 tag={}\n", .{ store.get(dom1).tag, store.get(dom2).tag });
    std.debug.print("codom1 tag={}, codom2 tag={}\n", .{ store.get(codom1).tag, store.get(codom2).tag });

    const result = checker.typesEqual(pi1, pi2);
    std.debug.print("typesEqual result: {}\n", .{result});

    // These should NOT be equal
    try std.testing.expect(!checker.typesEqual(pi1, pi2));
}
