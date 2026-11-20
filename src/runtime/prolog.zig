const std = @import("std");
const matrix_lib = @import("matrix_lib");
const platform = @import("platform");

pub const PrologAtom = struct {
    pred: []const u8,
    args: [8][]const u8,
    arity: u8,
};

pub const Substitution = struct {
    bindings: [32]struct { name: []const u8, value: []const u8 },
    count: u8,

    fn init() Substitution {
        return .{ .bindings = undefined, .count = 0 };
    }

    fn get(self: *const Substitution, name: []const u8) ?[]const u8 {
        var i: u8 = 0;
        while (i < self.count) : (i += 1) {
            if (std.mem.eql(u8, self.bindings[i].name, name)) return self.bindings[i].value;
        }
        return null;
    }

    fn put(self: *Substitution, name: []const u8, value: []const u8) bool {
        if (self.count >= 32) return false;
        if (self.get(name)) |existing| return std.mem.eql(u8, existing, value);
        self.bindings[self.count] = .{ .name = name, .value = value };
        self.count += 1;
        return true;
    }

    pub fn resolve(self: *const Substitution, term: []const u8) []const u8 {
        var current = term;
        var attempts: u8 = 0;
        while (attempts < 20) : (attempts += 1) {
            if (current.len == 0 or current[0] < 'A' or current[0] > 'Z') return current;
            if (self.get(current)) |val| {
                if (std.mem.eql(u8, val, current)) return current;
                current = val;
            } else return current;
        }
        return current;
    }

    pub fn printClean(self: Substitution) void {
        var i: u8 = 0;
        var first = true;
        while (i < self.count) : (i += 1) {
            const name = self.bindings[i].name;
            if (name.len == 0) continue;
            // Seulement les variables originales (majuscule, sans _)
            if (name[0] < 'A' or name[0] > 'Z') continue;
            if (std.mem.indexOf(u8, name, "_") != null) continue;

            const value = self.resolve(self.bindings[i].value);
            // Skip si la valeur est une variable interne
            // if (value.len > 0 and std.mem.indexOf(u8, value, "_") != null) continue;
            // Skip si la valeur est vide ou encore une variable non résolue
            if (value.len == 0) continue;
            if (value[0] >= 'A' and value[0] <= 'Z') continue;

            if (!first) platform.debug.print(", ", .{});
            platform.debug.print("{s} = {s}", .{ name, value });
            first = false;
        }
        if (first) platform.debug.print("true", .{});
    }
};

pub const Clause = struct {
    head: PrologAtom,
    body: [8]PrologAtom,
    body_len: u8,
};

pub const PrologEngine = struct {
    clauses: std.ArrayListUnmanaged(Clause),
    allocator: std.mem.Allocator,
    loaded: bool,
    rename_counter: u32,
    rename_bufs: [256][32]u8,

    pub fn init(alloc: std.mem.Allocator) PrologEngine {
        return .{ .clauses = .{}, .allocator = alloc, .loaded = false, .rename_counter = 0, .rename_bufs = undefined };
    }

    fn freeAtom(self: *PrologEngine, atom: PrologAtom) void {
        self.allocator.free(atom.pred);
        for (atom.args[0..atom.arity]) |arg| {
            self.allocator.free(arg);
        }
    }

    fn freeClause(self: *PrologEngine, clause: Clause) void {
        self.freeAtom(clause.head);
        for (clause.body[0..clause.body_len]) |atom| {
            self.freeAtom(atom);
        }
    }

    fn dupeAtom(self: *PrologEngine, source: PrologAtom) !PrologAtom {
        if (source.arity > 8) return error.TooManyArguments;
        if (std.mem.trim(u8, source.pred, " \t").len == 0)
            return error.InvalidAtom;

        for (source.args[0..source.arity]) |arg| {
            if (std.mem.trim(u8, arg, " \t").len == 0)
                return error.InvalidAtom;
        }

        const pred = try self.allocator.dupe(u8, source.pred);
        errdefer self.allocator.free(pred);

        var result: PrologAtom = .{
            .pred = pred,
            .args = undefined,
            .arity = source.arity,
        };
        var copied: usize = 0;
        errdefer {
            for (result.args[0..copied]) |arg| self.allocator.free(arg);
        }

        while (copied < source.arity) : (copied += 1) {
            result.args[copied] = try self.allocator.dupe(u8, source.args[copied]);
        }
        while (copied < 8) : (copied += 1) result.args[copied] = "";

        return result;
    }

    pub fn loadFromMatrix(self: *PrologEngine, matrix: *matrix_lib.Matrix) !void {
        if (self.loaded) return;

        const initial_len = self.clauses.items.len;
        errdefer {
            while (self.clauses.items.len > initial_len) {
                const last = self.clauses.items[self.clauses.items.len - 1];
                self.freeClause(last);
                self.clauses.items = self.clauses.items[0 .. self.clauses.items.len - 1];
            }
        }

        var it = matrix.symbol_index.iterator();
        while (it.next()) |entry| {
            const sym = entry.key_ptr.*;
            if (std.mem.startsWith(u8, sym, "FACT:")) {
                try self.parseFact(sym[5..]);
            } else if (std.mem.startsWith(u8, sym, "RULE:")) {
                try self.parseRule(sym[5..]);
            }
        }

        self.loaded = true;
    }

    fn parseFact(self: *PrologEngine, text: []const u8) !void {
        const atom_raw = self.parseAtomStr(text) orelse return error.InvalidFact;
        const atom = try self.dupeAtom(atom_raw);
        errdefer self.freeAtom(atom);
        try self.clauses.append(self.allocator, .{
            .head = atom,
            .body = undefined,
            .body_len = 0,
        });
    }

    /// Libere toutes les clauses (pred + args). A appeler dans Shell.deinit.
    pub fn deinit(self: *PrologEngine) void {
        for (self.clauses.items) |clause| {
            self.freeClause(clause);
        }
        self.clauses.deinit(self.allocator);
    }

    pub fn parseRule(self: *PrologEngine, text: []const u8) !void {
        const sep = std.mem.indexOf(u8, text, ":-") orelse return error.InvalidRule;
        const head_str = std.mem.trim(u8, text[0..sep], " \t");
        var rest_body = std.mem.trim(u8, text[sep + 2 ..], " \t");

        const head_raw = self.parseAtomStr(head_str) orelse return error.InvalidRule;
        const head = try self.dupeAtom(head_raw);
        var clause: Clause = .{
            .head = head,
            .body = undefined,
            .body_len = 0,
        };
        errdefer {
            self.freeAtom(clause.head);
            for (clause.body[0..clause.body_len]) |atom| self.freeAtom(atom);
        }

        if (rest_body.len == 0) return error.InvalidRule;

        while (rest_body.len > 0) {
            if (clause.body_len >= 8) return error.TooManyBodyAtoms;

            const close = std.mem.indexOfScalar(u8, rest_body, ')') orelse return error.InvalidRule;
            const atom_text = std.mem.trim(u8, rest_body[0 .. close + 1], " \t");
            const atom_raw = self.parseAtomStr(atom_text) orelse return error.InvalidRule;
            const atom = try self.dupeAtom(atom_raw);

            clause.body[clause.body_len] = atom;
            clause.body_len += 1;

            const after = std.mem.trim(u8, rest_body[close + 1 ..], " \t");
            if (after.len == 0) break;
            if (after[0] != ',') return error.InvalidRule;
            rest_body = std.mem.trim(u8, after[1..], " \t");
            if (rest_body.len == 0) return error.InvalidRule;
        }

        try self.clauses.append(self.allocator, clause);
    }

    fn parseAtomStr(self: *PrologEngine, str: []const u8) ?PrologAtom {
        _ = self;
        const input = std.mem.trim(u8, str, " \t");
        const paren_start = std.mem.indexOf(u8, input, "(") orelse return null;
        const paren_end = std.mem.lastIndexOf(u8, input, ")") orelse return null;
        if (paren_end <= paren_start or paren_end != input.len - 1) return null;

        const pred = std.mem.trim(u8, input[0..paren_start], " \t");
        if (pred.len == 0) return null;

        const args_str = input[paren_start + 1 .. paren_end];
        var atom: PrologAtom = .{ .pred = pred, .args = undefined, .arity = 0 };
        for (&atom.args) |*arg| arg.* = "";

        if (args_str.len == 0) return atom;

        var it = std.mem.splitScalar(u8, args_str, ',');
        while (it.next()) |part| {
            const arg = std.mem.trim(u8, part, " \t");
            if (arg.len == 0 or atom.arity >= 8) return null;
            atom.args[atom.arity] = arg;
            atom.arity += 1;
        }
        return atom;
    }

    /// Variante de `addFact` qui duplique les strings (utile pour les
    /// faits ajoutes interactivement, dont les slices peuvent etre
    /// ephemeres).
    pub fn addFactDup(self: *PrologEngine, pred: []const u8, args: []const []const u8) !void {
        if (args.len > 8) return error.TooManyArguments;
        if (std.mem.trim(u8, pred, " \t").len == 0) return error.InvalidFact;
        for (args) |arg| {
            if (std.mem.trim(u8, arg, " \t").len == 0)
                return error.InvalidFact;
        }

        var raw: PrologAtom = .{ .pred = pred, .args = undefined, .arity = @intCast(args.len) };
        for (args, 0..) |arg, i| raw.args[i] = arg;
        var i = args.len;
        while (i < 8) : (i += 1) raw.args[i] = "";

        const atom = try self.dupeAtom(raw);
        errdefer self.freeAtom(atom);
        try self.clauses.append(self.allocator, .{
            .head = atom,
            .body = undefined,
            .body_len = 0,
        });
    }

    pub fn addFact(self: *PrologEngine, pred: []const u8, args: []const []const u8) !void {
        return self.addFactDup(pred, args);
    }

    pub fn addRule(self: *PrologEngine, pred: []const u8, head_args: []const []const u8, body: []const PrologAtom) !void {
        if (head_args.len > 8) return error.TooManyArguments;
        if (body.len > 8) return error.TooManyBodyAtoms;
        if (std.mem.trim(u8, pred, " \t").len == 0) return error.InvalidRule;

        for (head_args) |arg| {
            if (std.mem.trim(u8, arg, " \t").len == 0)
                return error.InvalidRule;
        }
        for (body) |source| {
            if (std.mem.trim(u8, source.pred, " \t").len == 0)
                return error.InvalidRule;
            if (source.arity > 8) return error.TooManyArguments;
            for (source.args[0..source.arity]) |arg| {
                if (std.mem.trim(u8, arg, " \t").len == 0)
                    return error.InvalidRule;
            }
        }

        var raw_head: PrologAtom = .{
            .pred = pred,
            .args = undefined,
            .arity = @intCast(head_args.len),
        };
        for (head_args, 0..) |arg, i| raw_head.args[i] = arg;
        var i = head_args.len;
        while (i < 8) : (i += 1) raw_head.args[i] = "";

        const head = try self.dupeAtom(raw_head);
        var clause: Clause = .{
            .head = head,
            .body = undefined,
            .body_len = 0,
        };
        errdefer {
            self.freeAtom(clause.head);
            for (clause.body[0..clause.body_len]) |atom| self.freeAtom(atom);
        }

        for (body) |source| {
            const atom = try self.dupeAtom(source);
            clause.body[clause.body_len] = atom;
            clause.body_len += 1;
        }
        try self.clauses.append(self.allocator, clause);
    }

    pub fn parseAtom(self: *PrologEngine, str: []const u8) ?PrologAtom {
        return self.parseAtomStr(str);
    }

    pub fn solve(self: *PrologEngine, goal: PrologAtom, alloc: std.mem.Allocator) std.ArrayListUnmanaged(Substitution) {
        self.rename_counter = 0;
        var results: std.ArrayListUnmanaged(Substitution) = .{};
        var sub = Substitution.init();
        self.solveGoal(goal, &sub, &results, 0, alloc);
        return results;
    }

    fn solveGoal(self: *PrologEngine, goal: PrologAtom, sub: *Substitution, results: *std.ArrayListUnmanaged(Substitution), depth: u32, alloc: std.mem.Allocator) void {
        if (depth > 30) return;
        if (results.items.len >= 20) return;

        for (self.clauses.items) |clause| {
            if (results.items.len >= 20) return;
            if (!std.mem.eql(u8, clause.head.pred, goal.pred)) continue;
            if (clause.head.arity != goal.arity) continue;

            self.rename_counter += 1;
            const rc = self.rename_counter;
            const renamed_head = self.renameAtom(clause.head, rc);
            var renamed_body: [8]PrologAtom = undefined;
            var bi: u8 = 0;
            while (bi < clause.body_len) : (bi += 1) {
                renamed_body[bi] = self.renameAtom(clause.body[bi], rc);
            }

            var new_sub = sub.*;
            if (unifyAtom(goal, renamed_head, &new_sub)) {
                if (clause.body_len == 0) {
                    results.append(alloc, new_sub) catch {};
                } else {
                    self.solveBody(renamed_body[0..clause.body_len], &new_sub, results, depth + 1, alloc, goal);
                }
            }
        }
    }

    fn solveBody(self: *PrologEngine, goals: []const PrologAtom, sub: *Substitution, results: *std.ArrayListUnmanaged(Substitution), depth: u32, alloc: std.mem.Allocator, original_goal: PrologAtom) void {
        _ = original_goal;
        if (goals.len == 0) {
            results.append(alloc, sub.*) catch {};
            return;
        }
        if (results.items.len >= 20) return;

        const first = applySubAtom(goals[0], sub);

        var sub_results: std.ArrayListUnmanaged(Substitution) = .{};
        defer sub_results.deinit(alloc);
        self.solveGoal(first, sub, &sub_results, depth, alloc);

        for (sub_results.items) |*sol| {
            if (results.items.len >= 20) return;
            self.solveBody(goals[1..], sol, results, depth, alloc, .{ .pred = "", .args = undefined, .arity = 0 });
        }
    }

    fn renameAtom(self: *PrologEngine, atom: PrologAtom, counter: u32) PrologAtom {
        var result = atom;
        var i: u8 = 0;
        while (i < atom.arity) : (i += 1) {
            if (isVariable(atom.args[i])) {
                const buf_idx = (hashVarName(atom.args[i]) *% 17 +% counter) % 256;
                const written = std.fmt.bufPrint(&self.rename_bufs[buf_idx], "{s}_{d}", .{ atom.args[i], counter }) catch atom.args[i];
                result.args[i] = written;
            }
        }
        return result;
    }

    fn hashVarName(name: []const u8) u32 {
        if (name.len == 0) return 0;
        return @as(u32, name[0] - 'A');
    }

    fn unifyAtom(goal: PrologAtom, head: PrologAtom, sub: *Substitution) bool {
        var i: u8 = 0;
        while (i < goal.arity) : (i += 1) {
            const g = sub.resolve(goal.args[i]);
            const h = sub.resolve(head.args[i]);

            if (std.mem.eql(u8, g, h)) continue;

            if (isVariable(h) and isVariable(g)) {
                if (std.mem.indexOf(u8, h, "_") != null) {
                    if (!sub.put(g, h)) return false;
                } else if (std.mem.indexOf(u8, g, "_") != null) {
                    if (!sub.put(h, g)) return false;
                } else {
                    if (!sub.put(g, h)) return false;
                }
            } else if (isVariable(h)) {
                if (!sub.put(h, g)) return false;
            } else if (isVariable(g)) {
                if (!sub.put(g, h)) return false;
            } else {
                return false;
            }
        }
        return true;
    }

    fn applySubAtom(atom: PrologAtom, sub: *Substitution) PrologAtom {
        var result = atom;
        var i: u8 = 0;
        while (i < atom.arity) : (i += 1) {
            result.args[i] = sub.resolve(atom.args[i]);
        }
        return result;
    }

    fn isVariable(term: []const u8) bool {
        if (term.len == 0) return false;
        return term[0] >= 'A' and term[0] <= 'Z';
    }
};
