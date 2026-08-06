const std = @import("std");

// ═══════════════════════════════════════════════════════════ // TERMES LOGIQUES // ═══════════════════════════════════════════════════════════

pub const Term = union(enum) {
    Var: u32, // Variable logique (fresh)
    Atom: []const u8, // Symbole (socrate, platon, ...)
    Int: i64, // Entier
    Nil, // Liste vide []
    Pair: *const TermPair, // Paire/Cons [H|T]

    pub fn eql(a: Term, b: Term) bool {
        return switch (a) {
            .Var => |av| switch (b) {
                .Var => |bv| av == bv,
                else => false,
            },
            .Atom => |aa| switch (b) {
                .Atom => |ba| std.mem.eql(u8, aa, ba),
                else => false,
            },
            .Int => |ai| switch (b) {
                .Int => |bi| ai == bi,
                else => false,
            },
            .Nil => switch (b) {
                .Nil => true,
                else => false,
            },
            .Pair => |ap| switch (b) {
                .Pair => |bp| ap.head.eql(bp.head) and ap.tail.eql(bp.tail),
                else => false,
            },
        };
    }

    pub fn format(self: Term, buf: *[256]u8) []const u8 {
        var stream = std.io.fixedBufferStream(buf);
        const w = stream.writer();
        self.writeTo(w) catch {};
        return buf[0..stream.pos];
    }

    fn writeTo(self: Term, w: anytype) !void {
        switch (self) {
            .Var => |v| try w.print("_{d}", .{v}),
            .Atom => |a| try w.writeAll(a),
            .Int => |i| try w.print("{d}", .{i}),
            .Nil => try w.writeAll("[]"),
            .Pair => |p| {
                try w.writeAll("[");
                try p.head.writeTo(w);
                var tail = p.tail;
                while (true) {
                    switch (tail) {
                        .Pair => |pp| {
                            try w.writeAll(", ");
                            try pp.head.writeTo(w);
                            tail = pp.tail;
                        },
                        .Nil => break,
                        else => {
                            try w.writeAll(" | ");
                            try tail.writeTo(w);
                            break;
                        },
                    }
                }
                try w.writeAll("]");
            },
        }
    }
};

pub const TermPair = struct {
    head: Term,
    tail: Term,
};

// ═══════════════════════════════════════════════════════════ // SUBSTITUTION (walk + extend) // ═══════════════════════════════════════════════════════════

pub const Substitution = struct {
    bindings: std.AutoHashMap(u32, Term),
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) Substitution {
        return .{ .bindings = std.AutoHashMap(u32, Term).init(alloc), .allocator = alloc };
    }

    pub fn deinit(self: *Substitution) void {
        self.bindings.deinit();
    }

    pub fn clone(self: *const Substitution) Substitution {
        var new_sub = Substitution.init(self.allocator);
        var it = self.bindings.iterator();
        while (it.next()) |entry| {
            new_sub.bindings.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
        }
        return new_sub;
    }

    // Walk : résoudre une variable à travers la chaîne de substitution
    pub fn walk(self: *const Substitution, term: Term) Term {
        var current = term;
        var attempts: u32 = 0;
        while (attempts < 100) : (attempts += 1) {
            switch (current) {
                .Var => |v| {
                    if (self.bindings.get(v)) |val| {
                        current = val;
                    } else return current;
                },
                else => return current,
            }
        }
        return current;
    }

    // Walk profond : résoudre récursivement (pour l'affichage)
    pub fn walkDeep(self: *const Substitution, term: Term) Term {
        const walked = self.walk(term);
        switch (walked) {
            .Pair => |p| {
                const new_pair = self.allocator.create(TermPair) catch return walked;
                new_pair.* = .{
                    .head = self.walkDeep(p.head),
                    .tail = self.walkDeep(p.tail),
                };
                return .{ .Pair = new_pair };
            },
            else => return walked,
        }
    }

    // Extend : ajouter un binding
    pub fn extend(self: *Substitution, v: u32, term: Term) bool {
        // Occurs check (empêcher les boucles infinies)
        if (self.occursIn(v, term)) return false;
        self.bindings.put(v, term) catch return false;
        return true;
    }

    fn occursIn(self: *const Substitution, v: u32, term: Term) bool {
        const walked = self.walk(term);
        switch (walked) {
            .Var => |vv| return vv == v,
            .Pair => |p| return self.occursIn(v, p.head) or self.occursIn(v, p.tail),
            else => return false,
        }
    }
};

// ═══════════════════════════════════════════════════════════ // UNIFICATION // ═══════════════════════════════════════════════════════════

pub fn unify(sub: *Substitution, u: Term, v: Term) bool {
    const wu = sub.walk(u);
    const wv = sub.walk(v);

    // Mêmes termes
    if (wu.eql(wv)) return true;

    // Variable gauche → bind
    switch (wu) {
        .Var => |vu| return sub.extend(vu, wv),
        else => {},
    }

    // Variable droite → bind
    switch (wv) {
        .Var => |vv| return sub.extend(vv, wu),
        else => {},
    }

    // Paires → unifier récursivement
    switch (wu) {
        .Pair => |pu| {
            switch (wv) {
                .Pair => |pv| {
                    if (!unify(sub, pu.head, pv.head)) return false;
                    return unify(sub, pu.tail, pv.tail);
                },
                else => return false,
            }
        },
        else => return false,
    }
}

// ═══════════════════════════════════════════════════════════ // STREAMS (lazy list de substitutions) // ═══════════════════════════════════════════════════════════

pub const Stream = struct {
    items: std.ArrayListUnmanaged(Substitution),
    allocator: std.mem.Allocator,

    pub fn empty(alloc: std.mem.Allocator) Stream {
        return .{ .items = .{}, .allocator = alloc };
    }

    pub fn unit(alloc: std.mem.Allocator, sub: Substitution) Stream {
        var s = Stream.empty(alloc);
        s.items.append(alloc, sub) catch {};
        return s;
    }

    pub fn deinit(self: *Stream) void {
        for (self.items.items) |*sub| {
            sub.deinit();
        }
        self.items.deinit(self.allocator);
    }

    // Interleaving : mélanger deux streams alternativement
    pub fn interleave(a: *Stream, b: *Stream, alloc: std.mem.Allocator) Stream {
        var result = Stream.empty(alloc);
        var ai: usize = 0;
        var bi: usize = 0;
        while (ai < a.items.items.len or bi < b.items.items.len) {
            if (ai < a.items.items.len) {
                result.items.append(alloc, a.items.items[ai]) catch {};
                ai += 1;
            }
            if (bi < b.items.items.len) {
                result.items.append(alloc, b.items.items[bi]) catch {};
                bi += 1;
            }
        }
        return result;
    }

    pub fn appendStream(self: *Stream, other: *Stream) void {
        for (other.items.items) |sub| {
            self.items.append(self.allocator, sub) catch {};
        }
    }
};

// ═══════════════════════════════════════════════════════════ // GOALS // ═══════════════════════════════════════════════════════════

pub const Goal = struct {
    kind: GoalKind,

    pub const GoalKind = union(enum) {
        Unify: struct { u: Term, v: Term },
        Conj: struct { g1: *Goal, g2: *Goal },
        Disj: struct { g1: *Goal, g2: *Goal },
        Fresh: struct { body: *Goal, var_id: u32 },
        Relate: struct { name: []const u8, args: []const Term },
    };
};

// ═══════════════════════════════════════════════════════════ // KANREN ENGINE // ═══════════════════════════════════════════════════════════

pub const Relation = struct {
    name: []const u8,
    clauses: std.ArrayListUnmanaged(RelClause),
};

pub const RelClause = struct {
    // Les variables dans la clause (numérotées localement)
    num_vars: u32, // Les goals du corps (head est implicite via unification des args)
    head_args: []const Term,
    body: []const RelGoal,
};

pub const RelGoal = struct {
    name: []const u8,
    args: []const Term,
};

pub const KanrenEngine = struct {
    allocator: std.mem.Allocator,
    relations: std.StringHashMap(Relation),
    next_var: u32,

    pub fn init(alloc: std.mem.Allocator) KanrenEngine {
        return .{
            .allocator = alloc,
            .relations = std.StringHashMap(Relation).init(alloc),
            .next_var = 0,
        };
    }

    pub fn fresh(self: *KanrenEngine) Term {
        const v = self.next_var;
        self.next_var += 1;
        return .{ .Var = v };
    }

    // Définir une relation
    pub fn defineRelation(self: *KanrenEngine, name: []const u8) *Relation {
        if (!self.relations.contains(name)) {
            self.relations.put(name, .{
                .name = name,
                .clauses = .{},
            }) catch {};
        }
        return self.relations.getPtr(name).?;
    }

    pub fn addClause(self: *KanrenEngine, rel: *Relation, head_args: []const Term, body: []const RelGoal, num_vars: u32) void {
        rel.clauses.append(self.allocator, .{
            .num_vars = num_vars,
            .head_args = head_args,
            .body = body,
        }) catch {};
    }

    // Résoudre un goal
    pub fn solve(self: *KanrenEngine, name: []const u8, args: []const Term, max_results: u32) Stream {
        var sub = Substitution.init(self.allocator);
        return self.solveGoal(name, args, &sub, 0, max_results);
    }

    fn solveGoal(self: *KanrenEngine, name: []const u8, args: []const Term, sub: *Substitution, depth: u32, max_results: u32) Stream {
        if (depth > 50) return Stream.empty(self.allocator);

        const rel = self.relations.get(name) orelse return Stream.empty(self.allocator);
        var results = Stream.empty(self.allocator);

        for (rel.clauses.items) |clause| {
            if (results.items.items.len >= max_results) break;

            // Renommer les variables de la clause
            const base_var = self.next_var;
            self.next_var += clause.num_vars;

            // Copier la substitution
            var new_sub = sub.clone();

            // Unifier les arguments avec la tête
            var unified = true;
            for (clause.head_args, 0..) |head_arg, i| {
                if (i >= args.len) {
                    unified = false;
                    break;
                }
                const renamed_head = self.renameVarInTerm(head_arg, base_var);
                if (!unify(&new_sub, args[i], renamed_head)) {
                    unified = false;
                    break;
                }
            }

            if (!unified) {
                new_sub.deinit();
                continue;
            }

            // Résoudre le body
            if (clause.body.len == 0) {
                // Fait → solution directe
                results.items.append(self.allocator, new_sub) catch {};
            } else {
                // Règle → résoudre les sous-goals séquentiellement
                var body_results = self.solveBody(clause.body, &new_sub, depth + 1, max_results, base_var);
                results.appendStream(&body_results);
                new_sub.deinit();
            }
        }

        return results;
    }

    fn solveBody(self: *KanrenEngine, goals: []const RelGoal, sub: *Substitution, depth: u32, max_results: u32, base_var: u32) Stream {
        if (goals.len == 0) return Stream.unit(self.allocator, sub.clone());
        if (depth > 50) return Stream.empty(self.allocator);

        const first = goals[0];
        const rest = goals[1..];

        // Évaluer les arguments avec la substitution courante
        var resolved_args: [8]Term = undefined;
        for (first.args, 0..) |arg, i| {
            resolved_args[i] = sub.walk(self.renameVarInTerm(arg, base_var));
        }

        // Résoudre le premier goal
        var first_results = self.solveGoal(first.name, resolved_args[0..first.args.len], sub, depth, max_results);
        var final_results = Stream.empty(self.allocator);

        // Pour chaque résultat, résoudre le reste
        for (first_results.items.items) |*sol| {
            if (final_results.items.items.len >= max_results) break;
            var rest_results = self.solveBody(rest, sol, depth, max_results, base_var);
            final_results.appendStream(&rest_results);
        }

        first_results.deinit();
        return final_results;
    }

    fn renameVarInTerm(self: *KanrenEngine, term: Term, base: u32) Term {
        switch (term) {
            .Var => |v| return .{ .Var = v + base },
            .Pair => |p| {
                const new_pair = self.allocator.create(TermPair) catch return term;
                new_pair.* = .{
                    .head = self.renameVarInTerm(p.head, base),
                    .tail = self.renameVarInTerm(p.tail, base),
                };
                return .{ .Pair = new_pair };
            },
            else => return term,
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  HELPERS pour construire des termes
    // ═══════════════════════════════════════════════════════════

    pub fn atom(a: []const u8) Term {
        return .{ .Atom = a };
    }

    pub fn int(n: i64) Term {
        return .{ .Int = n };
    }

    pub fn variable(id: u32) Term {
        return .{ .Var = id };
    }

    pub fn nil() Term {
        return .Nil;
    }

    pub fn cons(self: *KanrenEngine, head: Term, tail: Term) Term {
        const pair = self.allocator.create(TermPair) catch return .Nil;
        pair.* = .{ .head = head, .tail = tail };
        return .{ .Pair = pair };
    }

    pub fn list(self: *KanrenEngine, items: []const Term) Term {
        var result: Term = .Nil;
        var i: usize = items.len;
        while (i > 0) {
            i -= 1;
            result = self.cons(items[i], result);
        }
        return result;
    }

    // ═══════════════════════════════════════════════════════════
    //  CHARGEMENT DEPUIS LA MATRIX (réutilise les FACT:/RULE:)
    // ═══════════════════════════════════════════════════════════

    pub fn loadFromSymbols(self: *KanrenEngine, symbols: std.StringHashMap(u32)) void {
        var it = symbols.iterator();
        while (it.next()) |entry| {
            const sym = entry.key_ptr.*;
            if (std.mem.startsWith(u8, sym, "FACT:")) {
                self.loadFact(sym[5..]);
            } else if (std.mem.startsWith(u8, sym, "RULE:")) {
                self.loadRule(sym[5..]);
            }
        }
        self.defineAppend();
        self.defineMember();
        self.defineLast();
        self.defineReverse();
    }

    fn defineAppend(self: *KanrenEngine) void {
        const rel = self.defineRelation("append");

        // Clause 1 : append([], Ys, Ys).
        // head_args = [Nil, Var(0), Var(0)]  (Y=Y)
        const c1_args = self.allocator.dupe(Term, &[_]Term{ .Nil, .{ .Var = 0 }, .{ .Var = 0 } }) catch return;
        const c1_body = self.allocator.alloc(RelGoal, 0) catch return;
        rel.clauses.append(self.allocator, .{ .num_vars = 1, .head_args = c1_args, .body = c1_body }) catch {};

        // Clause 2 : append([X|Xs], Ys, [X|Zs]) :- append(Xs, Ys, Zs).
        // head_args = [Pair(Var(0), Var(1)), Var(2), Pair(Var(0), Var(3))]
        // body = [append(Var(1), Var(2), Var(3))]
        const p1 = self.allocator.create(TermPair) catch return;
        p1.* = .{ .head = .{ .Var = 0 }, .tail = .{ .Var = 1 } }; // [X|Xs]
        const p2 = self.allocator.create(TermPair) catch return;
        p2.* = .{ .head = .{ .Var = 0 }, .tail = .{ .Var = 3 } }; // [X|Zs]

        const c2_args = self.allocator.dupe(Term, &[_]Term{
            .{ .Pair = p1 },
            .{ .Var = 2 },
            .{ .Pair = p2 },
        }) catch return;

        const c2_body_args = self.allocator.dupe(Term, &[_]Term{
            .{ .Var = 1 }, .{ .Var = 2 }, .{ .Var = 3 },
        }) catch return;
        const c2_body = self.allocator.dupe(RelGoal, &[_]RelGoal{
            .{ .name = "append", .args = c2_body_args },
        }) catch return;

        rel.clauses.append(self.allocator, .{ .num_vars = 4, .head_args = c2_args, .body = c2_body }) catch {};
    }

    fn defineMember(self: *KanrenEngine) void {
        const rel = self.defineRelation("member");

        // Clause 1 : member(X, [X|_]).
        const p1 = self.allocator.create(TermPair) catch return;
        p1.* = .{ .head = .{ .Var = 0 }, .tail = .{ .Var = 1 } };
        const c1_args = self.allocator.dupe(Term, &[_]Term{ .{ .Var = 0 }, .{ .Pair = p1 } }) catch return;
        const c1_body = self.allocator.alloc(RelGoal, 0) catch return;
        rel.clauses.append(self.allocator, .{ .num_vars = 2, .head_args = c1_args, .body = c1_body }) catch {};

        // Clause 2 : member(X, [_|T]) :- member(X, T).
        const p2 = self.allocator.create(TermPair) catch return;
        p2.* = .{ .head = .{ .Var = 1 }, .tail = .{ .Var = 2 } };
        const c2_args = self.allocator.dupe(Term, &[_]Term{ .{ .Var = 0 }, .{ .Pair = p2 } }) catch return;
        const c2_body_args = self.allocator.dupe(Term, &[_]Term{ .{ .Var = 0 }, .{ .Var = 2 } }) catch return;
        const c2_body = self.allocator.dupe(RelGoal, &[_]RelGoal{
            .{ .name = "member", .args = c2_body_args },
        }) catch return;
        rel.clauses.append(self.allocator, .{ .num_vars = 3, .head_args = c2_args, .body = c2_body }) catch {};
    }

    fn defineLast(self: *KanrenEngine) void {
        const rel = self.defineRelation("last");

        // Clause 1 : last([X], X).
        const p1 = self.allocator.create(TermPair) catch return;
        p1.* = .{ .head = .{ .Var = 0 }, .tail = .Nil };
        const c1_args = self.allocator.dupe(Term, &[_]Term{ .{ .Pair = p1 }, .{ .Var = 0 } }) catch return;
        const c1_body = self.allocator.alloc(RelGoal, 0) catch return;
        rel.clauses.append(self.allocator, .{ .num_vars = 1, .head_args = c1_args, .body = c1_body }) catch {};

        // Clause 2 : last([_|T], X) :- last(T, X).
        const p2 = self.allocator.create(TermPair) catch return;
        p2.* = .{ .head = .{ .Var = 1 }, .tail = .{ .Var = 2 } };
        const c2_args = self.allocator.dupe(Term, &[_]Term{ .{ .Pair = p2 }, .{ .Var = 0 } }) catch return;
        const c2_body_args = self.allocator.dupe(Term, &[_]Term{ .{ .Var = 2 }, .{ .Var = 0 } }) catch return;
        const c2_body = self.allocator.dupe(RelGoal, &[_]RelGoal{
            .{ .name = "last", .args = c2_body_args },
        }) catch return;
        rel.clauses.append(self.allocator, .{ .num_vars = 3, .head_args = c2_args, .body = c2_body }) catch {};
    }

    fn defineReverse(self: *KanrenEngine) void {
        const rel = self.defineRelation("reverse");

        // Clause 1 : reverse([], []).
        const c1_args = self.allocator.dupe(Term, &[_]Term{ .Nil, .Nil }) catch return;
        const c1_body = self.allocator.alloc(RelGoal, 0) catch return;
        rel.clauses.append(self.allocator, .{ .num_vars = 0, .head_args = c1_args, .body = c1_body }) catch {};

        // Clause 2 : reverse([H|T], R) :- reverse(T, RT), append(RT, [H], R).
        const p1 = self.allocator.create(TermPair) catch return;
        p1.* = .{ .head = .{ .Var = 0 }, .tail = .{ .Var = 1 } }; // [H|T]
        const p2 = self.allocator.create(TermPair) catch return;
        p2.* = .{ .head = .{ .Var = 0 }, .tail = .Nil }; // [H]

        const c2_args = self.allocator.dupe(Term, &[_]Term{ .{ .Pair = p1 }, .{ .Var = 2 } }) catch return;
        const c2_body_args1 = self.allocator.dupe(Term, &[_]Term{ .{ .Var = 1 }, .{ .Var = 3 } }) catch return;
        const c2_body_args2 = self.allocator.dupe(Term, &[_]Term{ .{ .Var = 3 }, .{ .Pair = p2 }, .{ .Var = 2 } }) catch return;
        const c2_body = self.allocator.dupe(RelGoal, &[_]RelGoal{
            .{ .name = "reverse", .args = c2_body_args1 },
            .{ .name = "append", .args = c2_body_args2 },
        }) catch return;
        rel.clauses.append(self.allocator, .{ .num_vars = 4, .head_args = c2_args, .body = c2_body }) catch {};
    }
    fn loadFact(self: *KanrenEngine, text: []const u8) void {
        const ps = std.mem.indexOf(u8, text, "(") orelse return;
        const pe = std.mem.lastIndexOf(u8, text, ")") orelse return;
        if (pe <= ps) return;
        const pred = text[0..ps];
        const args_str = text[ps + 1 .. pe];
        var buf: [8]Term = undefined;
        var n: usize = 0;
        var ait = std.mem.tokenizeAny(u8, args_str, ",");
        while (ait.next()) |a| {
            if (n < 8) {
                buf[n] = self.parseTerm(std.mem.trim(u8, a, " "));
                n += 1;
            }
        }
        const ha = self.allocator.dupe(Term, buf[0..n]) catch return;
        const body = self.allocator.alloc(RelGoal, 0) catch return;
        const rel = self.defineRelation(pred);
        rel.clauses.append(self.allocator, .{ .num_vars = 0, .head_args = ha, .body = body }) catch {};
    }

    fn loadRule(self: *KanrenEngine, text: []const u8) void {
        const sep = std.mem.indexOf(u8, text, ":-") orelse return;
        const head_str = std.mem.trim(u8, text[0..sep], " ");
        const body_str = std.mem.trim(u8, text[sep + 2 ..], " ");

        // Parse head
        const paren_start = std.mem.indexOf(u8, head_str, "(") orelse return;
        const paren_end = std.mem.lastIndexOf(u8, head_str, ")") orelse return;
        const pred = head_str[0..paren_start];
        const args_str = head_str[paren_start + 1 .. paren_end];

        var head_args_buf: [8]Term = undefined;
        var arity: usize = 0;
        var max_var: u32 = 0;
        var arg_it = std.mem.tokenizeAny(u8, args_str, ",");
        while (arg_it.next()) |arg| {
            if (arity >= 8) break;
            const trimmed = std.mem.trim(u8, arg, " ");
            head_args_buf[arity] = self.parseTermV(trimmed, &max_var);
            arity += 1;
        }

        // Parse body (split par virgule hors parenthèses)
        var body_buf: [8]RelGoal = undefined;
        var body_len: usize = 0;
        var depth: u32 = 0;
        var start: usize = 0;
        for (body_str, 0..) |ch, idx| {
            if (ch == '(') depth += 1 else if (ch == ')') {
                if (depth > 0) depth -= 1;
            } else if (ch == ',' and depth == 0) {
                if (body_len < 8) {
                    body_buf[body_len] = self.parseBodyAtom(std.mem.trim(u8, body_str[start..idx], " "), &max_var);
                    body_len += 1;
                }
                start = idx + 1;
            }
        }
        if (start < body_str.len and body_len < 8) {
            body_buf[body_len] = self.parseBodyAtom(std.mem.trim(u8, body_str[start..], " "), &max_var);
            body_len += 1;
        }

        const head_args = self.allocator.dupe(Term, head_args_buf[0..arity]) catch return;
        const body = self.allocator.dupe(RelGoal, body_buf[0..body_len]) catch return;

        const rel = self.defineRelation(pred);
        self.addClause(rel, head_args, body, max_var + 1);
    }

    fn parseBodyAtom(self: *KanrenEngine, text: []const u8, max_var: *u32) RelGoal {
        const paren_start = std.mem.indexOf(u8, text, "(") orelse return .{ .name = text, .args = &.{} };
        const paren_end = std.mem.lastIndexOf(u8, text, ")") orelse return .{ .name = text, .args = &.{} };
        const pred = text[0..paren_start];
        const args_str = text[paren_start + 1 .. paren_end];

        var args_buf: [8]Term = undefined;
        var arity: usize = 0;
        var arg_it = std.mem.tokenizeAny(u8, args_str, ",");
        while (arg_it.next()) |arg| {
            if (arity >= 8) break;
            args_buf[arity] = self.parseTermV(std.mem.trim(u8, arg, " "), max_var);
            arity += 1;
        }

        const args = self.allocator.dupe(Term, args_buf[0..arity]) catch return .{ .name = pred, .args = &.{} };
        return .{ .name = pred, .args = args };
    }

    fn parseTerm(self: *KanrenEngine, text: []const u8) Term {
        if (text.len == 0) return .Nil;
        if (std.mem.eql(u8, text, "[]")) return .Nil;
        if (std.fmt.parseInt(i64, text, 10)) |n| return .{ .Int = n } else |_| {}
        if (text[0] == '[' and text[text.len - 1] == ']') {
            return self.parseListTerm(text[1 .. text.len - 1], null);
        }
        return .{ .Atom = text };
    }

    fn parseTermV(self: *KanrenEngine, text: []const u8, mv: *u32) Term {
        if (text.len == 0) return .Nil;
        if (std.mem.eql(u8, text, "[]")) return .Nil;
        if (std.fmt.parseInt(i64, text, 10)) |n| return .{ .Int = n } else |_| {}
        if (text[0] >= 'A' and text[0] <= 'Z') {
            const vid: u32 = @as(u32, text[0] - 'A');
            if (vid >= mv.*) mv.* = vid + 1;
            return .{ .Var = vid };
        }
        if (text[0] == '[' and text[text.len - 1] == ']') {
            return self.parseListTerm(text[1 .. text.len - 1], mv);
        }
        return .{ .Atom = text };
    }

    pub fn parseListTerm(self: *KanrenEngine, inner: []const u8, mv: ?*u32) Term {
        if (inner.len == 0) return .Nil;

        var items_buf: [32][]const u8 = undefined;
        var count: usize = 0;
        var depth: u32 = 0;
        var start: usize = 0;
        var pipe_pos: ?usize = null;

        for (inner, 0..) |ch, idx| {
            if (ch == '[') depth += 1 else if (ch == ']') {
                if (depth > 0) depth -= 1;
            } else if (ch == ',' and depth == 0) {
                if (count < 32) {
                    items_buf[count] = std.mem.trim(u8, inner[start..idx], " ");
                    count += 1;
                }
                start = idx + 1;
            } else if (ch == '|' and depth == 0) {
                pipe_pos = idx;
                if (count < 32) {
                    items_buf[count] = std.mem.trim(u8, inner[start..idx], " ");
                    count += 1;
                }
                break;
            }
        }

        if (pipe_pos) |pp| {
            const tail_str = std.mem.trim(u8, inner[pp + 1 ..], " ");
            var tail = if (mv) |m| self.parseTermV(tail_str, m) else self.parseTerm(tail_str);
            var i: usize = count;
            while (i > 0) {
                i -= 1;
                const head = if (mv) |m| self.parseTermV(items_buf[i], m) else self.parseTerm(items_buf[i]);
                const pair = self.allocator.create(TermPair) catch return .Nil;
                pair.* = .{ .head = head, .tail = tail };
                tail = .{ .Pair = pair };
            }
            return tail;
        }

        // Liste simple
        if (start < inner.len and count < 32) {
            items_buf[count] = std.mem.trim(u8, inner[start..], " ");
            count += 1;
        }

        var result: Term = .Nil;
        var i: usize = count;
        while (i > 0) {
            i -= 1;
            const elem = if (mv) |m| self.parseTermV(items_buf[i], m) else self.parseTerm(items_buf[i]);
            const pair = self.allocator.create(TermPair) catch return .Nil;
            pair.* = .{ .head = elem, .tail = result };
            result = .{ .Pair = pair };
        }
        return result;
    }
};
