const std = @import("std");

// ═══════════════════════════════════════════════════════════ // TERMES LOGIQUES // ═══════════════════════════════════════════════════════════

var next_fresh_var_id: u32 = 1000;

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

    // Constructeurs et helpers de termes
    pub fn sym(name: []const u8) Term {
        return .{ .Atom = name };
    }

    pub fn freshVar(_: []const u8) Term {
        const v = next_fresh_var_id;
        next_fresh_var_id += 1;
        return .{ .Var = v };
    }

    pub fn primitiveLitInt(allocator: std.mem.Allocator, val: i64) Term {
        return list(allocator, &.{ sym("lit"), .{ .Int = val } });
    }

    pub fn pair(allocator: std.mem.Allocator, head: Term, tail: Term) Term {
        const p = allocator.create(TermPair) catch unreachable;
        p.* = .{ .head = head, .tail = tail };
        return .{ .Pair = p };
    }

    pub fn list(allocator: std.mem.Allocator, elements: []const Term) Term {
        var result: Term = .Nil;
        var i: usize = elements.len;
        while (i > 0) {
            i -= 1;
            result = pair(allocator, elements[i], result);
        }
        return result;
    }

    pub fn arrow(param: Term, ret: Term) Term {
        const alloc = std.heap.page_allocator;
        return list(alloc, &.{ sym("arrow"), param, ret });
    }

    pub fn getSymbolName(self: Term) ?[]const u8 {
        return switch (self) {
            .Atom => |a| a,
            else => null,
        };
    }

    pub fn isLambda(self: Term) bool {
        return switch (self) {
            .Pair => |p| switch (p.head) {
                .Atom => |a| std.mem.eql(u8, a, "lambda"),
                else => false,
            },
            else => false,
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

    pub fn walk(self: *const Substitution, term: Term) Term {
        var current = term;
        var hops: u32 = 0;

        // Un cycle dans une Substitution est une invariant violé
        // (occurs-check aurait dû le refuser). On panique plutôt que
        // de renvoyer silencieusement un terme non résolu.
        const MAX_HOPS: u32 = 4096;

        while (true) : (hops += 1) {
            switch (current) {
                .Var => |v| {
                    if (self.bindings.get(v)) |val| {
                        current = val;
                        if (hops >= MAX_HOPS) {
                            @panic("Substitution.walk: cycle détecté (>4096 sauts)");
                        }
                    } else return current;
                },
                else => return current,
            }
        }
    }

    /// Variante paramétrée par un allocateur externe, pour permettre
    /// au moteur d'y brancher son arène scratch.
    pub fn walkDeepIn(self: *const Substitution, term: Term, alloc: std.mem.Allocator) Term {
        const walked = self.walk(term);
        switch (walked) {
            .Pair => |p| {
                const new_head = self.walkDeepIn(p.head, alloc);
                const new_tail = self.walkDeepIn(p.tail, alloc);
                const new_pair = alloc.create(TermPair) catch return walked;
                new_pair.* = .{ .head = new_head, .tail = new_tail };
                return .{ .Pair = new_pair };
            },
            else => return walked,
        }
    }

    /// Ancienne API : délègue sur l'allocateur propre de la Substitution.
    /// (Non utilisée par typeo.zig — conservée pour compat.)
    pub fn walkDeep(self: *const Substitution, term: Term) Term {
        return self.walkDeepIn(term, self.allocator);
    }

    pub fn extend(self: *Substitution, v: u32, term: Term) bool {
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

    if (wu.eql(wv)) return true;

    switch (wu) {
        .Var => |vu| return sub.extend(vu, wv),
        else => {},
    }

    switch (wv) {
        .Var => |vv| return sub.extend(vv, wu),
        else => {},
    }

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

// ═══════════════════════════════════════════════════════════ // STREAMS // ═══════════════════════════════════════════════════════════

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

    /// Transfère tous les items de `other` dans `self`, en vidant `other`.
    ///
    /// APRÈS appel :
    /// - `self` possède chaque `Substitution` ;
    /// - `other.items` est vide → `other.deinit()` devient sûr (pas de double-free).
    ///
    /// Le buffer `ArrayListUnmanaged` de `other` doit être libéré par
    /// l'appelant (`other.deinit()` ou `clearAndFree`).
    pub fn appendStream(self: *Stream, other: *Stream) void {
        self.items.appendSlice(self.allocator, other.items.items) catch {};
        other.items.clearRetainingCapacity();
    }
};

// ═══════════════════════════════════════════════════════════ // KANREN ENGINE // ═══════════════════════════════════════════════════════════

pub const Relation = struct {
    name: []const u8,
    clauses: std.ArrayListUnmanaged(RelClause),
};

pub const RelClause = struct {
    num_vars: u32,
    head_args: []const Term,
    body: []const RelGoal,
};

pub const RelGoal = struct {
    name: []const u8,
    args: []const Term,
};

/// Mini-parser récursif de S-expressions pour `parseTerm`.
///
/// Convention actuelle :
/// - `N` (seul) produit `Var(1)` — sera renommé par clause à l'usage ;
/// - `Nil` produit `.Nil` ;
/// - tout entier (avec signe optionnel) produit `.Int` ;
/// - tout autre identifiant produit `.Atom` ;
/// - `[a, b, c]` et `f(a, b)` produisent des listes propres.
///
/// Toutes les allocations vont dans `self.allocator` (à brancher sur
/// l'arène scratch du moteur par `parseTerm`).
const TermParser = struct {
    src: []const u8,
    pos: usize = 0,
    allocator: std.mem.Allocator,

    fn peekChar(self: *TermParser) ?u8 {
        if (self.pos >= self.src.len) return null;
        return self.src[self.pos];
    }

    fn skipWs(self: *TermParser) void {
        while (self.pos < self.src.len and std.ascii.isWhitespace(self.src[self.pos])) {
            self.pos += 1;
        }
    }

    fn parseExpr(self: *TermParser) error{ InvalidTerm, UnclosedParen, OutOfMemory }!Term {
        self.skipWs();
        const c = self.peekChar() orelse return error.InvalidTerm;

        if (c == '[') return self.parseBracketList();
        if (c == '(') return self.parseParenGroup();

        const head = try self.parseAtomOrNumber();

        // Appel de style Lisp `f(a, b, c)` : uniquement si head est un Atom.
        self.skipWs();
        if (self.peekChar()) |ch| {
            if (ch == '(') {
                switch (head) {
                    .Atom => return self.parseCallWithHead(head),
                    else => return head,
                }
            }
        }
        return head;
    }

    fn parseCallWithHead(
        self: *TermParser,
        head: Term,
    ) error{ InvalidTerm, UnclosedParen, OutOfMemory }!Term {
        std.debug.assert(self.src[self.pos] == '(');
        self.pos += 1;

        var elems = std.ArrayListUnmanaged(Term){};
        defer elems.deinit(self.allocator);
        try elems.append(self.allocator, head);

        while (true) {
            self.skipWs();
            const c = self.peekChar() orelse return error.UnclosedParen;
            if (c == ')') {
                self.pos += 1;
                break;
            }
            if (c == ',') {
                self.pos += 1;
                continue;
            }
            try elems.append(self.allocator, try self.parseExpr());
        }
        return self.listFromElems(elems.items);
    }

    fn parseParenGroup(self: *TermParser) error{ InvalidTerm, UnclosedParen, OutOfMemory }!Term {
        // Consomme '(' et traite le groupe comme une liste nue.
        self.pos += 1;
        var elems = std.ArrayListUnmanaged(Term){};
        defer elems.deinit(self.allocator);
        while (true) {
            self.skipWs();
            const c = self.peekChar() orelse return error.UnclosedParen;
            if (c == ')') {
                self.pos += 1;
                break;
            }
            if (c == ',') {
                self.pos += 1;
                continue;
            }
            try elems.append(self.allocator, try self.parseExpr());
        }
        return self.listFromElems(elems.items);
    }

    fn parseBracketList(self: *TermParser) error{ InvalidTerm, UnclosedParen, OutOfMemory }!Term {
        std.debug.assert(self.src[self.pos] == '[');
        self.pos += 1;
        var elems = std.ArrayListUnmanaged(Term){};
        defer elems.deinit(self.allocator);
        while (true) {
            self.skipWs();
            const c = self.peekChar() orelse return error.UnclosedParen;
            if (c == ']') {
                self.pos += 1;
                break;
            }
            if (c == ',') {
                self.pos += 1;
                continue;
            }
            try elems.append(self.allocator, try self.parseExpr());
        }
        return self.listFromElems(elems.items);
    }

    fn parseAtomOrNumber(self: *TermParser) error{InvalidTerm}!Term {
        const start = self.pos;
        while (self.pos < self.src.len) {
            const ch = self.src[self.pos];
            const accepted = std.ascii.isAlphanumeric(ch) or
                ch == '_' or ch == '?' or
                ch == '-' or ch == '+' or ch == '*' or
                ch == '/' or ch == '=' or ch == '<' or
                ch == '>' or ch == '!';
            if (!accepted) break;
            self.pos += 1;
        }
        const text = self.src[start..self.pos];
        if (text.len == 0) return error.InvalidTerm;

        if (std.fmt.parseInt(i64, text, 10)) |n| {
            return .{ .Int = n };
        } else |_| {}

        if (std.mem.eql(u8, text, "N")) return .{ .Var = 1 };
        if (std.mem.eql(u8, text, "Nil")) return .Nil;
        return Term.sym(text);
    }

    fn listFromElems(self: *TermParser, elems: []const Term) Term {
        var result: Term = .Nil;
        var i: usize = elems.len;
        while (i > 0) {
            i -= 1;
            result = Term.pair(self.allocator, elems[i], result);
        }
        return result;
    }
};

pub const KanrenEngine = struct {
    allocator: std.mem.Allocator,
    scratch: std.heap.ArenaAllocator,
    relations: std.StringHashMap(Relation),
    next_var: u32,

    pub fn init(alloc: std.mem.Allocator) KanrenEngine {
        return .{
            .allocator = alloc,
            .scratch = std.heap.ArenaAllocator.init(alloc),
            .relations = std.StringHashMap(Relation).init(alloc),
            .next_var = 0,
        };
    }

    pub fn deinit(self: *KanrenEngine) void {
        var it = self.relations.valueIterator();
        while (it.next()) |rel| {
            for (rel.clauses.items) |clause| {
                self.allocator.free(clause.head_args);
                self.allocator.free(clause.body);
            }
            rel.clauses.deinit(self.allocator);
        }
        self.relations.deinit();
        self.scratch.deinit();
    }

    /// Allocateur à utiliser pour les Term.pair transitoires.
    /// La mémoire vit jusqu'à `engine.deinit()`.
    pub fn transientAllocator(self: *KanrenEngine) std.mem.Allocator {
        return self.scratch.allocator();
    }

    pub fn fresh(self: *KanrenEngine) Term {
        const v = self.next_var;
        self.next_var += 1;
        return .{ .Var = v };
    }

    pub fn defineRelation(self: *KanrenEngine, name: []const u8) *Relation {
        if (!self.relations.contains(name)) {
            self.relations.put(name, .{
                .name = name,
                .clauses = .{},
            }) catch {};
        }
        return self.relations.getPtr(name).?;
    }

    pub fn addClause(
        self: *KanrenEngine,
        name: []const u8,
        head_args: []const Term,
        body: []const RelGoal,
        num_vars: u32,
    ) !void {
        const duped_args = try self.allocator.dupe(Term, head_args);
        const duped_body = try self.allocator.dupe(RelGoal, body);

        const gop = try self.relations.getOrPut(name);
        if (!gop.found_existing) {
            gop.value_ptr.* = Relation{
                .name = name,
                .clauses = .{},
            };
        }
        try gop.value_ptr.clauses.append(self.allocator, .{
            .num_vars = num_vars,
            .head_args = duped_args,
            .body = duped_body,
        });
    }

    /// Parse une S-expression en `Term`.
    /// Voir `TermParser` pour la grammaire supportée.
    /// Les allocations vont dans l'arène `scratch` du moteur.
    pub fn parseTerm(self: *KanrenEngine, str: []const u8) Term {
        var parser = TermParser{
            .src = str,
            .allocator = self.scratch.allocator(),
        };
        return parser.parseExpr() catch Term.sym(str);
    }

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

            const base_var = self.next_var;
            self.next_var += clause.num_vars;

            var new_sub = sub.clone();

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

            if (clause.body.len == 0) {
                results.items.append(self.allocator, new_sub) catch {};
            } else {
                var body_results = self.solveBody(clause.body, &new_sub, depth + 1, max_results, base_var);
                results.appendStream(&body_results);
                body_results.deinit();
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

        var resolved_args: [8]Term = undefined;
        for (first.args, 0..) |arg, i| {
            resolved_args[i] = sub.walk(self.renameVarInTerm(arg, base_var));
        }

        var first_results = self.solveGoal(first.name, resolved_args[0..first.args.len], sub, depth, max_results);
        var final_results = Stream.empty(self.allocator);

        for (first_results.items.items) |*sol| {
            if (final_results.items.items.len >= max_results) break;
            var rest_results = self.solveBody(rest, sol, depth, max_results, base_var);
            final_results.appendStream(&rest_results);
            rest_results.deinit();
        }

        first_results.deinit();
        return final_results;
    }

    pub fn renameVarInTerm(self: *KanrenEngine, term: Term, base_var: u32) Term {
        switch (term) {
            .Var => |v| return .{ .Var = v + base_var },
            .Pair => |p| {
                const new_head = self.renameVarInTerm(p.head, base_var);
                const new_tail = self.renameVarInTerm(p.tail, base_var);
                const a = self.scratch.allocator(); // ← arène au lieu de self.allocator
                const new_pair = a.create(TermPair) catch return term;
                new_pair.* = .{ .head = new_head, .tail = new_tail };
                return .{ .Pair = new_pair };
            },
            else => return term,
        }
    }

    /// Garantit l'existence de la relation `append`.
    ///
    /// NOTE : la signature accepte `snapshot` pour compatibilité avec
    /// `cmdRunStar` (commands.zig:88), mais ne l'utilise pas. Les clauses
    /// `append` sont actuellement codées en dur (standard Prolog).
    /// TODO : construire dynamiquement les relations à partir du snapshot.
    pub fn loadFromSymbols(self: *KanrenEngine, snapshot: anytype) void {
        _ = snapshot;

        if (self.relations.contains("append")) return;

        const alloc = self.scratch.allocator();

        // append([], L, L).
        {
            const l = self.fresh();
            self.addClause(
                "append",
                &.{ .Nil, l, l },
                &.{},
                2,
            ) catch {};
        }

        // append([H|T], L, [H|R]) :- append(T, L, R).
        {
            const h = self.fresh();
            const t = self.fresh();
            const l = self.fresh();
            const r = self.fresh();

            const ht = Term.pair(alloc, h, t);
            const hr = Term.pair(alloc, h, r);

            // Le body doit survivre à addClause : args doit être sur le heap.
            const body_args = alloc.dupe(Term, &.{ t, l, r }) catch return;
            const body = alloc.dupe(RelGoal, &.{
                .{ .name = "append", .args = body_args },
            }) catch return;

            self.addClause(
                "append",
                &.{ ht, l, hr },
                body,
                4,
            ) catch {};
        }
    }

    /// Parse le contenu d'une liste Prolog `a, b, c` (entre crochets).
    ///
    /// Exemples :
    ///   "a, b, c"   → [a, b, c]              = Pair(a, Pair(b, Pair(c, Nil)))
    ///   "X, Y"      → [Var, Var]
    ///   "1, 2"      → [Int(1), Int(2)]
    ///   "[a], b"    → [[a], b]
    ///   ""          → Nil
    ///
    /// `tail` permet de construire une liste impropre : `parseListTerm("a, b", X)`
    /// produit `[a, b | X]`. Passer `null` pour une liste propre (tail = Nil).
    ///
    /// LIMITATION : les variables majuscules (`X`) créent chacune une nouvelle
    /// variable fraîche, sans déduplication. Pour l'instant `append([X], Y, Z)`
    /// ne partage pas `X` avec d'éventuelles occurrences hors de la liste.
    /// À corriger en propageant le contexte `qvs` de `Shell.parseKanrenArg`.
    pub fn parseListTerm(self: *KanrenEngine, inner: []const u8, tail: ?Term) Term {
        const alloc = self.scratch.allocator();
        const final_tail: Term = tail orelse .Nil;

        var elems: std.ArrayListUnmanaged(Term) = .{};
        defer elems.deinit(alloc);

        var start: usize = 0;
        var depth: usize = 0;
        var i: usize = 0;
        while (i < inner.len) : (i += 1) {
            const c = inner[i];
            switch (c) {
                '[' => depth += 1,
                ']' => {
                    if (depth > 0) depth -= 1;
                },
                ',' => {
                    if (depth == 0) {
                        const elem_str = std.mem.trim(u8, inner[start..i], " \t");
                        elems.append(alloc, self.parseListElement(elem_str)) catch return final_tail;
                        start = i + 1;
                    }
                },
                else => {},
            }
        }
        if (start < inner.len) {
            const elem_str = std.mem.trim(u8, inner[start..], " \t");
            if (elem_str.len > 0) {
                elems.append(alloc, self.parseListElement(elem_str)) catch return final_tail;
            }
        }

        var result: Term = final_tail;
        var j: usize = elems.items.len;
        while (j > 0) {
            j -= 1;
            result = Term.pair(alloc, elems.items[j], result);
        }
        return result;
    }

    /// Parse un élément atomique de liste (utilisé par `parseListTerm`).
    fn parseListElement(self: *KanrenEngine, text: []const u8) Term {
        if (text.len == 0) return .Nil;
        if (std.mem.eql(u8, text, "[]")) return .Nil;
        if (text[0] >= 'A' and text[0] <= 'Z') return self.fresh();
        if (std.fmt.parseInt(i64, text, 10)) |n| {
            return .{ .Int = n };
        } else |_| {}
        if (text[0] == '[' and text[text.len - 1] == ']') {
            return self.parseListTerm(text[1 .. text.len - 1], null);
        }
        return .{ .Atom = text };
    }
};

test "appendStream transfers ownership without double-free" {
    const allocator = std.testing.allocator;

    var a = Stream.empty(allocator);
    defer a.deinit();

    var b = Stream.empty(allocator);
    defer b.deinit(); // ← doit être sûr, plus de double-free

    var sub1 = Substitution.init(allocator);
    try sub1.bindings.put(1, Term.sym("x"));
    try b.items.append(allocator, sub1);

    var sub2 = Substitution.init(allocator);
    try sub2.bindings.put(2, Term.sym("y"));
    try b.items.append(allocator, sub2);

    a.appendStream(&b);

    try std.testing.expectEqual(@as(usize, 2), a.items.items.len);
    try std.testing.expectEqual(@as(usize, 0), b.items.items.len);
}

test "parseTerm — atome et entier" {
    const allocator = std.testing.allocator;
    var engine = KanrenEngine.init(allocator);
    defer engine.deinit();

    const a = engine.parseTerm("foo");
    try std.testing.expect(a == .Atom);
    try std.testing.expectEqualStrings("foo", a.Atom);

    const n = engine.parseTerm("42");
    try std.testing.expect(n == .Int);
    try std.testing.expectEqual(@as(i64, 42), n.Int);

    const neg = engine.parseTerm("-7");
    try std.testing.expect(neg == .Int);
    try std.testing.expectEqual(@as(i64, -7), neg.Int);
}

test "parseTerm — Nil et N" {
    const allocator = std.testing.allocator;
    var engine = KanrenEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expect(engine.parseTerm("Nil") == .Nil);

    const v = engine.parseTerm("N");
    try std.testing.expect(v == .Var);
    try std.testing.expectEqual(@as(u32, 1), v.Var);
}

test "parseTerm — appel simple" {
    const allocator = std.testing.allocator;
    var engine = KanrenEngine.init(allocator);
    defer engine.deinit();

    const t = engine.parseTerm("lit(N)");
    try std.testing.expect(t == .Pair);
    const p = t.Pair;
    try std.testing.expect(p.head == .Atom);
    try std.testing.expectEqualStrings("lit", p.head.Atom);
    try std.testing.expect(p.tail == .Pair);
    try std.testing.expect(p.tail.Pair.head == .Var);
    try std.testing.expectEqual(@as(u32, 1), p.tail.Pair.head.Var);
}

test "parseTerm — appel multi-args" {
    const allocator = std.testing.allocator;
    var engine = KanrenEngine.init(allocator);
    defer engine.deinit();

    const t = engine.parseTerm("arrow(Int, Int)");
    try std.testing.expect(t == .Pair);

    var count: usize = 0;
    var cursor = t;
    while (cursor == .Pair) : (cursor = cursor.Pair.tail) count += 1;
    // head + 2 args
    try std.testing.expectEqual(@as(usize, 3), count);
}

test "parseTerm — appel imbriqué" {
    const allocator = std.testing.allocator;
    var engine = KanrenEngine.init(allocator);
    defer engine.deinit();

    const t = engine.parseTerm("f(g(x), h(y))");
    try std.testing.expect(t == .Pair);
    try std.testing.expectEqualStrings("f", t.Pair.head.Atom);

    // Premier arg = g(x) → Pair(Pair(Atom("g"), Pair(Atom("x"), Nil)), ...)
    const first_arg = t.Pair.tail.Pair.head;
    try std.testing.expect(first_arg == .Pair);
    try std.testing.expectEqualStrings("g", first_arg.Pair.head.Atom);
}

test "parseTerm — liste entre crochets" {
    const allocator = std.testing.allocator;
    var engine = KanrenEngine.init(allocator);
    defer engine.deinit();

    const t = engine.parseTerm("[a, b, c]");
    var count: usize = 0;
    var cursor = t;
    while (cursor == .Pair) : (cursor = cursor.Pair.tail) count += 1;
    try std.testing.expectEqual(@as(usize, 3), count);
}

test "walk — chaîne de substitutions" {
    const allocator = std.testing.allocator;
    var sub = Substitution.init(allocator);
    defer sub.deinit();

    try sub.bindings.put(1, .{ .Var = 2 });
    try sub.bindings.put(2, .{ .Var = 3 });
    try sub.bindings.put(3, .{ .Int = 42 });

    const walked = sub.walk(.{ .Var = 1 });
    try std.testing.expect(walked == .Int);
    try std.testing.expectEqual(@as(i64, 42), walked.Int);
}

test "walk — variable libre reste libre" {
    const allocator = std.testing.allocator;
    var sub = Substitution.init(allocator);
    defer sub.deinit();

    const walked = sub.walk(.{ .Var = 7 });
    try std.testing.expect(walked == .Var);
    try std.testing.expectEqual(@as(u32, 7), walked.Var);
}

test "parseListTerm — liste d'atomes" {
    const allocator = std.testing.allocator;
    var engine = KanrenEngine.init(allocator);
    defer engine.deinit();

    const t = engine.parseListTerm("a, b, c", null);
    try std.testing.expect(t == .Pair);
    try std.testing.expectEqualStrings("a", t.Pair.head.Atom);
    try std.testing.expectEqualStrings("b", t.Pair.tail.Pair.head.Atom);
    try std.testing.expectEqualStrings("c", t.Pair.tail.Pair.tail.Pair.head.Atom);
    try std.testing.expect(t.Pair.tail.Pair.tail.Pair.tail == .Nil);
}

test "parseListTerm — liste vide" {
    const allocator = std.testing.allocator;
    var engine = KanrenEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expect(engine.parseListTerm("", null) == .Nil);
}

test "parseListTerm — liste mixte" {
    const allocator = std.testing.allocator;
    var engine = KanrenEngine.init(allocator);
    defer engine.deinit();

    const t = engine.parseListTerm("X, 42, foo", null);
    try std.testing.expect(t.Pair.head == .Var);
    try std.testing.expect(t.Pair.tail.Pair.head == .Int);
    try std.testing.expectEqual(@as(i64, 42), t.Pair.tail.Pair.head.Int);
    try std.testing.expectEqualStrings("foo", t.Pair.tail.Pair.tail.Pair.head.Atom);
}

test "parseListTerm — liste impropre avec tail" {
    const allocator = std.testing.allocator;
    var engine = KanrenEngine.init(allocator);
    defer engine.deinit();

    const tail_term = Term.sym("T");
    const t = engine.parseListTerm("a, b", tail_term);
    try std.testing.expect(t.Pair.head == .Atom);
    try std.testing.expectEqualStrings("a", t.Pair.head.Atom);
    // Le tail final est bien T (pas Nil)
    const last = t.Pair.tail.Pair.tail;
    try std.testing.expect(last == .Atom);
    try std.testing.expectEqualStrings("T", last.Atom);
}

test "parseListTerm — liste imbriquée" {
    const allocator = std.testing.allocator;
    var engine = KanrenEngine.init(allocator);
    defer engine.deinit();

    const t = engine.parseListTerm("[a, b], c", null);
    // Premier élément = [a, b] (Pair)
    try std.testing.expect(t.Pair.head == .Pair);
    try std.testing.expectEqualStrings("a", t.Pair.head.Pair.head.Atom);
    // Second élément = c
    try std.testing.expectEqualStrings("c", t.Pair.tail.Pair.head.Atom);
}
