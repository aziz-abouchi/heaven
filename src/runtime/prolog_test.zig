const std = @import("std");
const prolog_lib = @import("prolog");
const matrix_lib = @import("matrix_lib");


fn allocationFailureAddFactDup(allocator: std.mem.Allocator) !void {
    var engine = prolog_lib.PrologEngine.init(allocator);
    defer engine.deinit();

    const args = [_][]const u8{"ada", "bob", "carol"};

    engine.addFactDup("allocation_test", &args) catch |err| {
        if (err != error.OutOfMemory) return err;
        try std.testing.expectEqual(@as(usize, 0), engine.clauses.items.len);
        return err;
    };

    try std.testing.expectEqual(@as(usize, 1), engine.clauses.items.len);
    try std.testing.expectEqual(@as(u8, 3), engine.clauses.items[0].head.arity);
}

fn allocationFailureAddRule(allocator: std.mem.Allocator) !void {
    var engine = prolog_lib.PrologEngine.init(allocator);
    defer engine.deinit();

    const head_args = [_][]const u8{"X", "Z"};
    const body = [_]prolog_lib.PrologAtom{
        .{
            .pred = "parent",
            .args = .{ "X", "Y", "", "", "", "", "", "" },
            .arity = 2,
        },
        .{
            .pred = "parent",
            .args = .{ "Y", "Z", "", "", "", "", "", "" },
            .arity = 2,
        },
    };

    engine.addRule("grandparent", &head_args, &body) catch |err| {
        if (err != error.OutOfMemory) return err;
        try std.testing.expectEqual(@as(usize, 0), engine.clauses.items.len);
        return err;
    };

    try std.testing.expectEqual(@as(usize, 1), engine.clauses.items.len);
    try std.testing.expectEqual(@as(u8, 2), engine.clauses.items[0].head.arity);
    try std.testing.expectEqual(@as(u8, 2), engine.clauses.items[0].body_len);
    try std.testing.expectEqualStrings("grandparent", engine.clauses.items[0].head.pred);
    try std.testing.expectEqualStrings("parent", engine.clauses.items[0].body[1].pred);
}

test "Prolog addRule gere tous les echecs d allocation" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        allocationFailureAddRule,
        .{},
    );
}

test "Prolog addFactDup gere tous les echecs d allocation" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        allocationFailureAddFactDup,
        .{},
    );
}

test "Prolog addFactDup accepte huit arguments" {
    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    const args = [_][]const u8{
        "a", "b", "c", "d", "e", "f", "g", "h",
    };

    try engine.addFactDup("eight", &args);

    try std.testing.expectEqual(@as(usize, 1), engine.clauses.items.len);
    try std.testing.expectEqual(@as(u8, 8), engine.clauses.items[0].head.arity);
    try std.testing.expectEqualStrings("h", engine.clauses.items[0].head.args[7]);
}

test "Prolog addFactDup conserve ses propres copies" {
    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    const pred = try std.testing.allocator.dupe(u8, "temporary_predicate");
    defer std.testing.allocator.free(pred);

    const arg = try std.testing.allocator.dupe(u8, "temporary_value");
    defer std.testing.allocator.free(arg);

    const args = [_][]const u8{arg};
    try engine.addFactDup(pred, &args);

    try std.testing.expectEqualStrings(
        "temporary_predicate",
        engine.clauses.items[0].head.pred,
    );
    try std.testing.expectEqualStrings(
        "temporary_value",
        engine.clauses.items[0].head.args[0],
    );
}

test "Prolog charge les faits et règles depuis Matrix" {
    var matrix = matrix_lib.Matrix.init(std.testing.allocator);
    defer matrix.deinit();

    _ = try matrix.addUniqueSymbol("FACT:father(ada,bob)");
    _ = try matrix.addUniqueSymbol("RULE:parent(X,Y) :- father(X,Y)");

    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    try engine.loadFromMatrix(&matrix);

    try std.testing.expect(engine.loaded);
    try std.testing.expectEqual(@as(usize, 2), engine.clauses.items.len);

    var found_fact = false;
    var found_rule = false;

    for (engine.clauses.items) |clause| {
        if (std.mem.eql(u8, clause.head.pred, "father")) {
            found_fact = true;
            try std.testing.expectEqual(@as(u8, 0), clause.body_len);
        } else if (std.mem.eql(u8, clause.head.pred, "parent")) {
            found_rule = true;
            try std.testing.expectEqual(@as(u8, 1), clause.body_len);
            try std.testing.expectEqualStrings("father", clause.body[0].pred);
        }
    }

    try std.testing.expect(found_fact);
    try std.testing.expect(found_rule);
}


test "Prolog addFactDup rejette un predicat vide sans insertion" {
    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    const args = [_][]const u8{"ada"};
    try std.testing.expectError(error.InvalidFact, engine.addFactDup("", &args));
    try std.testing.expectEqual(@as(usize, 0), engine.clauses.items.len);
}

test "Prolog addFactDup rejette un argument vide sans insertion" {
    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    const args = [_][]const u8{"ada", ""};
    try std.testing.expectError(error.InvalidFact, engine.addFactDup("parent", &args));
    try std.testing.expectEqual(@as(usize, 0), engine.clauses.items.len);
}

test "Prolog addRule rejette un predicat vide sans insertion" {
    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    const head_args = [_][]const u8{"X"};
    const body = [_]prolog_lib.PrologAtom{
        .{
            .pred = "parent",
            .args = .{ "X", "", "", "", "", "", "", "" },
            .arity = 1,
        },
    };

    try std.testing.expectError(error.InvalidRule, engine.addRule("", &head_args, &body));
    try std.testing.expectEqual(@as(usize, 0), engine.clauses.items.len);
}

test "Prolog addRule rejette un argument vide dans le corps sans insertion" {
    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    const head_args = [_][]const u8{"X"};
    const body = [_]prolog_lib.PrologAtom{
        .{
            .pred = "parent",
            .args = .{ "X", "", "", "", "", "", "", "" },
            .arity = 2,
        },
    };

    try std.testing.expectError(error.InvalidRule, engine.addRule("target", &head_args, &body));
    try std.testing.expectEqual(@as(usize, 0), engine.clauses.items.len);
}

test "Prolog rejette les predicats et arguments espaces ou tabulations" {
    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    const no_args = [_][]const u8{};
    const tab_arg = [_][]const u8{"\t"};

    try std.testing.expectError(error.InvalidFact, engine.addFactDup(" \t", &no_args));
    try std.testing.expectError(error.InvalidFact, engine.addFactDup("parent", &tab_arg));

    const head_args = [_][]const u8{"\t"};
    const body = [_]prolog_lib.PrologAtom{};

    try std.testing.expectError(error.InvalidRule, engine.addRule("target", &head_args, &body));
    try std.testing.expectEqual(@as(usize, 0), engine.clauses.items.len);
}

test "Prolog addFactDup rejette plus de huit arguments sans insertion" {
    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    const args = [_][]const u8{"a", "b", "c", "d", "e", "f", "g", "h", "i"};
    try std.testing.expectError(error.TooManyArguments, engine.addFactDup("nine", &args));
    try std.testing.expectEqual(@as(usize, 0), engine.clauses.items.len);
}

fn allocationFailureParseRule(allocator: std.mem.Allocator) !void {
    var engine = prolog_lib.PrologEngine.init(allocator);
    defer engine.deinit();

    engine.parseRule("grandparent(X,Z) :- parent(X,Y), parent(Y,Z)") catch |err| {
        if (err != error.OutOfMemory) return err;
        try std.testing.expectEqual(@as(usize, 0), engine.clauses.items.len);
        return err;
    };

    try std.testing.expectEqual(@as(usize, 1), engine.clauses.items.len);
    try std.testing.expectEqual(@as(u8, 2), engine.clauses.items[0].head.arity);
    try std.testing.expectEqual(@as(u8, 2), engine.clauses.items[0].body_len);
    try std.testing.expectEqualStrings("grandparent", engine.clauses.items[0].head.pred);
    try std.testing.expectEqualStrings("parent", engine.clauses.items[0].body[0].pred);
    try std.testing.expectEqualStrings("parent", engine.clauses.items[0].body[1].pred);
}

test "Prolog parseRule gere tous les echecs d allocation" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        allocationFailureParseRule,
        .{},
    );
}

test "Prolog parseRule rejette une règle mal formée sans insertion" {
    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    try std.testing.expectError(error.InvalidRule, engine.parseRule("parent(X,Y) :- father(X,Y),"));
    try std.testing.expectEqual(@as(usize, 0), engine.clauses.items.len);
}

test "Prolog parseRule rejette plus de huit atomes dans le corps" {
    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    try std.testing.expectError(
        error.TooManyBodyAtoms,
        engine.parseRule("target(X) :- a(X), b(X), c(X), d(X), e(X), f(X), g(X), h(X), i(X)"),
    );
    try std.testing.expectEqual(@as(usize, 0), engine.clauses.items.len);
}

test "Prolog loadFromMatrix annule le chargement après une insertion partielle" {
    var exercised_rollback = false;

    for (0..1024) |attempt| {
        var matrix = matrix_lib.Matrix.init(std.testing.allocator);
        defer matrix.deinit();

        for (0..64) |i| {
            var valid_buf: [64]u8 = undefined;
            const valid_label = try std.fmt.bufPrint(
                &valid_buf,
                "FACT:valid_{d}(ada,bob)",
                .{i},
            );
            _ = try matrix.addUniqueSymbol(valid_label);
        }

        var invalid_buf: [64]u8 = undefined;
        const invalid_label = try std.fmt.bufPrint(
            &invalid_buf,
            "FACT:malformed_{d}",
            .{attempt},
        );
        _ = try matrix.addUniqueSymbol(invalid_label);

        var valid_seen = false;
        var invalid_after_valid = false;
        var it = matrix.symbol_index.iterator();

        while (it.next()) |entry| {
            const sym = entry.key_ptr.*;
            if (std.mem.startsWith(u8, sym, "FACT:valid_")) {
                valid_seen = true;
            } else if (std.mem.startsWith(u8, sym, "FACT:malformed_")) {
                invalid_after_valid = valid_seen;
                break;
            }
        }

        if (!invalid_after_valid) continue;

        var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
        defer engine.deinit();

        const existing_args = [_][]const u8{"preserved"};
        try engine.addFactDup("existing", &existing_args);

        try std.testing.expectError(
            error.InvalidFact,
            engine.loadFromMatrix(&matrix),
        );
        try std.testing.expect(!engine.loaded);
        try std.testing.expectEqual(@as(usize, 1), engine.clauses.items.len);
        try std.testing.expectEqualStrings("existing", engine.clauses.items[0].head.pred);
        try std.testing.expectEqualStrings("preserved", engine.clauses.items[0].head.args[0]);

        try std.testing.expectError(
            error.InvalidFact,
            engine.loadFromMatrix(&matrix),
        );
        try std.testing.expect(!engine.loaded);
        try std.testing.expectEqual(@as(usize, 1), engine.clauses.items.len);
        try std.testing.expectEqualStrings("existing", engine.clauses.items[0].head.pred);
        try std.testing.expectEqualStrings("preserved", engine.clauses.items[0].head.args[0]);

        exercised_rollback = true;
        break;
    }

    try std.testing.expect(exercised_rollback);
}


fn allocationFailureLoadFromMatrix(allocator: std.mem.Allocator) !void {
    // La matrice utilise l'allocateur normal : seuls les appels du moteur
    // Prolog sont soumis à l'injection d'échecs.
    var matrix = matrix_lib.Matrix.init(std.testing.allocator);
    defer matrix.deinit();

    for (0..32) |i| {
        var buf: [64]u8 = undefined;
        const label = try std.fmt.bufPrint(
            &buf,
            "FACT:allocation_{d}(ada,bob)",
            .{i},
        );
        _ = try matrix.addUniqueSymbol(label);
    }

    _ = try matrix.addUniqueSymbol(
        "RULE:grandparent(X,Z) :- parent(X,Y), parent(Y,Z)",
    );

    var engine = prolog_lib.PrologEngine.init(allocator);
    defer engine.deinit();

    const existing_args = [_][]const u8{"preserved"};
    try engine.addFactDup("existing", &existing_args);

    engine.loadFromMatrix(&matrix) catch |err| {
        if (err != error.OutOfMemory) return err;

        try std.testing.expect(!engine.loaded);
        try std.testing.expectEqual(@as(usize, 1), engine.clauses.items.len);
        try std.testing.expectEqualStrings("existing", engine.clauses.items[0].head.pred);
        try std.testing.expectEqualStrings("preserved", engine.clauses.items[0].head.args[0]);
        return err;
    };

    try std.testing.expect(engine.loaded);
    try std.testing.expectEqual(@as(usize, 34), engine.clauses.items.len);
    try std.testing.expectEqualStrings("existing", engine.clauses.items[0].head.pred);
    try std.testing.expectEqualStrings("preserved", engine.clauses.items[0].head.args[0]);
}

test "Prolog loadFromMatrix gere tous les echecs d allocation" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        allocationFailureLoadFromMatrix,
        .{},
    );
}
