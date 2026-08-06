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

    pub fn loadFromMatrix(self: *PrologEngine, matrix: *matrix_lib.Matrix) void {
        if (self.loaded) return;
        self.loaded = true;

        var it = matrix.symbol_index.iterator();
        while (it.next()) |entry| {
            const sym = entry.key_ptr.*;
            if (std.mem.startsWith(u8, sym, "FACT:")) {
                self.parseFact(sym[5..]);
            } else if (std.mem.startsWith(u8, sym, "RULE:")) {
                self.parseRule(sym[5..]);
            }
        }
    }

    fn parseFact(self: *PrologEngine, text: []const u8) void {
        const atom = self.parseAtomStr(text) orelse return;
        self.clauses.append(self.allocator, .{ .head = atom, .body = undefined, .body_len = 0 }) catch {};
    }

    fn parseRule(self: *PrologEngine, text: []const u8) void {
        const sep = std.mem.indexOf(u8, text, ":-") orelse return;
        const head_str = std.mem.trim(u8, text[0..sep], " ");
        const body_str = std.mem.trim(u8, text[sep + 2 ..], " ");

        const head = self.parseAtomStr(head_str) orelse return;
        var clause: Clause = .{ .head = head, .body = undefined, .body_len = 0 };

        var rest_body = body_str;
        while (rest_body.len > 0) {
            const close = std.mem.indexOfScalar(u8, rest_body, ')') orelse break;
            const atom_str = std.mem.trim(u8, rest_body[0 .. close + 1], " ");

            if (close + 1 < rest_body.len) {
                const after = rest_body[close + 1 ..];
                const comma = std.mem.indexOfScalar(u8, after, ',');
                if (comma) |ci| {
                    rest_body = std.mem.trim(u8, after[ci + 1 ..], " ");
                } else {
                    rest_body = "";
                }
            } else {
                rest_body = "";
            }

            if (self.parseAtomStr(atom_str)) |atom| {
                if (clause.body_len < 8) {
                    clause.body[clause.body_len] = atom;
                    clause.body_len += 1;
                }
            }
        }

        self.clauses.append(self.allocator, clause) catch {};
    }

    fn parseAtomStr(self: *PrologEngine, str: []const u8) ?PrologAtom {
        _ = self;
        const paren_start = std.mem.indexOf(u8, str, "(") orelse return null;
        const paren_end = std.mem.lastIndexOf(u8, str, ")") orelse return null;
        if (paren_end <= paren_start) return null;

        const pred = std.mem.trim(u8, str[0..paren_start], " ");
        if (pred.len == 0) return null;

        const args_str = str[paren_start + 1 .. paren_end];

        var atom: PrologAtom = .{ .pred = pred, .args = undefined, .arity = 0 };
        var ai: usize = 0;
        while (ai < 8) : (ai += 1) atom.args[ai] = "";

        var arg_it = std.mem.tokenizeAny(u8, args_str, ",");
        while (arg_it.next()) |arg| {
            if (atom.arity >= 8) break;
            atom.args[atom.arity] = std.mem.trim(u8, arg, " ");
            atom.arity += 1;
        }

        return atom;
    }

    pub fn addFact(self: *PrologEngine, pred: []const u8, args: []const []const u8) void {
        var atom: PrologAtom = .{ .pred = pred, .args = undefined, .arity = @intCast(args.len) };
        for (args, 0..) |a, i| atom.args[i] = a;
        var i: usize = args.len;
        while (i < 8) : (i += 1) atom.args[i] = "";
        self.clauses.append(self.allocator, .{ .head = atom, .body = undefined, .body_len = 0 }) catch {};
    }

    pub fn addRule(self: *PrologEngine, pred: []const u8, head_args: []const []const u8, body: []const PrologAtom) void {
        var head: PrologAtom = .{ .pred = pred, .args = undefined, .arity = @intCast(head_args.len) };
        for (head_args, 0..) |a, i| head.args[i] = a;
        var i: usize = head_args.len;
        while (i < 8) : (i += 1) head.args[i] = "";
        var clause: Clause = .{ .head = head, .body = undefined, .body_len = @intCast(body.len) };
        for (body, 0..) |b, bi| clause.body[bi] = b;
        self.clauses.append(self.allocator, clause) catch {};
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
