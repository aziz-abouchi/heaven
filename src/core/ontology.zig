const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;

/// ═══════════════════════════════════════════════════
/// L2 — ONTOLOGIE COMPUTATIONNELLE
/// Concepts, propriétés, subsomption, complexité
/// ═══════════════════════════════════════════════════
pub const Complexity = enum {
    constant, // O(1)
    logarithmic, // O(log n)
    linear, // O(n)
    linearithmic, // O(n log n)
    quadratic, // O(n²)
    cubic, // O(n³)
    exponential, // O(2ⁿ)
    factorial, // O(n!)
    unknown,

    pub fn format(self: Complexity) []const u8 {
        return switch (self) {
            .constant => "O(1)",
            .logarithmic => "O(log n)",
            .linear => "O(n)",
            .linearithmic => "O(n log n)",
            .quadratic => "O(n\xc2\xb2)",
            .cubic => "O(n\xc2\xb3)",
            .exponential => "O(2\xe2\x81\xbf)",
            .factorial => "O(n!)",
            .unknown => "O(?)",
        };
    }

    pub fn le(a: Complexity, b: Complexity) bool {
        return @intFromEnum(a) <= @intFromEnum(b);
    }

    pub fn lt(a: Complexity, b: Complexity) bool {
        return @intFromEnum(a) < @intFromEnum(b);
    }
};

pub const StackUsage = enum {
    constant, // constant stack (iterative) O(1)
    linear, // linear stack (recursive) O(n),
    logarithmic, // logarithmic stack (divide & conquer) O(log n),
    unknown,

    pub fn format(self: StackUsage) []const u8 {
        return switch (self) {
            .constant => "stack O(1)",
            .linear => "stack O(n)",
            .logarithmic => "stack O(log n)",
            .unknown => "stack O(?)",
        };
    }
};

pub const AlgoProperty = struct {
    name: []const u8,
    time: Complexity,
    space: StackUsage,
    is_tail_recursive: bool,
    is_parallelizable: bool,
    domain_constraint: ?[]const u8, // e.g. "n > 0", "n >= 0"

    pub fn dominates(self: AlgoProperty, other: AlgoProperty) bool {
        // self dominates other if same or better in all dimensions
        return Complexity.le(self.time, other.time) and
            (@intFromEnum(self.space) <= @intFromEnum(other.space));
    }
};

/// A Concept in the ontology
pub const Concept = struct {
    name: []const u8,
    parent: ?[]const u8,
    // superclass (is-a)
    properties: [8]?Property,
    num_props: u8,
    algorithms: [16]?AlgoProperty,
    num_algos: u8,
};

pub const Property = struct {
    name: []const u8,
    domain: []const u8,
    range: []const u8,
    constraint: ?[]const u8,
};

/// ═══════════════════════════════════════════════════
/// ONTOLOGY ENGINE
/// ═══════════════════════════════════════════════════
pub const Ontology = struct {
    allocator: Allocator,
    concepts: std.StringHashMapUnmanaged(Concept),
    equiv_classes: std.StringHashMapUnmanaged(std.ArrayListUnmanaged([]const u8)),

    pub fn init(allocator: Allocator) Ontology {
        return .{
            .allocator = allocator,
            .concepts = .{},
            .equiv_classes = .{},
        };
    }

    pub fn deinit(self: *Ontology) void {
        // 1. Libérer les concepts (clés et parents)
        var it = self.concepts.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*); // Libère name_dupe
            if (entry.value_ptr.parent) |p| {
                self.allocator.free(p); // Libère parent_dupe
            }
        }
        self.concepts.deinit(self.allocator);

        // 2. Libérer les listes d'équivalents
        // Attention : on ne libère pas les clés de equiv_classes car elles pointent
        // vers les mêmes chaînes que les noms de concepts (qu'on a déjà libérées ci-dessus).
        // On ne libère pas non plus les items de la liste car ce sont des string literals pour l'instant.
        var equiv_it = self.equiv_classes.iterator();
        while (equiv_it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator); // Libère la mémoire de l'ArrayList
        }
        self.equiv_classes.deinit(self.allocator);
    }

    // ─── Concepts ───
    pub fn defineConcept(self: *Ontology, name: []const u8, parent: ?[]const u8) !void {
        const name_dupe = try self.allocator.dupe(u8, name);
        const parent_dupe = if (parent) |p| try self.allocator.dupe(u8, p) else null;
        const c = Concept{
            .name = name_dupe,
            .parent = parent_dupe,

            .properties = [_]?Property{null} ** 8,
            .num_props = 0,
            .algorithms = [_]?AlgoProperty{null} ** 16,
            .num_algos = 0,
        };
        _ = c;
        try self.concepts.put(self.allocator, name_dupe, .{
            .name = name_dupe,
            .parent = parent_dupe,
            .properties = [_]?Property{null} ** 8,
            .num_props = 0,
            .algorithms = [_]?AlgoProperty{null} ** 16,
            .num_algos = 0,
        });
    }

    // ─── Subsomption (is-a) ───

    pub fn isA(self: *Ontology, child: []const u8, ancestor: []const u8) bool {
        if (std.mem.eql(u8, child, ancestor)) return true;
        const concept = self.concepts.get(child) orelse return false;
        if (concept.parent) |p| {
            return self.isA(p, ancestor);
        }
        return false;
    }

    // ─── Algorithm Registration ───

    pub fn registerAlgo(self: *Ontology, concept_name: []const u8, algo: AlgoProperty) !void {
        if (self.concepts.getPtr(concept_name)) |c| {
            if (c.num_algos < 16) {
                c.algorithms[c.num_algos] = algo;
                c.num_algos += 1;
            }
        }
    }

    // ─── Equivalence Classes ───

    pub fn declareEquivalent(self: *Ontology, class_name: []const u8, expr_str: []const u8) !void {
        const result = try self.equiv_classes.getOrPut(self.allocator, class_name);
        if (!result.found_existing) {
            result.value_ptr.* = .{};
        }
        try result.value_ptr.append(self.allocator, expr_str);
    }

    pub fn getEquivalents(self: *Ontology, class_name: []const u8) ?[]const []const u8 {
        if (self.equiv_classes.get(class_name)) |list| {
            return list.items;
        }
        return null;
    }

    // ─── L3: Optimiser — Choose Best Algorithm ───

    pub fn chooseBest(self: *Ontology, concept_name: []const u8, context: OptContext) ?AlgoProperty {
        const concept = self.concepts.get(concept_name) orelse return null;
        var best: ?AlgoProperty = null;
        var best_score: i32 = -1000;

        var i: u8 = 0;
        while (i < concept.num_algos) : (i += 1) {
            if (concept.algorithms[i]) |algo| {
                const score = self.scoreAlgo(algo, context);
                if (score > best_score) {
                    best_score = score;
                    best = algo;
                }
            }
        }
        return best;
    }

    fn scoreAlgo(_: *Ontology, algo: AlgoProperty, ctx: OptContext) i32 {
        var score: i32 = 0;

        // Time complexity score (lower is better)
        // Exponential penalty for worse time complexity
        const time_val = @as(i32, @intFromEnum(algo.time));
        score -= time_val * time_val * 10;

        // Stack usage matters for large n
        if (ctx.expected_n > 10000) {
            if (algo.space == .constant) score += 50;
            if (algo.space == .linear) score -= 50;
        }

        // Parallelism bonus
        if (ctx.has_gpu and algo.is_parallelizable) score += 30;

        // Tail recursion bonus (no stack overflow)
        if (algo.is_tail_recursive) score += 20;

        // Small n: prefer simpler code
        if (ctx.expected_n < 20) score += 10;

        // Domain constraint check
        if (algo.domain_constraint) |dc| {
            if (std.mem.eql(u8, dc, "n > 0") and ctx.expected_n == 0) {
                score -= 1000; // Invalid for this input
            }
        }

        return score;
    }

    // ─── Query & Format ───

    pub fn describeChoice(self: *Ontology, concept_name: []const u8, context: OptContext, allocator: Allocator) ![]u8 {
        const concept = self.concepts.get(concept_name) orelse
            return allocator.dupe(u8, "  (concept inconnu)\n");

        var buf = std.ArrayListUnmanaged(u8){};
        const w = buf.writer(allocator);

        try std.fmt.format(w, "  \xe2\x95\x90\xe2\x95\x90\xe2\x95\x90 Ontologie: {s} \xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\n", .{concept_name});
        if (concept.parent) |p| {
            try std.fmt.format(w, "  is-a: {s}\n", .{p});
        }

        try std.fmt.format(w, "  Contexte: n\xe2\x89\x88{d}", .{context.expected_n});
        if (context.has_gpu) try w.writeAll(", GPU disponible");
        try w.writeAll("\n\n");

        // List all algorithms
        try w.writeAll("  Algorithmes connus:\n");
        var i: u8 = 0;
        while (i < concept.num_algos) : (i += 1) {
            if (concept.algorithms[i]) |algo| {
                const score = self.scoreAlgo(algo, context);
                try std.fmt.format(w, "    {s}: {s}, {s} [score={d}]\n", .{
                    algo.name, algo.time.format(), algo.space.format(), score,
                });
            }
        }

        // Best choice
        if (self.chooseBest(concept_name, context)) |best| {
            try std.fmt.format(w, "\n  \xe2\x9c\x93 Choix optimal: {s} ({s})\n", .{ best.name, best.time.format() });
        }

        // Equivalences
        if (self.getEquivalents(concept_name)) |equivs| {
            try w.writeAll("\n  Formes \xc3\xa9quivalentes:\n");
            for (equivs) |eq| {
                try std.fmt.format(w, "    \xe2\x89\xa1 {s}\n", .{eq});
            }
        }

        return buf.toOwnedSlice(allocator);
    }
};

pub const OptContext = struct {
    expected_n: u64,
    has_gpu: bool,
    max_stack: u64, // 0 = unlimited
    prefer_simple: bool,
};

/// ═══════════════════════════════════════════════════
/// L1 — NOYAU MÉTACIRCULAIRE
/// eval(quote(e)), méta-raisonnement
/// ═══════════════════════════════════════════════════
pub const MetaEngine = struct {
    allocator: Allocator,
    ontology: Ontology,

    pub fn init(allocator: Allocator) MetaEngine {
        var self = MetaEngine{
            .allocator = allocator,
            .ontology = Ontology.init(allocator),
        };
        self.bootstrap() catch {};
        return self;
    }

    pub fn deinit(self: *MetaEngine) void {
        self.ontology.deinit();
    }

    fn bootstrap(self: *MetaEngine) !void {
        // ─── Ontologie de base ───

        // Concepts mathématiques
        try self.ontology.defineConcept("Computation", null);
        try self.ontology.defineConcept("Arithmetic", "Computation");
        try self.ontology.defineConcept("Factorial", "Arithmetic");
        try self.ontology.defineConcept("Fibonacci", "Arithmetic");
        try self.ontology.defineConcept("Sort", "Computation");
        try self.ontology.defineConcept("Search", "Computation");
        try self.ontology.defineConcept("Product", "Arithmetic");

        // ─── Factorial : 3 algorithmes équivalents ───

        try self.ontology.registerAlgo("Factorial", .{
            .name = "\xce\xa0(k=1..n) k",
            .time = .linear,
            .space = .constant,
            .is_tail_recursive = false,
            .is_parallelizable = true,
            .domain_constraint = null,
        });

        try self.ontology.registerAlgo("Factorial", .{
            .name = "n * (n-1)! with n>0",
            .time = .linear,
            .space = .linear,
            .is_tail_recursive = false,
            .is_parallelizable = false,
            .domain_constraint = "n > 0",
        });

        try self.ontology.registerAlgo("Factorial", .{
            .name = "fold(*, 1, [1..n])",
            .time = .linear,
            .space = .constant,
            .is_tail_recursive = true,
            .is_parallelizable = true,
            .domain_constraint = null,
        });

        // Equivalences
        try self.ontology.declareEquivalent("Factorial", "\xce\xa0(k=1..n) k");
        try self.ontology.declareEquivalent("Factorial", "n * (n-1)! with n>0");
        try self.ontology.declareEquivalent("Factorial", "fold(*, 1, [1..n])");
        try self.ontology.declareEquivalent("Factorial", "gamma(n+1)");

        // ─── Fibonacci ───

        try self.ontology.registerAlgo("Fibonacci", .{
            .name = "fib(n-1) + fib(n-2)",
            .time = .exponential,
            .space = .linear,
            .is_tail_recursive = false,
            .is_parallelizable = false,
            .domain_constraint = "n >= 0",
        });

        try self.ontology.registerAlgo("Fibonacci", .{
            .name = "matrix_pow([[1,1],[1,0]], n)",
            .time = .logarithmic,
            .space = .constant,
            .is_tail_recursive = false,
            .is_parallelizable = false,
            .domain_constraint = "n >= 0",
        });

        try self.ontology.registerAlgo("Fibonacci", .{
            .name = "fib_iter(a=0, b=1, n)",
            .time = .linear,
            .space = .constant,
            .is_tail_recursive = true,
            .is_parallelizable = false,
            .domain_constraint = "n >= 0",
        });

        try self.ontology.declareEquivalent("Fibonacci", "fib(n-1) + fib(n-2)");
        try self.ontology.declareEquivalent("Fibonacci", "matrix_pow([[1,1],[1,0]], n)[0][1]");
        try self.ontology.declareEquivalent("Fibonacci", "fib_iter(0, 1, n)");

        // ─── Sort ───

        try self.ontology.registerAlgo("Sort", .{
            .name = "quicksort",
            .time = .linearithmic,
            .space = .logarithmic,
            .is_tail_recursive = false,
            .is_parallelizable = true,
            .domain_constraint = null,
        });

        try self.ontology.registerAlgo("Sort", .{
            .name = "mergesort",
            .time = .linearithmic,
            .space = .linear,
            .is_tail_recursive = false,
            .is_parallelizable = true,
            .domain_constraint = null,
        });

        try self.ontology.registerAlgo("Sort", .{
            .name = "insertion_sort",
            .time = .quadratic,
            .space = .constant,
            .is_tail_recursive = false,
            .is_parallelizable = false,
            .domain_constraint = null,
        });
    }

    // ─── API ───

    pub fn userDefineConcept(self: *MetaEngine, name: []const u8, parent: ?[]const u8) !void {
        try self.ontology.defineConcept(name, parent);
    }

    pub fn isA(self: *MetaEngine, child: []const u8, ancestor: []const u8) bool {
        return self.ontology.isA(child, ancestor);
    }

    pub fn optimize(self: *MetaEngine, concept: []const u8, n: u64) ![]u8 {
        const ctx = OptContext{
            .expected_n = n,
            .has_gpu = false,
            .max_stack = 0,
            .prefer_simple = n < 20,
        };
        return self.ontology.describeChoice(concept, ctx, self.allocator);
    }

    pub fn optimizeGPU(self: *MetaEngine, concept: []const u8, n: u64) ![]u8 {
        const ctx = OptContext{
            .expected_n = n,
            .has_gpu = true,
            .max_stack = 0,
            .prefer_simple = false,
        };
        return self.ontology.describeChoice(concept, ctx, self.allocator);
    }
};
